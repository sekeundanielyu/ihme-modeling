###########################################################
### Date: 2/4/16
### Project: Metabolics
### Purpose: Crosswalk different diagnostic criteria to means
### Notes: 
###
###
###		The goal this crosswalk is to prep microdata for the training set used to
###   convert prevalence estimate of sbp (hypertension), fpg (diabetes), chl (hypercholesterolemia)
###		from standard and non-standard definitions to the mean
###		
###		Hypertension = SBP > 140 | DBP > 90 & treatment == 1
###		Diabetes = FPG > 7.0 mmol/l & treatment == 1
###		Hypercholesterolemia = CHL > 5.0 mmol/l & treatment == 1
###
###
###		Structure:
###			- Loop through ubcov extracted microdata 
###			- Bring in template which has all the DC that need to be crosswalked
###     - Using those criteria, mark binaries if individual satifies critiera
###     - Calculate proportion at given definitions + mean
###	
###
###########################################################



###################
### Setting up ####
###################

library(dplyr)
library(data.table)
library(ggplot2)
library(lme4)
library(car)
library(sjPlot)
library(sjmisc)
library(gridExtra)
library(grid)

## OS locals
  rm(list=objects())
      os <- .Platform$OS.type
      if (os == "windows") {
        jpath <- "J:/"
      } else {
        jpath <- "/home/j/"
      }

## Paths
code_root <- paste0(unlist(strsplit(getwd(), "metabolics"))[1], "metabolics/code")
data_root <- fread(paste0(code_root, "/root.csv"))[, data_root]

## Resources
source(paste0(code_root, "/extraction/exp/resources/db_tools.r"))

## Utility
inv.delta.log <- function(data, var) {
	return(var / (1/(data)^2))
}

#####################################################################
### Load and setup
#####################################################################

## Load microdata frame of different diagnostic criteria
cw_frame <- readRDS(paste0(data_root, "/extraction/output/processing/cw_prep.rds"))

## Load literature to be crosswalked
df <- readRDS(paste0(data_root, "/extraction/output/processing/literature.rds"))

#####################################################################
### Reshape literature data so wide on diagnostic criteria by source
#####################################################################

## Set variables to be merged with
reshape_vars <- c("nid", "file_path", 
                "ihme_loc_id", "smaller_site_unit", "site_memo", 
                "year_id", "sex_id", "age_start", "age_end", "me_name", grep("cv_", names(df), value=T))
## Remove cv_dc_cw and cv_dc_orig from the reshape vars
reshape_vars <- setdiff(reshape_vars, c("cv_dc_cw", "cv_dc_orig"))

## Remove duplicates
df <- df[!duplicated(df[, c(reshape_vars, "dc_short"), with=F])]

## Mark dc_short as mean if mean data
df <- df[dc_condition == "mean", dc_short := me_name]

## Reshape wide on the dignostic criteria
cast <- as.formula(paste0(paste(reshape_vars, collapse=" + "), " ~ dc_short"))
df.w <- dcast(df, cast, value.var=c("data", "standard_error", "sample_size"))

## Which data points have what measure of prev or mean?
data_cols <- grep("data_", names(df.w), value=T)

## For each column, add to list of definitions if data not missing
df.w <- df.w[, dc_list := NA]
for (var in data_cols) df.w <- df.w[, dc_list := ifelse(!is.na(get(var)), paste0(dc_list, ";", var), paste0(dc_list))]
df.w <- df.w[, dc_list := gsub("NA;", "", dc_list)]

## Set mid_age and mid_age_group
df.w <- df.w[, mid_age := (age_start + age_end)/2]
df.w <- df.w[, mid_age_group_id := round(mid_age/5) + 5]
df.w <- df.w[mid_age_group_id > 21 , mid_age_group_id := 21]
df.w <- df.w[mid_age_group_id < 11 , mid_age_group_id := 11]

## Separate points with mean and not (to_cw)
df.w <- df.w[!is.na(data_chl) | !is.na(data_sbp) | !is.na(data_fpg), has_mean := 1]
df.w <- df.w[is.na(has_mean), has_mean := 0]
mean_frame <- df.w[has_mean==1]
to_cw <- df.w[has_mean==0]


#####################################################################
### Setup for crosswalk of diag criteria to mean
#####################################################################

################################
## Clean up cw_frame 
################################

cols <- names(cw_frame)[!names(cw_frame) %in% c("nid", "ihme_loc_id", "start_year", "end_year", "age_group_id", "sex_id")]
setnames(cw_frame, cols, paste0("data_", cols))
cw_frame <- cw_frame[, year_id := floor((start_year + end_year)/2)]


