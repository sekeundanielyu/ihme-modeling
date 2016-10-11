###########################################################
### Project: ubCov
### Purpose: Linear Prior
###########################################################

###################
### Setting up ####
###################
library(data.table)
library(lme4)

###################################################################
# Prior Blocks
###################################################################

prep_df <- function(run_id, kos) {

	## Load objects
	df <- model_load(run_id, "prepped")
	square <- model_load(run_id, "square")
	if (kos > 0) ko.df <- model_load(run_id, "kos")

	## Study level covariates
	covs <- grep("cv_", names(df), value=T)

	## Square things
	square.names <- names(square)[!names(square) %in% df]
	## Generate has_level_n flag for subnationals
	levels <- ifelse(!is.na(square)[, grep("level_", names(square))], 1, 0)
	colnames(levels) <- paste0("has_", colnames(levels))
	square <- cbind(square, levels)

	## Kos
	if (kos > 0) {
		ko_list <- c(0, seq(1:kos))
		df <- merge(df, ko.df, by=c("data_id"))
	} else {
		ko_list <- 0
		df <- df[, train0 := 1]
	}

	## Create list of knockouts
	df_list <- lapply(ko_list, function(x) df[paste0("train", x) >= 1, 
		c("location_id", "year_id", "age_group_id", "sex_id", "data", "variance", covs), with=F])

	## Merge on square
	df_list <- lapply(ko_list, function(x) merge(square, df_list[[x+1]], by=c("location_id", "year_id", "age_group_id", "sex_id"), all.x=T))

	return(df_list)
}


run_model <- function(df, model, type) {	
	
	if (type == "lm") mod <- lm(as.formula(paste0(model)), data=df, na.action=na.omit)
		
	if (type == "lmer") mod <- lmer(as.formula(paste0(model)), data=df, na.action=na.omit)
	
	return(mod)
}

fe_table <- function(mod) {
	Vcov <- vcov(mod, useScale = FALSE)
	betas <- fixef(mod)
	se <- sqrt(diag(Vcov))
	zval <- betas / se
	table <- cbind(betas, se, zval)
	return(table)
}

re_list <- function(re, obj) {
	## Grab random effects
	x <- re[[obj]]
	pv   <- attr(x, "postVar")
	cols <- 1:(dim(pv)[1])
	var   <- unlist(lapply(cols, function(i) pv[i, i, ]))
	ord  <- unlist(lapply(x, order)) + rep((0:(ncol(x) - 1)) * nrow(x), each=nrow(x))
	## Make frame
	pDf <- data.table(beta=unlist(x)[ord],
	                  se=sqrt(var[ord]),
	                  id=rep(rownames(x), ncol(x))[ord], 
	                  re=gl(ncol(x), nrow(x), labels=names(x))
	                )
	## Convert ind to numeric if possible
	if (length(pDf[!is.na(id),id]) == length(pDf[!is.na(suppressWarnings(as.numeric(pDf$id))), id])) pDf[, id := as.numeric(id)]
	## Clean ind var
	pDf[,re := gsub("[(]|[)]", "", re)]
	## Making a column for indicator so can return whole thing as a list
	pDf <- cbind(var=obj, pDf)
    ## Column order
    setcolorder(pDf, c('var', 're', 'id', 'beta', 'se'))
	return(pDf)
}
                       
re_table <- function(mod) {
    re <- ranef(mod, condVar=T)
    table <- lapply(names(re), re_list, re=re) %>% rbindlist
    return(table)
}   

set_study_covs <- function(df, study_covs) {
	covs<- lapply(study_covs, function(x) strsplit(x,"#")) %>% data.frame
	for (i in ncol(covs)) {
    	df <- df[, (covs[1,i] %>% as.character) := covs[2,i]]
    	print(paste0("Set study level covariate: ", covs[1,i], " | Reference value: ", covs[2,i]))
	} 
	return(df)
}


run_predict <- function(df, model, type, predict_re=0) {
	## Predict
	if (type == "lm") {
		prior <- predict(model, newdata=df)
	}
	if (type == "lmer") {
		if (predict_re == 1) {
			re.form <- NULL
		} else {
			re.form <- NA
		}
		prior <- predict(model, newdata=df, allow.new.levels=T, re.form=re.form)
	}
	return(prior)
}

model_predict <- function(df, prior_model, model_type, predict_re, study_covs=NULL, no.subnat=TRUE) {
	for (sex in unique(df$sex_id)) {
		## Model
		if (no.subnat) mod <- run_model(df[sex_id==sex & level == 3], prior_model, model_type)
		if (!no.subnat) mod <- run_model(df[sex_id==sex], prior_model, model_type)
		## Set study covs
		if (!is.blank(study_covs)) df[sex_id == sex] <- set_study_covs(df[sex_id==sex], study_covs)
		## Predict
		df <- df[sex_id == sex, prior := run_predict(df[sex_id == sex,], mod, model_type, predict_re)]
		## Stats
	}
	return(df)
}

