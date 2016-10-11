################################################################################
## Description: Generates in-sample/out-of-sample RMSE for the selected model(s)

################################################################################
## Clear workspace
rm(list=ls())

## Import Libraries
library(plyr)
library(ggplot2)
library(lme4)
library(gridExtra)
library(foreign)

################################################################################
## SET MI Model Number (MANUAL)
################################################################################
## Model number
if (length(commandArgs()) == 1| commandArgs()[1] == "RStudio")  {
  modnum = 65
} else {modnum = modnum <- commandArgs()[3]}


################################################################################
## Set Data Locations and Set Model Restrictions 
################################################################################
## Set root directory and working directory
root <- ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
wkdir = paste0(root, "WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/")
setwd(wkdir)

## set output directory
output_directory = paste0(root, "temp/registry/cancer/03_models/01_mi_ratio/RMSE")
try(dir.create(output_directory, recursive = TRUE), silent = TRUE)

## Load model controls
model_control <- read.csv(paste0(root, "WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/_launch/model_control.csv"), stringsAsFactors = FALSE)

## Create a list to dictate which causes should be modeled and for which genders
cause_information_path <- "./_launch/data_restrictions.csv"
cause_information <- read.csv(cause_information_path)

# keep only those data that are modeled
cause_information <- cause_information[cause_information$model_mi == 1, ]

# create empty data frame in which to store RMSE data
all_rmse <- data.frame()

