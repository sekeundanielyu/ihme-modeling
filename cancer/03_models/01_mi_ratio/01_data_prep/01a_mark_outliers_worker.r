################################################################################
## Description: Add outliers to MI Input

################################################################################
## Clear workspace  
rm(list=ls())

## Import libraries
library(foreign)

## define operating system and root
root <- ifelse(Sys.info()[1]=="Windows", "J:", "/home/j")
current_year =  format(Sys.Date(), "%Y")

## Accept or assign arguments
cause_name <- commandArgs()[3]
temp_folder <- commandArgs()[4]
mi_input_version <- commandArgs()[5]
modnum <- commandArgs()[6]
        
## set location of outlier map
  outlier_map_location = paste0(temp_folder, "/outlier_selection.csv")
  
## #######################################
## define functions
## #######################################

markExceptions <- function(data, exceptions){
  data$is_exception <- FALSE
  if (exceptions != "none") {
    print(paste('Exceptions:', exceptions))
    exceptions = as.list(strsplit(gsub(" ", ",", exceptions), ","))[[1]]
    if ("orig_ihme_loc_id" %in% colnames(data)) {
      data$is_exception[is.element(data$orig_ihme_loc_id, exceptions)] <- TRUE
    } else {data$is_exception[is.element(data$ihme_loc_id, exceptions)] <- TRUE}
  }
  return(data)
}

inrange <- function(var, range_data){
  lower = paste0(var, "_within_lower_bound")
  upper = paste0(var, "_within_upper_bound")
  return( range_data[lower] <= range_data[var] & range_data[upper] >= range_data[var] )
}

markOutliers <- function(data, exceptions){
  data <- markExceptions(data, exceptions)
  data$in_range <- !data$is_exception & inrange("year", data) & inrange("age", data) & !is.na(data$possible_outlier)
  
  ## mark outliers where mi boundary is set to a single entry(
  mark_outlier =  !is.na(data$mi_equal_to) & data$mi_ratio == data$mi_equal_to & data$in_range
  data$manual_outlier[mark_outlier] <- 1
  
  ## compare to mi boundary if mi boundary is set
  mark_outlier = (data$mi_less_than > 0 | data$mi_greater_than < 2) & (data$mi_ratio < data$mi_less_than | data$mi_ratio > data$mi_greater_than) & data$in_range
  data$manual_outlier[mark_outlier] <- 1
  
  ## compare only other inputs if no mi boundary is set
  mark_outlier = (data$mi_less_than <= 0 & data$mi_greater_than >= 2) & data$in_range
  data$manual_outlier[mark_outlier] <- 1
  
  ## return dataset
  return(data)
}

## ########################################
## generate outlier maps
## ########################################
## import data specific to the cause
  outlier_map <- read.csv(outlier_map_location, stringsAsFactors=FALSE)
  names(outlier_map) <- gsub("\\.", "", names(outlier_map)) 
  outlier_map$acause <- as.character(outlier_map$acause)
  outlier_map <- outlier_map[outlier_map$acause == cause_name,]
  outlier_map  <- outlier_map[, c('ihme_loc_id', 'sex', 'apply_to_subnationals', 'exceptions', 'year_within_lower_bound', 'year_within_upper_bound',  'mi_less_than',	'mi_greater_than',	'mi_equal_to',	'age_within_lower_bound',	'age_within_upper_bound')]
  outlier_map$ihme_loc_id <- as.character(outlier_map$ihme_loc_id)
  outlier_map$sex <- as.character(outlier_map$sex)
  outlier_map$possible_outlier <- TRUE
   
