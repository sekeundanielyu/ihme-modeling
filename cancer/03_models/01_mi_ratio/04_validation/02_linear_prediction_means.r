################################################################################
## Description: Generates with/without data means for the selected model(s)

################################################################################
## Clear workspace
rm(list=ls())

################################################################################    
## SET MI Model Number (MANUAL)
################################################################################
if (length(commandArgs()) == 1| commandArgs()[1] == "RStudio")  {
  modnum = 139
} else {modnum <- commandArgs()[3]}

################################################################################
## Set Data Locations and Set Model Restrictions 
################################################################################
## Set root directory and working directory
root <- ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
wkdir = paste0(root, "WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/")
setwd(wkdir)

## set output directory
output_dir = paste0(root, "temp/registry/cancer/03_models/01_mi_ratio/Prediction_Means")
try(dir.create(output_dir, recursive = TRUE), silent = TRUE)


################################################################################
## Calculate mean mi prediction for each model
################################################################################
## create list of files to be imported
  files <- list.files(paste0("/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model/model_", modnum), pattern = "linear_model_output.RData", recursive = TRUE)

## data frame for means by development status and whether a country has data
  means_by_dev_andData <- data.frame()

## data frame for means by cause and country
  means_by_country <- data.frame()
 
## iterate through the list of files
for(ff in files) {
  print(ff)
  cause <- substr(ff, start = 1, stop = regexpr("/", ff[1]) - 1)
  sex <- substr(ff, start = regexpr("/", ff[1]) + 1, stop = gregexpr("/", ff[1])[[1]][2] - 1)
  
  ## Load linear model output
  linear_file <- paste(cause, sex, "linear_model_output.RData", sep = "/")
  print(paste("adding", linear_file))
  load(paste0("/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model/model_", modnum, "/", linear_file))
  
  ## combine input data with predictions
  data <- final_model$data
  data$mi_input <- data$mi_ratio
  preds <- pred_frame
  preds$modnum <- modnum
  preds$linear_prediction <- preds$preds
  combined_data <- merge(preds[, c("ihme_loc_id", "year", "age", "sex", "cause", "super_region_id", "developed", "linear_prediction", "modnum")],  data[, c("ihme_loc_id", "year", "age", "mi_input", "outlier")], all.x = TRUE)
  names(combined_data)[names(combined_data) %in% "outlier"] <- "linear_outlier"
  
  ## Determine if datapoint has input data
  combined_data <- combined_data[, has_data:=all(sapply(unique(combined_data$ihme_loc_id), function(i) any(!is.na(combined_data$mi_input[combined_data$ihme_loc_id == i])))), by = ihme_loc_id]
  
  ## Calculate means by dev status and data availability
    means_d <- aggregate(combined_data$linear_prediction, list(combined_data$has_data, combined_data$developed), mean)
    names(means_d) <- c("has_data", "developed", "mean_predicted_mi")
    
    ## calculate the percent of data that needs adjustment
      US_pred <- combined_data[combined_data$ihme_loc_id == "USA",]
      US_pred <- US_pred[,c("linear_prediction", "age", "year")]
      names(US_pred) <- c("US_pred", "age", "year")
      us_check <- merge(combined_data, US_pred, by = c("age", "year"), all.x = TRUE)
      us_check <- us_check[!is.na(us_check$linear_prediction),]
      strange_preds <- us_check$developed == 0 & us_check$linear_prediction > us_check$US_pred & !is.na(us_check$US_pred)
      us_check$needs_adjustment <- 0
      us_check$needs_adjustment[strange_preds] <- 1
      num_issues <- 100*(sum(us_check$needs_adjustment)/nrow(us_check))
    
    ## Calculate the percent of data that is outliered
      outlier_data <- combined_data[!is.na(combined_data$linear_outlier),]
      outliered_any <-100*(sum(outlier_data$linear_outlier)/nrow(outlier_data))
      outliered_developing <- 100*(sum(outlier_data$linear_outlier[outlier_data$developed == 0 & !grepl("_", outlier_data$ihme_loc_id)])/nrow(outlier_data[outlier_data$developed == 0 & !grepl("_", outlier_data$ihme_loc_id),]))
    
    ## Create and store the final dataset
      means_d$percent_D0_predicted_below_US <- num_issues
      means_d$percent_outliered_all_data <- outliered_any
      means_d$percent_outliered_developing <- outliered_developing
      means_d$cause <- cause
      means_d$sex <- sex
      print(modnum)
      print(means_d)
      means_by_dev_andData <- rbind(means_by_dev_andData, means_d)

  ## Calculate means by country (specific age groups)
    temp <- combined_data[combined_data$age %in% c(20, 40, 60, 80),]
    means_c <- aggregate(temp$linear_prediction, list(temp$ihme_loc_id, temp$age), mean)
    names(means_c) <- c("ihme_loc_id", "age", "mean_predicted_mi")
    
    ## create ancstore the final dataset
      means_c$cause <- cause
      means_c$sex <- sex
      means_by_country <- rbind(means_by_country, means_c)
}

## add data from the current model number to the full dataset, then write to csv
means_by_dev_andData$modnum <- modnum
write.csv(means_by_dev_andData, file = paste0(output_dir, "/model_", modnum, "_linear_prediction_means_byDev_andData_status.csv"), row.names=FALSE)

print("Reshaping and saving...")
means_by_c <- means_by_country
means_by_c <- reshape(means_by_c,
                      v.names = "mean_predicted_mi",
                      timevar = "age",
                      idvar = c("ihme_loc_id", "cause", "sex"),
                      direction = "wide")
means_by_c$modnum <- modnum
means_by_c <- merge(means_by_c, pred_frame[, c("ihme_loc_id", "region_id", "super_region_id", "developed")], all.y = TRUE)
means_by_c <- means_by_c[!duplicated(means_by_c),]
means_by_c <- means_by_c[!grepl("_", means_by_c$ihme_loc_id),]
write.csv(means_by_c, file = paste0(output_dir, "/model_", modnum, "_linear_prediction_means_by_cause_andCountry.csv"), row.names=FALSE)