################################
## Create training frame
################################

## Append mean onto cw_frame
training <- cw_frame

## Clean up training frame to only what is needed
cols <- c("nid","ihme_loc_id", "year_id", "age_group_id", "sex_id", grep("data_", names(training), value=T))
training <- training[, cols, with=F]

## Use mid_age_group_id from literature as age_group_id
training <- training[!is.na(age_group_id), mid_age_group_id := age_group_id]

## Grab location vars
locs <- get_location_hierarchy(74)[, .(location_id, ihme_loc_id, region_id, region_name, super_region_id, super_region_name)]

## Merge
training <- merge(training, locs, by="ihme_loc_id", all.x=T)


######################################################################
#### Crosswalks
######################################################################


################################
## Crosswalk Functions
################################

## RMSE Function

run.oos.rmse <- function(df, prop_train, model, reps) {

	lapply(1:reps, function(x) {
		## Split
		set.seed(x)
		train_index <- sample(seq_len(nrow(df)), size = floor(prop_train * nrow(df)))
		train <- df[train_index]
		test <- df[-train_index]
		## Model
		mod <- lmer(as.formula(model), data=train)
		## Predict
		prediction <- predict(mod, newdata=test, allow.new.levels=TRUE) %>% exp
		## Detect variable of interest by parsing on "~"
		var <- strsplit(model, "~")[[1]][1] %>% str_trim
		## Strip the log
		var <- strsplit(var, "log[(]|[)]")[[1]][2]
		## RMSE
		rmse <- sqrt(mean((prediction-test[[var]])^2, na.rm=T))
		return(rmse)
	}) %>% unlist %>% mean 

}

## Crosswalk function

run.crosswalk <- function(training, to_cw, prev_var, mean_var, model) {

print(paste0("Starting crosswalk for: ", prev_var))

## Subset
subset <- training[!is.na(get(mean_var)) & !is.na(get(prev_var))]

## Put range on prev
subset <- subset[get(prev_var) < 1 & get(prev_var) > 0]

## Number of points
n_in_cw <- nrow(subset)
n_to_cw <- nrow(to_cw[!is.na(get(prev_var))])

## Run model
defaultmodel <- paste0("log(", mean_var, ")", " ~ logit(", prev_var, ") + (1|super_region_name)")
mod <- lmer(defaultmodel, data=subset)

## RMSE
is.rmse <- rmse(mod) %>% exp
oos.rmse <- run.oos.rmse(df=subset, prop_train=0.8, model=defaultmodel, reps=10)

## Summary table
table <- data.table(prev_var, mean_var, n_in_cw, n_to_cw, is.rmse, oos.rmse) %>% t

## Plots
	## Scatter
	p.scatter <- ggplot(subset) + 
		geom_point(aes(y=get(mean_var), x=get(prev_var), color=super_region_name)) +
		ggtitle(paste0(prev_var, " vs ", mean_var))
	## Residuals
	p.resid <- plot(mod)
	## Fixed effects
	p.fe <- sjp.lmer(mod, type="fe", y.offset = .2, showIntercept = FALSE, printPlot=FALSE)
	## Random effects
	p.re <- sjp.lmer(mod, type="re", y.offset = .2, facet.grid=TRUE, sort.coef="(Intercept)", printPlot=FALSE)
	## Table
	mytheme <- gridExtra::ttheme_default(
    	core = list(fg_params=list(cex = 1.5)),
    	colhead = list(fg_params=list(cex = 2)),
    	rowhead = list(fg_params=list(cex = 2)))
	p.table <- tableGrob(table, theme=mytheme)

	## Arrange
	
	plots <- arrangeGrob(
				arrangeGrob(
					arrangeGrob(p.scatter, p.resid, nrow=2),
					p.table, nrow=1, widths=c(2,1)
					),
				 arrangeGrob(p.fe$plot
				 	),
				 arrangeGrob(p.re$plot.list[[1]]
				 			nrow=1
				 	),
				 nrow=3,		 
				 heights=c(4, 3, 3),
				 top = textGrob(prev_var,gp=gpar(fontsize=20, font=3))
				 )
	
	
print(paste0("Completed crosswalk for: ", prev_var))

return(list(mod=mod, table=table, plots=plots))

}


################################
## Run Crosswalk
################################

## Grab list of crosswalks to run
prev_list <- grep("data_", names(training), value=T)
prev_list <- prev_list[!prev_list %in% c("data_sbp", "data_fpg", "data_cholesterol", "data_chl", "data_hba1c")]

