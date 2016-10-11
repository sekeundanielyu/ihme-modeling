################################################################################

## Description: Calls function to determine best fit linear model, then makes predictions with that model

################################################################################
## Clear workspace
  rm(list=ls())

## Import Libraries
library(ggplot2)
library(plyr)
library(boot)

################################################################################
## Set Data Locations and Load the Input Data (AUTORUN)
################################################################################
## Set root directory and working directory 
root <- ifelse(Sys.info()[1]=='Windows', 'J:/', '/home/j/')
wkdir = paste0(root, 'WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/')
setwd(wkdir)

## Accept arguments
modnum <- commandArgs()[3]
cause <- commandArgs()[4]
gender <- commandArgs()[5]

## Set arguments if none are sent (used for testing)
if (length(commandArgs()) == 1| commandArgs()[1] == 'RStudio')  {
  modnum <- 160
  cause <- 'neo_bladder'
  gender <- 'both'  
}
print(paste(cause, gender))

## Set paths
model_control_path <- './_launch/model_control.csv'

################################################################################
## Set Model Specifications (outliers, weights, random effects, etc.) and set the modeling function (AUTORUN)
################################################################################
## Get model specifications from the model record
model_control <- read.csv(model_control_path, stringsAsFactors = FALSE)
rand_eff.form <- model_control$random_effects[model_control$modnum == modnum]
upper_cap <- as.numeric(model_control$upper_cap[model_control$modnum == modnum])
model_script <- model_control$model_script[model_control$modnum == modnum]

## Convert the randm effects input to a formula. Set as null if no argument is present
if(!is.na(rand_eff.form)) {
  if(rand_eff.form == 'NULL') {
    rand_eff.form <- NULL
  } else {
    rand_eff.form <- as.formula(rand_eff.form)
  }
}

################################################################################
## Run Model
################################################################################
source(paste0('./02_linear_model/', model_script))
results <- run_model(cause, modnum, code_dir = wkdir)
input_data <- results$input_data
test_data <- results$test_data
subnat_data <- results$subnat_data
pred_frame <- results$pred_frame
final_model <- results$model_results
mi_formula <- results$final_formula
cov_coeff <- final_model$cov_coeff
covariate <- results$covariate

## test for duplicates
test <- input_data[,c('ihme_loc_id', 'year', 'age', 'sex')]
print(paste('Number of duplicates:', nrow(test[duplicated(test),])))


################################################################################
## Make Predictions
################################################################################
## Remove age and year categories with insufficient data from the prediction_frame if age is categorical
## age
if(class(test_data$age) == 'factor') {
  ## drop ages for which there is not enough test data to make a prediction
  for (a in unique(test_data$age)) {
    if (sum(test_data$age == a) < 5) {test_data <- test_data[test_data$age != a,]} 
  }
  
  ## set the prediction frame ages to the valid test data ages
  pred_frame <- pred_frame[(pred_frame$age %in% test_data$age),]
  pred_frame <- droplevels(pred_frame)
}

## year
if(class(test_data$year) == 'factor') {
  ## drop ages for which there is not enough test data to make a prediction
  for (y in unique(test_data$year)) {
    if (sum(test_data$year == y) < 5) {test_data <- test_data[test_data$year != y,]} 
  }
  
  ## set the prediction frame ages to the valid test data ages
  pred_frame <- pred_frame[(pred_frame$year %in% test_data$year),]
  pred_frame <- droplevels(pred_frame)
}

## Create predictions based on the model output
print('Making predictions...')
if (grepl('logit', deparse(mi_formula)[[1]])) {
  pred_frame$preds <- upper_cap*inv.logit(predict(final_model$model, pred_frame, re.form = rand_eff.form, allow.new.levels = TRUE)) 
} else {
  pred_frame$preds <- exp(predict(final_model$model, pred_frame, re.form = rand_eff.form, allow.new.levels = TRUE))
  if (sum(pred_frame$preds[pred_frame$preds > upper_cap]) > 0) {pred_frame$preds[pred_frame$preds > upper_cap] <- upper_cap}
}

## replace subnational predictions with national predictions
national_preds <- pred_frame[!grepl('_', pred_frame$ihme_loc_id), c('ihme_loc_id', 'year', 'sex', 'age', 'preds')]
names(national_preds)[names(national_preds) %in% c('ihme_loc_id', 'preds')] <- c('parent_ihme_loc_id', 'national_preds')
pred_frame$parent_ihme_loc_id <- substr(pred_frame$ihme_loc_id, 1, 3)
pred_frame <-merge(pred_frame, national_preds, by= c('parent_ihme_loc_id', 'year', 'sex', 'age'))
pred_frame$preds[grepl('_', pred_frame$ihme_loc_id)] <- pred_frame$national_preds[grepl('_', pred_frame$ihme_loc_id)]
pred_frame <- pred_frame[ , !(names(pred_frame) %in% 'national_preds')]

################################################################################
## Finalize and Save
################################################################################
print('Finalizing...')

## Name coefficients if applicable
if (covariate != 'none'){
  names(final_model)[names(final_model) == 'cov_coeff'] <- 'wealth_coeff'
} 

## add subnational data back to the test data to create the final dataset
  final_model$data <- rbind(test_data, subnat_data)
  final_model$data <- final_model$data[,!(names(final_model$data) %in% 'data_id')]
  final_model$final_formula <- mi_formula

## test for duplicates
  test <- input_data[,c('ihme_loc_id', 'year', 'age', 'sex')]
  print(paste('Number of duplicates:', nrow(test[duplicated(test),])))

##save
  save(pred_frame, 'model' = final_model , file = paste0('/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model/model_', modnum, '/', cause, '/', gender, '/linear_model_output.RData'))