################################################################################
## Generate the mean 80/20 RMSEs for X iterations
################################################################################
for(x in 1:10){
  ## Get settings from the model control
  input_type = model_control$mi_version[model_control$modnum == modnum]
  upper_cap <- upper_cap <- as.numeric(model_control$upper_cap[model_control$modnum == modnum])
  rand_eff.form <- model_control$random_effects[model_control$modnum == modnum]
  model_script <- model_control$model_script[model_control$modnum == modnum]
  
  ## Convert the randm effects input to a formula. Set as null if no argument is present
  if(!is.na(rand_eff.form)) {
    if(rand_eff.form == "NULL") {
      rand_eff.form <- NULL
    } else {
      rand_eff.form <- as.formula(rand_eff.form)
    }
  }

  ## Set input data location
  input_data_location = paste0(root, "/WORK/07_registry/cancer/02_database/01_mortality_incidence/data/final")
  
  ################################################################################
  ## Plot RMSE. Run in-sample vs out-of-sample test
  ################################################################################
  ## create empty data frames for the RMSE values
  rmse_data <- data.frame()
  
  ## Loop through the model result files. Create one ST_GPR input for each cause-sex-super_region
  for(cause in cause_information$acause) {
    print(cause)
    
    try ({
    ## Run the model with the in-sample data (random sample saved as r data file)
      source(paste0("./02_linear_model/", model_script))
      results <- run_model(cause, modnum, wkdir, rmse_test = TRUE)
      in_sample <- results$in_sample
      out_sample <- results$out_sample
      pred_frame <- results$pred_frame
      model <- results$model
      mi_formula <-results$final_formula
      cov_coeff <- model$cov_coeff
      covariate <- results$covariate
      
      ################################################################################
      ## Make Predictions
      ################################################################################
      ## Remove age and year categories with insufficient data from the prediction_frame if age is categorical
      ## age
      if(class(in_sample$age) == "factor") {
        ## drop ages for which there is not enough test data to make a prediction
        for (a in unique(in_sample$age)) {
          if (sum(in_sample$age == a) < 5) {in_sample <- in_sample[in_sample$age != a,]} 
        }
        ## set the prediction frame ages to the valid test data ages
        pred_frame <- pred_frame[(pred_frame$age %in% in_sample$age),]
        pred_frame <- droplevels(pred_frame)
      }
      
      ## year
      if(class(in_sample$year) == "factor") {
        ## drop ages for which there is not enough test data to make a prediction
        for (y in unique(in_sample$year)) {
          if (sum(in_sample$year == y) < 5) {in_sample <- in_sample[in_sample$year != y,]} 
        }
        ## set the prediction frame ages to the valid test data ages
        pred_frame <- pred_frame[(pred_frame$year %in% in_sample$year),]
        pred_frame <- droplevels(pred_frame)
      }
      
      ## Create predictions based on the model output
      print("Making predictions...")
      if (grepl("logit", deparse(mi_formula)[[1]])) {
        pred_frame$preds <- upper_cap*inv.logit(predict(model$model, pred_frame, re.form = rand_eff.form, allow.new.levels = TRUE)) 
      } else {
        pred_frame$preds <- exp(predict(model$model, pred_frame, re.form = rand_eff.form, allow.new.levels = TRUE))
        if (sum(pred_frame$preds[pred_frame$preds > upper_cap]) > 0) {pred_frame$preds[pred_frame$preds > upper_cap] <- upper_cap}
      }
      
      ################################################################################
      ## Calculate RMSE
      ################################################################################
      print("Calculating RMSE...")
      ## Merge the input data (in_sample) data with predictions
      in_sample <- merge(pred_frame[, c("ihme_loc_id", "year", "age", "sex", "cause", "preds")], in_sample[, c("ihme_loc_id", "year", "age", "mi_ratio", "cases")])
      in_sample <- in_sample[!is.na(in_sample$preds),]
      in_sample$residuals <- in_sample$preds - in_sample$mi_ratio
      rmse_df_in <- data.frame()
      for (s in unique(in_sample$sex)) {
        in_sample_rmse <- sqrt(mean(in_sample$residuals[in_sample$sex == s]^2))
        in_sample_mae <- mean(abs(in_sample$residuals[in_sample$sex == s]))
        sex <- s
        temp <- cbind(in_sample_rmse, in_sample_mae, sex)
        rmse_df_in <- rbind(rmse_df_in, temp)
      }
      
      ## Merge the out-of-sample data (out_sample) with predictions
      out_sample <- out_sample[out_sample$ihme_loc_id %in% unique(in_sample$ihme_loc_id),]
      out_sample <- merge(pred_frame[, c("ihme_loc_id", "year", "age", "sex", "cause", "preds")], out_sample[, c("ihme_loc_id", "year", "age", "mi_ratio", "cases")])
      if (nrow(out_sample) == 0) {next}
      out_sample <- out_sample[!is.na(out_sample$preds),]
      out_sample$residuals <- out_sample$preds - out_sample$mi_ratio
      rmse_df_out <- data.frame()
      for (s in unique(out_sample$sex)) {
        out_sample_rmse <- sqrt(mean(out_sample$residuals[out_sample$sex == s]^2))
        out_sample_mae <- mean(abs(out_sample$residuals[out_sample$sex == s]))
        sex <- s
        temp <- cbind(out_sample_rmse, out_sample_mae, sex)
        rmse_df_out <- rbind(rmse_df_out, temp)
      }
      rmse_df <- merge(rmse_df_out, rmse_df_in)
      rmse_df$cause <- cause
      rmse_data <- rbind(rmse_data, rmse_df)
    })
  }
  rmse_data$modnum <- as.numeric(modnum)
  all_rmse <- rbind(all_rmse, rmse_data)
}
##
avg_rmse <- data.frame()
for(cause in unique(all_rmse$cause)) {
  temp_c <- data.frame()
  for (s in unique(all_rmse$sex[all_rmse$cause == cause])) {
    mean_in_sample_rmse <- mean(as.numeric(as.character(all_rmse$in_sample_rmse[all_rmse$cause == cause & all_rmse$sex == s])))
    mean_out_sample_rmse <- mean(as.numeric(as.character(all_rmse$out_sample_rmse[all_rmse$cause == cause & all_rmse$sex == s])))
    temp_s <- cbind(mean_in_sample_rmse, mean_out_sample_rmse, cause, modnum, "sex" = s)
    temp_c <- rbind(temp_c, temp_s)
  }
  avg_rmse <- rbind(avg_rmse,temp_c)
} 

write.csv(avg_rmse, file = paste0(output_directory, "/RMSE_compare_", modnum, ".csv"), quote = TRUE, row.names = FALSE, col.names = TRUE)
  
  
##############################################################################
# END
###############################################################################
