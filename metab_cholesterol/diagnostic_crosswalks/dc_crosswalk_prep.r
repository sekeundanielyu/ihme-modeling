###########################################################
### Date: 2/4/16
### Project: Metabolics
### Purpose: Crosswalk prep for non-standard diagnostic criteria to std for prevalence
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
###########################################################



###################
### Setting up ####
###################

library(dplyr)
library(data.table)
library(haven)
library(ggplot2)
library(survey)


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
microdata_root <- paste0(jpath, "/temp/pyliu/metabolics/extraction/microdata/ubcov_output/")


#####################################################################
### Load and clean diagnostic criteria to be crosswalked
#####################################################################

## Clean diagnostics
diag <- fread(paste0(code_root, "/extraction/exp/resources/dc_to_crosswalk.csv"))[dc_condition != ""]
diag <- diag[, dc_short := gsub(">|[|]", "_", dc_condition)]
diag <- diag[, dc_short := gsub("rx==1", "rx", dc_short)]
## Replace dc_rx with that of the me so I can use it more easily
for (me in c("fpg", "sbp", "chl")) {
    diag <- diag[me_name == me, dc_condition := gsub("rx", paste0(me, "_rx"), dc_condition)]
}

#####################################################################
### Iterate through microdata
#####################################################################

## Append files together
files <- list.files(microdata_root, pattern=".dta", full.names=T, recursive=T)

#####################################################################
### Open and clean microdata
#####################################################################

prev_data <- NULL

for (file in files) {

df <- read_stata(file) %>% data.table

## Proceed if has sbp, dbp, fpg, hba1c or chl
if (any(c("metab_sbp", "metab_dbp", "metab_fpg", "metab_hba1c", "metab_chl") %in% names(df))) {

## Name cleaning
setnames(df, names(df), gsub("ihme_|metab_", "", names(df)))
if ("a1c" %in% names(df)) setnames(df, "a1c", "hba1c")

## Subset
cols <- c("loc_id", "nid", "start_year", "end_year", "strata", "psu", "pweight", "male", "age_yr", "sbp", "dbp", "fpg", "hba1c", "chl", "hyperten_drug", "diabetes_drug", "diabetes_insulin", "high_chl_drug")
for (col in cols) if (!col %in% names(df)) df <- df[, (col) := NA]
df <- df[, cols, with=F]
setnames(df, "loc_id", "ihme_loc_id")

## Keep if age >= 25
df <- df[age_yr >=25,]

## If on treatment
df <- df[diabetes_insulin == 1, diabetes_drug := 1]
old <- c("hyperten_drug", "diabetes_drug", "high_chl_drug")
new <- c("sbp_rx", "fpg_rx", "chl_rx")
setnames(df, old, new)

## Set rx to 0 if measured but no response
for (me in c("fpg", "chl")) df <- df[!is.na(get(paste0(me))) & is.na(get(paste0(me, "_rx"))), (paste0(me, "_rx")) := 0]
df <- df[!is.na(sbp) & !is.na(dbp) & is.na(sbp_rx), sbp_rx := 0]

#####################################################################
### Apply definitions to the microdata
#####################################################################

## Create binary if condition is met
for (i in 1:nrow(diag)) df[, (diag$dc_short[i]) := as.numeric(eval(parse(text=diag$dc_condition[i])))]

#####################################################################
### Calculate prev
#####################################################################

  #####################################################################
  ### Setup
  #####################################################################

  ## Create a new list of vars that aren't completely missing
  vars <- NULL
  for (col in diag$dc_short) if (!all(is.na(df[[col]]))) vars <- c(vars, col)
  for (me in c("sbp", "chl", "fpg", "hba1c")) if (!all(is.na(df[[me]]))) vars <- c(vars, me)

  ## Sex
  df <- df[, sex_id := ifelse(male==1, 1, 2)]

  ## Age
  df <- df[, age_group_id := round((age_yr + 25)/5)]
  df <- df[age_yr > 80, age_group_id := 21]


  #####################################################################
  ### Estimate (put in svy design stuff later...sorry!)
  #####################################################################

  ## Calculate means
  df <- df[, (vars) := lapply(.SD, function(x) mean(x, na.rm=T)), .SDcols=vars, by=c("age_group_id", "sex_id")]

  #####################################################################
  ### Clean
  #####################################################################
  
  ## Keep loc, year
  out <- df[, c("nid", "ihme_loc_id", "start_year", "end_year", "age_group_id", "sex_id", vars), with=F] %>% unique

  ## Append
  prev_data <- rbind(prev_data, out, fill=T)

}

}

#####################################################################
### Save prev
#####################################################################

saveRDS(prev_data, paste0(data_root, "/extraction/output/processing/cw_prep.rds"))