## reformat single entries
  ## set upper and lower bounds equal to each other if only one is indicated (for age and year only)
  outlier_map$age_within_upper_bound[is.na(outlier_map$age_within_upper_bound)] <- outlier_map$age_within_lower_bound[is.na(outlier_map$age_within_upper_bound)]
  outlier_map$age_within_lower_bound[is.na(outlier_map$age_within_lower_bound)] <- outlier_map$age_within_upper_bound[is.na(outlier_map$age_within_lower_bound)]
  outlier_map$year_within_upper_bound[is.na(outlier_map$year_within_upper_bound)] <- outlier_map$year_within_lower_bound[is.na(outlier_map$year_within_upper_bound)]
  outlier_map$year_within_lower_bound[is.na(outlier_map$year_within_lower_bound)] <- outlier_map$year_within_upper_bound[is.na(outlier_map$year_within_lower_bound)]
  
  ## set remaining null values to maximum range
  outlier_map$age_within_lower_bound[is.na(outlier_map$age_within_lower_bound)] <- 0
  outlier_map$year_within_lower_bound[is.na(outlier_map$year_within_lower_bound)] <- 0
  outlier_map$age_within_upper_bound[is.na(outlier_map$age_within_upper_bound)] <- 85
  outlier_map$year_within_upper_bound[is.na(outlier_map$year_within_upper_bound)] <- current_year

  ## set undefined mi boundaries at maximum
  outlier_map$mi_less_than[is.na(outlier_map$mi_less_than)] <- 0
  outlier_map$mi_greater_than[is.na(outlier_map$mi_greater_than)] <- 2

## reformat subnational specification
  outlier_map$apply_to_subnationals[(is.na(outlier_map$apply_to_subnationals) | outlier_map$apply_to_subnationals != 1)] <- 0

## reformat exceptions
  outlier_map$exceptions <- as.character(outlier_map$exceptions)
  outlier_map$exceptions[outlier_map$exceptions %in% c("", " ", ".") | is.na(outlier_map$exceptions)] <- "none"
  outlier_map$exceptions <- strsplit(outlier_map$exceptions, split=", ")

## reformat combined sex (relabel "both" data as either gender)
  outlier_map$sex[outlier_map$sex == "" | outlier_map$sex %in% c("all", "both", "any")] <- "both"
  combined_sex <- outlier_map[outlier_map$sex == "both",] 
  sex_corrected = outlier_map
  sex_corrected$sex[sex_corrected$sex == "both"] <- "female"
  sex_corrected <- rbind(sex_corrected, combined_sex)
  sex_corrected$sex[sex_corrected$sex == "both"] <- "male"

## drop duplicates and remove null entries
  sex_corrected <- sex_corrected[!duplicated(sex_corrected),]
  sex_corrected <- sex_corrected[rowSums(is.na(sex_corrected))<ncol(sex_corrected),]

## create map of global outliers
  sex_corrected$ihme_loc_id[sex_corrected$ihme_loc_id == "" | (sex_corrected$ihme_loc_id %in% c("all", "any"))] <- "any"
  global <- sex_corrected[sex_corrected$ihme_loc_id =="any",]
  
## create map of outliers by country that are not applied to subnational locations
  by_ihme_loc_id <- sex_corrected[sex_corrected$ihme_loc_id != "any" & (sex_corrected$apply_to_subnationals == 0 | grepl("_", sex_corrected$ihme_loc_id)),]

## create map of outliers by country that should be applied to all subnationals
  apply_to_subnat <- sex_corrected[sex_corrected$ihme_loc_id !="any" & sex_corrected$apply_to_subnationals == 1 & !grepl("_", sex_corrected$ihme_loc_id),]