clean_prior <- function(df) {

	cols <- c("location_id", "year_id", "sex_id", "age_group_id", "prior")
	return(df[, cols, with=F] %>% unique)

}


###################################################################
# Prior Process
###################################################################


run_prior <- function(get.df=FALSE) {

	## Prep frame
	df_list <- prep_df(run_id, kos)

	## Run regression by sex
	df_list <- mclapply(df_list, function(x) model_predict(x, prior_model, model_type, predict_re), mc.cores=4)

	## Clean
	df_list <- lapply(df_list, clean_prior)

	## Save temp file
	if (!get.df) model_save(df_list, run_id, "prior")
	if (get.df) return(df_list)
}

###################################################################
# Spacetime Blocks
###################################################################


calculate_mad <- function(location_id, data, prediction, level) {

	## Setup
	resid <- abs(data - prediction)
	df <- data.table(location_id, resid)

	## Merge location hierarchy
	hierarchy <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)
	hierarchy <- hierarchy[, grep("location_id|level", names(hierarchy)), with=F]
	df <- merge(df, hierarchy, by="location_id", all.x=T)

	## Calculate MAD across levels
	levels <- as.numeric(gsub("level_", "", grep("level_", names(hierarchy), value=T)))
	for (lvl in levels) {
		df[, paste0("mad_level_", lvl) := median(resid, na.rm=T), by=eval(paste0("level_", lvl))]
		## Its treating NA's as a category make these missing if the location level is < mad level
		df[level < lvl, paste0("mad_level_", lvl) := NA]
	}

	## Iteratively replace with MAD from a higher level if missing (except for global)
	for (lvl in levels[!levels %in% 0]) {
		df[is.na(get(paste0("mad_level_", lvl))), paste0("mad_level_", lvl) := get(paste0("mad_level_", lvl-1))]
	}

	## Return MAD at the specified level
	mad <- df[, paste0("mad_level_", level), with=F]

	return(mad)

}

nsv <- function(residual, variance) {
	N = length(residual[!is.na(residual)])
	inv_var = 1 / variance
	sum_wi = sum(inv_var, na.rm=T)
	sum_wi_xi = sum( residual * inv_var, na.rm=T) 
	weighted_mean = sum_wi_xi / sum_wi
	norm_weights = N * inv_var / sum_wi
	nsv = 1/(N-1) * sum(norm_weights * (residual - weighted_mean)**2, na.rm=T)
	return(nsv)
}

calculate_nsv <- function(location_id, data, prediction, variance, threshold) {

	## Setup
	resid <- data - prediction
	df <- data.table(location_id, resid, variance)

	## Merge location hierarchy
	hierarchy <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)
	hierarchy <- hierarchy[, grep("location_id|level", names(hierarchy)), with=F]
	df <- merge(df, hierarchy, by="location_id", all.x=T)

	## Count the number of data points at each level
	levels <- as.numeric(gsub("level_", "", grep("level_", names(hierarchy), value=T)))
	for (lvl in levels) { 
		df[, paste0("count_", lvl) := sum(!is.na(resid)), by=eval(paste0("level_", lvl))]
		## Its treating NA's as a category make these missing if the location level is < mad level
		df[level < lvl, paste0("count_", lvl) := NA]
	}

	## Calculate nsv at each level
	for (lvl in levels) { 
		df[, paste0("nsv_", lvl) := nsv(resid, variance), by=eval(paste0("level_", lvl))]
		## Its treating NA's as a category make these missing if the location level is < mad level
		df[level < lvl, paste0("nsv_", lvl) := NA]
	}

	## Replace with nsv at lowest level where number of data exceeds the threshold
	for (lvl in levels) {
		df[get(paste0("count_", lvl)) > threshold, nsv := get(paste0("nsv_", lvl))]
	}

	return(df$nsv)

}



###################################################################
# Spacetime Process
###################################################################