## Run Crosswalks
cw_out <- NULL
for (me in c("sbp", "fpg", "chl")) {  

	## Parse them by category
	if (me == "sbp") sub_str <- "sbp|dbp"
	if (me == "chl") sub_str <- "chl"
	if (me == "fpg") sub_str <- "fpg|hba1c"
	prev_vars <- grep(sub_str, prev_list, value=T)
	mean_var <- paste0("data_", me)

	## Don't proceed with crosswalk if....
	drop_cw <- NULL
	for (i in 1:length(prev_vars)) {
		## Not in list of to_cw 
		if (!prev_vars[i] %in% names(to_cw)) {
			drop_cw <- c(drop_cw, i)
		## In list, but 0 observations
		} else if (nrow(training[!is.na(get(prev_vars[i]))]) < 1) {
			drop_cw <- c(drop_cw, i)
		## In to_cw but 0 observations
		} else if (nrow(to_cw[!is.na(get(prev_vars[i]))]) < 1) {
			drop_cw <- c(drop_cw, i)i<3mooncakes!!!

		}
	}
	## Drop
	if (!is.null(drop_cw)) prev_vars <- prev_vars[-drop_cw]

	## Run crosswalk
	cw_out[[me]] <- lapply(prev_vars, function(x) run.crosswalk(training=training, 
															to_cw=to_cw, 
															prev_var=x, mean_var=mean_var))

	## Save diagnostic graphs
	pdf(paste0(jpath, "/WORK/05_risk/risks/metabolics/diagnostics/exp/crosswalks/prev_to_mean/", me, ".pdf"), w=30, h=20)
	for (i in 1:length(cw_out[[me]])) grid.arrange(cw_out[[me]][[i]]$plot)
	dev.off()

}
	
################################
## Apply Crosswalk
################################


## Grab location vars
locs <- get_location_hierarchy(74)[, .(location_id, ihme_loc_id, region_id, region_name, super_region_id, super_region_name)]

## Merge
to_cw <- merge(to_cw, locs, by="ihme_loc_id", all.x=T)

## Predict
for (me in c("sbp", "fpg", "chl")) {
	for (i in 1:length(cw_out[[me]])) {
		## Grab objects
		prev_var <- cw_out[[me]][[i]]$table[1]
		mean_var <- cw_out[[me]][[i]]$table[2]
		sample_var <- paste0("sample_size_", gsub("data_", "", prev_var))
		mod <- cw_out[[me]][[i]]$mod
		## Predict
		to_cw <- to_cw[!is.na(get(prev_var)), mean := predict(mod, newdata=to_cw[!is.na(get(prev_var))], allow.new.levels=TRUE) %>% exp]
		## Transfer sample size
		to_cw <- to_cw[!is.na(get(prev_var)), sample_size := get(sample_var)]
		## Mark which cw was done
		to_cw <- to_cw[!is.na(get(prev_var)), cv_dc_orig := gsub("data_", "", prev_var)]
		to_cw <- to_cw[!is.na(get(prev_var)), cv_dc_cw := 1]
		## Prediction error
		## PUT IN RE prediction error
		r.var <- attr(VarCorr(mod), "sc")^2
		fe.var <- var(predict(mod, re.form=NA))
	}
}

#####################################################################
### Output
#####################################################################

## Clean to_cw
cols <- c("nid", "file_path", 
                "ihme_loc_id", "smaller_site_unit", "site_memo", 
                "year_id", "sex_id", "age_start", "age_end", "me_name", grep("cv_", names(to_cw), value=T), "mean", "sample_size")
crosswalked <- to_cw[, cols, with=F]
crosswalked <- crosswalked[!is.na(mean)]

## Clean mean_frame
for (me in c("sbp", "fpg", "chl")) {
	mean_frame <- mean_frame[me_name==me, mean := get(paste0("data_", me))]
	mean_frame <- mean_frame[me_name==me, sample_size := get(paste0("sample_size_", me))]
	mean_frame <- mean_frame[me_name==me, standard_error := get(paste0("standard_error_", me))]
}

cols <- c("nid", "file_path", 
                "ihme_loc_id", "smaller_site_unit", "site_memo", 
                "year_id", "sex_id", "age_start", "age_end", "me_name", grep("cv_", names(mean_frame), value=T), "mean", "sample_size", "standard_error")
mean_frame <- mean_frame[, cols, with=F]

## Cleaned lit
lit_out <- rbind(crosswalked, mean_frame, fill=TRUE)



