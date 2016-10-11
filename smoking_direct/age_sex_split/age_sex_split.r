###########################################################
### AGE SEX SPLIT
###########################################################

###################
### Setting up ####
###################
rm(list=objects())
library(data.table)
library(dplyr)


## OS locals
os <- .Platform$OS.type
if (os == "windows") {
  jpath <- "J:/"
} else {
  jpath <- "/home/j/"
}


## Resources
source(paste0(jpath, "WORK/05_risk/risks/metab_bmi/bmi_code/db_tools/db_tools.r"))

#####################################################################
### Pull population estimates
#####################################################################

## Pull populations
dbname <- strConnection
host <- strConnection
query <-  strQuery
pops <- run_query(dbname, host, query)
pops <- pops[, age_start := round(age_start)]


#####################################################################
### Define function
#####################################################################

age_sex_split <- function(df, location_id, year_id, age_start, age_end, sex, estimate, sample_size) {

###############
## Setup 
###############

## Generate unique ID for easy merging
df[, split_id := 1:.N]

## Make sure age and sex are int
cols <- c(age_start, age_end, sex)
df[, (cols) := lapply(.SD, as.integer), .SDcols=cols]

## Save original values
orig <- c(age_start, age_end, sex, estimate, sample_size)
orig.cols <- paste0("orig.", orig)
df[, (orig.cols) := lapply(.SD, function(x) x), .SDcols=orig]

## Separate metadata from required variables
cols <- c(location_id, year_id, age_start, age_end, sex, estimate, sample_size)
meta.cols <- setdiff(names(df), cols)
metadata <- df[, meta.cols, with=F]
data <- df[, c("split_id", cols), with=F]

## Round age groups to the nearest 5-y boundary
data[, age_start := age_start - age_start %%5]
data <- data[age_start > 80, (age_start) := 80]
data[, age_end := age_end - age_end %%5 + 4]
data <- data[age_end > 80, age_end := 84]

## Split into training and split set
training <- data[(age_end - age_start) == 4 & sex_id %in% c(1,2)]
split <- data[(age_end - age_start) != 4 | sex_id == 3]


###################
## Age Sex Pattern
###################

# Determine relative age/sex pattern
asp <- aggregate(training[[estimate]],by=lapply(training[,c(age_start, sex), with=F],function(x)x),FUN=mean,na.rm=TRUE)
names(asp)[3] <- "rel_est"

# Fill NAs with values from adjacent age/sex groups
asp <- dcast(asp, formula(paste0(age_start," ~ ",sex)), value.var="rel_est")
asp[is.na(asp[[1]]), 1] <- asp[is.na(asp[[1]]),2]
asp[is.na(asp[[2]]), 2] <- asp[is.na(asp[[2]]),1]
asp <- melt(asp,id.var=c(age_start), variable.name=sex, value.name="rel_est")
asp[[sex]] <- as.integer(asp[[sex]])

##########################
## Expand rows for splits
##########################

split[, n.age := (age_end + 1 - age_start)/5]
split[, n.sex := ifelse(sex_id==3, 2, 1)]

## Expand for age 
split[, age_start_floor := age_start]
expanded <- rep(split$split_id, split$n.age) %>% data.table("split_id" = .)
split <- merge(expanded, split, by="split_id", all=T)
split[, age.rep := 1:.N - 1, by=.(split_id)]
split[, (age_start):= age_start + age.rep * 5 ]
split[, (age_end) :=  age_start + 4 ]

## Expand for sex
split[, sex_split_id := paste0(split_id, "_", age_start)]
expanded <- rep(split$sex_split_id, split$n.sex) %>% data.table("sex_split_id" = .)
split <- merge(expanded, split, by="sex_split_id", all=T)
split <- split[sex_id==3, (sex) := 1:.N, by=sex_split_id]

##########################
## Perform splits
##########################

## Merge on population and the asp, aggregate pops by split_id
split <- merge(split, pops, by=c("location_id", "year_id", "sex_id", "age_start"), all.x=T)
split <- merge(split, asp, by=c("sex_id", "age_start"))
split[, pop_group := sum(pop_scaled), by="split_id"]

## Calculate R, the single-group age/sex estimate in population space using the age pattern from asp
split[, R := rel_est * pop_scaled]

## Calculate R_group, the grouped age/sex estimate in population space
split[, R_group := sum(R), by="split_id"]

## Split 
split[, (estimate) := get(estimate) * (pop_group/pop_scaled) * (R/R_group) ]

## Split the sample size
split[, (sample_size) := sample_size * pop_scaled/pop_group]

## Mark as split
split[, cv_split := 1]

#############################################
## Append training, merge back metadata, clean
#############################################

## Append training, mark cv_split
out <- rbind(split, training, fill=T)
out <- out[is.na(cv_split), cv_split := 0]

## Append on metadata
out <- merge(out, metadata, by="split_id", all.x=T)

## Clean
out <- out[, c(meta.cols, cols, "cv_split", "n.sex", "n.age"), with=F]
out[, split_id := NULL]
    
}