## ############################
## Import MI Input
## ############################
## get data
  cause_data <- read.dta(paste0(root, '/WORK/07_registry/cancer/02_database/01_mortality_incidence/data/final/04_MI_ratio_model_input_', mi_input_version,'.dta'), convert.factors = FALSE)
  cause_data <- cause_data[cause_data$acause == cause_name,]
  cause_data <- cause_data[, c("ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "pop", "excludeFromNational")]
  cause_data$ihme_loc_id <- as.character(cause_data$ihme_loc_id)
  cause_data$acause <- as.character(cause_data$acause)
  cause_data$sex <- as.character(cause_data$sex)

## generate mi and outlier column
  cause_data$mi_ratio <- cause_data$deaths/cause_data$cases
  cause_data$mi_ratio[is.nan(cause_data$mi_ratio)] <- 0
  cause_data$manual_outlier <- 0

## reformat age
  names(cause_data)[names(cause_data) %in% "age"] <- "gbd_age_format"
  cause_data$age = (cause_data$gbd_age_format -6)*5
  cause_data$age[cause_data$age == -20] <- 0
  cause_data <- cause_data[cause_data$gbd_age_format != 1, ]

## reformat sex
  names(cause_data)[names(cause_data) %in% "sex"] <- "gender"
  cause_data$sex[cause_data$gender == 2] <- "female"
  cause_data$sex[cause_data$gender == 1] <- "male"

## ############################
## MARK OUTLIERS
## ############################
## mark outliers that are applied globally
if (nrow(global) >0) {
  marking_global <- cause_data
  for (i in 1:nrow(global)){
    print(paste("marking global outliers", i, "of", nrow(global)))
    marking_global <- merge(marking_global, global[i, !(names(global) %in% "ihme_loc_id")], by = "sex", all.x = TRUE, all.y = FALSE)  
    marking_global <- markOutliers(marking_global, global$exceptions[i])
    marking_global <- marking_global[, c("ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "pop", "mi_ratio", "excludeFromNational", "manual_outlier")]
  }
  global_complete <- marking_global
} else {
  print("no global outliers to apply")
  global_complete <- cause_data
}

## mark outliers by country (not applied to subnationals)
if(nrow(by_ihme_loc_id) > 0) {
  marking_countries <- global_complete
  for (i in 1:nrow(by_ihme_loc_id)){
    print(paste("marking outliers applied to national", i, "of", nrow(by_ihme_loc_id), "(", by_ihme_loc_id$ihme_loc_id[i], ")"))
    marking_countries <- merge(marking_countries, by_ihme_loc_id[i,], by = c("ihme_loc_id", "sex"), all.x = TRUE, all.y = FALSE)
    marking_countries <- markOutliers(marking_countries, by_ihme_loc_id$exceptions[i])
    marking_countries <- marking_countries[, c("ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "pop", "mi_ratio", "excludeFromNational", "manual_outlier")]
  }
    countries_complete <- marking_countries
} else {
  print("no ihme_loc_id outliers to apply without subnationals")
  countries_complete <- global_complete
}

## mark outliers by country (applied to subnationals also)
if (nrow(apply_to_subnat) > 0) {
  ## create parent ihme_loc_id variable create dummy ihme_loc_id variable to enable additional merge
  marking_apply_subnat <- countries_complete
  marking_apply_subnat$orig_ihme_loc_id <- marking_apply_subnat$ihme_loc_id
  marking_apply_subnat$ihme_loc_id <- substr(marking_apply_subnat$ihme_loc_id,1,3)
  
  ## mark outliers 
  for (i in 1:nrow(apply_to_subnat)){
    print(paste("marking outliers applied to subnational", i, "of", nrow(apply_to_subnat), "(", apply_to_subnat$ihme_loc_id[i], ")"))
    marking_apply_subnat <- merge(marking_apply_subnat, apply_to_subnat[i,], by = c("ihme_loc_id", "sex"), all.x = TRUE, all.y = FALSE)
    marking_apply_subnat <- markOutliers(marking_apply_subnat, apply_to_subnat$exceptions[i])
    marking_apply_subnat <- marking_apply_subnat[, c("orig_ihme_loc_id", "ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "pop", "mi_ratio", "excludeFromNational", "manual_outlier")]
  
  }
  marking_apply_subnat$ihme_loc_id <- marking_apply_subnat$orig_ihme_loc_id
  outliers_complete <- marking_apply_subnat[, c("ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "pop", "mi_ratio", "excludeFromNational", "manual_outlier")]
} else {
  print("no outliers to apply to subnationals")
  outliers_complete <- countries_complete
}

## drop duplicates
  outliers_complete <- outliers_complete[!duplicated(outlier_map),]

## save
  write.csv(outliers_complete, paste0(temp_folder, "/model_", modnum, "/", cause_name, "_outliers.csv"), row.names =FALSE)
     
## #######
## END
## #######
  