run_spacetime <- function(logs=NULL) {

	## Check if prior exists
	if (!('prior' %in% h5ls(paste0(run_root, "/temp.h5"))$name)) stop("Missing prior in ~/temp.h5")

	## Run spacetime
	script <- paste0(model_root, "/spacetime.py")
	if (parallel) {
		slots <- 6
		memory <- 12
		locs <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)[level >= 3 & level <6,]$location_id
		loc_ranges <- split_args(locs, nparallel)
		file_list <- NULL
		for (i in 1:nparallel) {
			loc_start <- loc_ranges[i, 1]
			loc_end <- loc_ranges[i, 2]
			file_list <- c(file_list, paste0(run_root, "/st_temp/", loc_start, "_", loc_end, ".csv"))
			args <- paste(run_root, model_root, parallel, loc_start, loc_end, sep=" ")
			qsub(job_name=paste("st", run_id, loc_start, loc_end, sep="_"), script=script, slots=slots, memory=memory, arguments=args, cluster_project=cluster_project, logs=logs)
		}
		job_hold(paste0("st_", run_id), file_list = file_list)
		## Bring in and clean
		vars <- c("location_id", "year_id", "age_group_id", "sex_id")
		st <- mclapply(paste0(run_root, "/st_temp/") %>% list.files(.,full.names=T), fread, mc.cores=cores) %>% rbindlist
		st <- st[order(location_id, year_id, age_group_id, sex_id)]
		st <- st[, (vars) := lapply(.SD, as.numeric), .SDcols=vars]
		## Save
		model_save(st, run_id, 'st')
		unlink(paste0(run_root, "/st_temp/"), recursive=T)
	} else {
		slots <- 30
		memory <- 60
		args <- paste(run_root, model_root, parallel, sep=" ")
		qsub(job_name=paste0("st_", run_id), script=script, slots=slots, memory=memory, arguments=args, cluster_project=cluster_project, logs=logs)
		job_hold(paste0("st_", run_id), file_list=model_path(run_id, 'st'))
		st <- model_load(run_id, 'st')
	}

	## Merge on data
	data <- model_load(run_id, 'prepped')
	df <- merge(st, data, by=c("location_id", "year_id", "age_group_id", "sex_id"), all.x=T)

	## Calculate MAD
	df <- df[, st_amp := calculate_mad(location_id, data, st, gpr_amp_unit), by="sex_id"] 

	## Calculate NSV
	df <- df[, nsv := calculate_nsv(location_id, data, st, variance, threshold=5), by="sex_id"] 
	df <- df[, variance := variance + nsv]

	## Save data
	data_save <- df[!is.na(data_id), c(names(data), "nsv"), with=F]
	model_save(data_save, run_id, 'adj_data')
	
	## Save st_amp
	st_amp <- unique(df[, .(location_id, year_id, age_group_id, sex_id, st_amp)])
	model_save(st_amp, run_id, 'st_amp')

}


###################################################################
# GPR Process
###################################################################

run_gpr <- function(logs=NULL) {

	## Check file
	if (!('st' %in% h5ls(paste0(run_root, "/temp.h5"))$name)) stop("Missing st in ~/temp.h5")

	## Run GPR
	script <- paste0(model_root, "/gpr.py")
	if (parallel) {
		slots <- 5
		memory <- 10
		locs <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)[level >= 3 & level <6,]$location_id
		loc_ranges <- split_args(locs, nparallel)
		file_list <- NULL
		for (i in 1:nparallel) {
			loc_start <- loc_ranges[i, 1]
			loc_end <- loc_ranges[i, 2]
			file_list <- c(file_list, paste0(run_root, "/gpr_temp/", loc_start, "_", loc_end, ".csv"))
			args <- paste(run_root, model_root, draws, parallel, loc_start, loc_end, sep=" ")
			qsub(job_name=paste("gpr", run_id, loc_start, loc_end, sep="_"), script=script, slots=slots, memory=memory, arguments=args, cluster_project=cluster_project, logs=logs)
		}
		job_hold(paste0("gpr_", run_id), file_list = file_list)
		if (draws == 0) {
			gpr <- mclapply(paste0(run_root, "/gpr_temp/") %>% list.files(.,full.names=T), fread, mc.cores=cores) %>% rbindlist
			## Bring in and clean
			vars <- c("location_id", "year_id", "age_group_id", "sex_id")
			gpr <- gpr[order(location_id, year_id, age_group_id, sex_id)]
			gpr <- gpr[, (vars) := lapply(.SD, as.numeric), .SDcols=vars]
			model_save(gpr, run_id, 'gpr')
			unlink(paste0(run_root, "/gpr_temp/"), recursive=T)
		}
	} else {
		slots <- 30
		memory <- 60
		args <- paste(run_root, model_root, draws, parallel, sep=" ")
		qsub(job_name=paste0("gpr_", run_id), script=script, slots=slots, memory=memory, arguments=args, cluster_project=cluster_project, logs=logs)
		job_hold(paste0("gpr_", run_id), file_list=model_path(run_id, 'gpr'))
	}

}







