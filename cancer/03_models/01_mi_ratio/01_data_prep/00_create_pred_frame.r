################################################################################

## Description: Save full prediction frame for MI ratio models

################################################################################
## Declare if SDS file should be updated from database
  refresh_sds = FALSE

## Import Libraries
  library(plyr)
  library(reshape2)

################################################################################
## Set Data Locations and Load the Input Data (AUTORUN)
################################################################################
## Set root directory and working directory 
  root <- ifelse(Sys.info()[1]=='Windows', 'J:/', '/home/j/')
  cancer_folder =  paste0(root, 'WORK/07_registry/cancer')
  wkdir = paste0(cancer_folder, '/03_models/01_mi_ratio')
  setwd(wkdir)

## Set paths
  save_location = paste0(cancer_folder, '/03_models/01_mi_ratio/02_data')
  locations_modeled <- paste0(cancer_folder, '/00_common/data/modeled_locations.csv')
  wealth_covariates <- './02_data/sds.csv'

# ################################################################################
# ## GET NEW SDS DATA
# ################################################################################
if(refresh_sds){
  old_sds_file <- './02_data/previous_sds.csv'
  if (file.exists(old_sds_file)) {unlink(old_sds_file)}
  if (file.exists(wealth_covariates)) {file.rename(wealth_covariates, old_sds_file)}
  system(paste0('python ', wkdir, '/01_code/01_data_prep/get_sds.py'))
  while (!file.exists(wealth_covariates)) {Sys.sleep(1)}
}
################################################################################
## CREATE PREDICTION FRAME
################################################################################
## Get modeled locations
 ihme_cc <- read.csv(locations_modeled) 
 ihme_cc$model[ihme_cc$parent_type == "region"] <- 1
 ihme_cc <- ihme_cc[ihme_cc$model == 1, c('location_id', 'ihme_loc_id',	'parent_id',	'location_name',	'super_region_id',	'super_region_name',	'region_id',	'region_name',	'developed')]

## Set location, year, age, and sex parameters for the prediction frame
  locations <- unique(ihme_cc$location_id)
  years <- 1970:2015
  age_groups <- as.factor(seq(0, 80, by = 5))
  sexes <- c('male', 'female')
  pred_frame <- expand.grid(locations, years, age_groups, sexes)
  names(pred_frame) <- c('location_id', 'year', 'age', 'sex')
  pred_frame <- merge(pred_frame, ihme_cc, by = 'location_id', all.x = TRUE)

## Import SDS and LDI
  sds <- read.csv(wealth_covariates)
  sds <- sds[, c('location_id', 'year', 'SDS')]

## Add LDI and SDS to the prediction frame
  pred_frame <- merge(pred_frame, sds, by = c('location_id', 'year'))
  pred_frame <- pred_frame[!duplicated(pred_frame),]  

################################################################################
## SAVE
################################################################################
  save(pred_frame, file =  paste0(save_location,'/pred_frame.RData'))
  print('Prediction frame refreshed.')

## #######
## END
## #######
