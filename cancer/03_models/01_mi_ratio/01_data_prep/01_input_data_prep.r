################################################################################

## Description: Prep MI ratio data for modeling

################################################################################
## Clear workspace  
  rm(list=ls())

## set boolean regenerate_outliers variable 
  ## determines whether to re-run outlier marking for the input dataset whether or not it already exists
  regenerate_outliers = FALSE

################################################################################
## SET/LOAD DATA LOCATIONS AND M/I VALUE RESTRICTIONS (MANUAL)
################################################################################

## Import Libraries
  if (!require("doBy")) install.packages("doBy")
  library(doBy)
  library(foreign)
  library(plyr)
  library(reshape2)

## Manually set modnum and regenerate_outliers. Set regenerate_outliers to FALSE to use the outlier version currently saved in 03_results/01_data_prep
  if (length(commandArgs()) == 1| commandArgs()[1] == "RStudio")  {
    modnum = 158
  } else {
    modnum <- commandArgs()[3]
  }

## Set root directory and working directory
  root = ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
  cancer_folder = paste0(root,'WORK/07_registry/cancer')
  wkdir = paste0(cancer_folder, '/03_models/01_mi_ratio')
  setwd(wkdir)

## Get model specifications. Set Input Data and M/I Value Restrictions
  model_control <- read.csv("./01_code/_launch/model_control.csv", stringsAsFactors = FALSE)
  mi_input_version = model_control$mi_input_version[model_control$modnum == modnum]
  mi_formula <- model_control$formula[model_control$modnum == modnum]
  add_outliers = eval(model_control$add_outliers[model_control$modnum == modnum])
  buffer = model_control$buffer[model_control$modnum == modnum]
  upper_cap = model_control$upper_cap[model_control$modnum == modnum]
  max_mi_accepted = model_control$max_mi_input_accepted[model_control$modnum == modnum]

## Set the model method
  if (grepl("logit", deparse(mi_formula))){
    mi_model_method = "logit"
  } else {
    mi_model_method = "log"
  }

## set paths for input data, IHME country details, and outliers
  data_restrictions_path <- "./02_data/data_restrictions.csv"
  locations_modeled <- paste0(cancer_folder, '/00_common/data/modeled_locations.csv')
  marked_outliers_folder <- "./03_results/01_data_prep/raw_inputs_with_outliers_marked"
  output_folder <- "./03_results/01_data_prep/formatted_model_inputs"

## Set output file and remove previous output if present
  final_input_file = paste0(cancer_folder, "/02_database/00_registry_database/mi_input_", mi_input_version, ".csv")
  if (file.exists(final_input_file)) {unlink(final_input_file)}

## Load the prediction frame
  load("./02_data/pred_frame.RData")

################################################################################
## LOAD and REFORMAT DATA WHERE NECESSARY (AUTORUN)
################################################################################

## Add outliers if outliers are requested. Otherwise import the raw data
  ## use a previously-generated outliered dataset if requested and available
  if (add_outliers & !regenerate_outliers){
    
    ## verify that the desired outliered dataset is available
    input_data_with_outliers <- paste0(marked_outliers_folder, "/04_MI_ratio_model_input_", mi_input_version ,".csv")
    if (file.exists(input_data_with_outliers)) {       
      print("Using Existing Outliered Input...")
      ## if it exists, use the outliered input data 
      outliers_marked <- read.csv(paste0(marked_outliers_folder, "/04_MI_ratio_model_input_", mi_input_version ,".csv"), stringsAsFactors=FALSE)
      ## subset data
      reformatted_input <- outliers_marked[, c("ihme_loc_id", "year", "sex", "acause", "cases", "deaths", "age", "manual_outlier", "excludeFromNational")]
      
    } else { regenerate_outliers = TRUE }
  }

  ## generate a new, outliered input dataset if required. Otherwise use the raw data.
  if (add_outliers & regenerate_outliers) {
    print("Generating Outliers...")
    ## call a script to create a dataset of marked outliers ("outliers_marked")
    commandArgs <- function() c("runR", "runR", mi_input_version, modnum)  
    source(paste0(wkdir, "/01_code/01_data_prep/01a_mark_outliers_master.r"))
    reformatted_input <- outliers_marked[, c("ihme_loc_id", "year", "sex", "acause", "cases", "deaths", "age", "manual_outlier", "excludeFromNational")]
    
  }else if (!add_outliers){  
    print("Using Input Data Without Added Outliers...")
    ## import raw input data
      mi_input_data <- paste0(cancer_folder, "/02_database/01_mortality_incidence/data/final/04_MI_ratio_model_input_", mi_input_version, ".dta")
      raw_mi_input <- read.dta(mi_input_data, , convert.factors = FALSE)
      
    ## add potentially missing columns and subset
      if (!("manual_outlier" %in% names(raw_mi_input) )) {raw_mi_input$manual_outlier <- 0 }
      if (!("excludeFromNational" %in% names(raw_mi_input) )) {raw_mi_input$excludeFromNational <- 0 }
      reformatted_input <- raw_mi_input[, c("ihme_loc_id", "year", "sex", "acause", "cases", "deaths", "age", "manual_outlier", "excludeFromNational")]
      
    ## Reformat Data 
      ## drop "all ages" data
        reformatted_input <- reformatted_input[reformatted_input$age != 1,]
     
      ## Reformat age groups 
        reformatted_input$age[reformatted_input$age == 2] <- 0
        reformatted_input$age[reformatted_input$age >= 7] <- (reformatted_input$age[reformatted_input$age >= 7 & reformatted_input$age <= 22] - 6)*5
        
      ## Recode sex to be factor with "male" and "female" levels
        reformatted_input$sex <- factor(reformatted_input$sex, levels = c(1, 2), labels = c("male", "female"))
  }

################################################################################
## APPLY INITIAL DATA RESTRICTIONS (AUTORUN)
################################################################################

## Display the total number of ihme_loc_ids in the input dataset
  print(paste("Total number of ihme_loc_ids in the input dataset:",length(unique(reformatted_input$ihme_loc_id))))

## Drop irrelevant data
  ## Drop years outside of prediction frame
  reformatted_input <- reformatted_input[reformatted_input$year >= 1970, ]
  
  ## Drop both sexes data, if present
  reformatted_input <- reformatted_input[reformatted_input$sex %in% c("female","male"), ]
  
  ## Drop input data corresponding to age groups that we aren't modeling
  ages <- read.csv(data_restrictions_path, stringsAsFactors = FALSE)
  ages <- ages[ages$model_mi == 1, ]
  for(site in unique(ages$acause)) {
    lower_age <- ages$yll_age_start[ages$acause == site]
    lower_age <- floor(lower_age/5)*5
    invalids <- which(reformatted_input$age < lower_age & reformatted_input$acause == site)
    if(length(invalids) > 0) {
      reformatted_input <- reformatted_input[-invalids, ]
    }
  }
  
  ## Drop "benign" causes and add sex restrictions
  reformatted_input <- reformatted_input[!grepl("benign", reformatted_input$acause), ]
  reformatted_input$acause <- gsub("_cancer", "", reformatted_input$acause)
  
  ## Keep only data with cases/deaths greater than 1. Values less than 1 are likely floating point errors or remnants of Redistribution
  reformatted_input <- reformatted_input[reformatted_input$cases >= 1 & reformatted_input$age > 15, ]
  reformatted_input <- reformatted_input[reformatted_input$deaths >= 1 & reformatted_input$age > 15, ]

################################################################################
## CALCULATE MI RATIO and APPLY MI RATIO RESTRICTIONS (AUTORUN)
################################################################################
print("Calculating MI...")
## generate list of subnational data
  locations <- read.csv(locations_modeled)
  locations <- locations[!is.na(locations$super_region_id),]
  subnatLocs <- as.character(unique(locations$ihme_loc_id[grepl("_",locations$ihme_loc_id)]))
  natSubnats <- unique(substr(subnatLocs, 1, 3))
  Locs <- c(subnatLocs, natSubnats)

## mark subnational locations where no national data is present (outliers are removed)
  sData <- reformatted_input[reformatted_input$ihme_loc_id %in% Locs,]
  sData <- sData[sData$manual_outlier == 0 & sData$excludeFromNational == 0,]
  sData$parent <- substr(sData$ihme_loc_id, 1, 3)
  sData$is_national[sData$ihme_loc_id %in% natSubnats] <- 1
  sData$is_national[is.na(sData$is_national)] <- 0
  national_check <- aggregate(sData$is_national, by = list(sData$parent, sData$year, sData$acause, sData$sex), sum)
  names(national_check) <- c("parent", "year", "acause", "sex", "has_national")
  national_check$has_national[national_check$has_national > 0] <- 1

## calculate national numbers as the sum of the subnational numbers if no national data are present
  removing_national_data <- merge(sData, national_check, by=c("parent", "year", "sex", "acause"), all = TRUE)
  national_data_removed <- removing_national_data[removing_national_data$has_national != 1,]
  national_data_removed$ihme_loc_id <- substr(national_data_removed$ihme_loc_id, 1, 3)
  national_data_removed <- national_data_removed[, !(names(national_data_removed) %in% c("parent", "has_national", "in_national"))]
  for_calculation <- summaryBy(cases + deaths ~ ihme_loc_id + year + sex + age + acause, FUN=(sum), data=national_data_removed) 

## reformat new dataset to facilitate merge
  names(for_calculation)[names(for_calculation) %in% "cases.(sum)"] <- "cases"
  names(for_calculation)[names(for_calculation) %in% "deaths.(sum)"] <- "deaths"
  for_calculation$manual_outlier <- 0
  for_calculation <- for_calculation[!duplicated(for_calculation),]  

## merge new data with the rest of the data and caluclate MI
  reformatted_input <- reformatted_input[,!(names(reformatted_input) %in% "excludeFromNational")]
  mi_calculated <- rbind(reformatted_input, for_calculation)
  mi_calculated$mi_ratio <- mi_calculated$deaths/mi_calculated$cases

print("Applying MI restrictions...")
## Drop MI ratios above the maximum accepted mi ratio
  mi_calculated <- mi_calculated[mi_calculated$mi_ratio <= max_mi_accepted,] 

## Drop missing MI ratio data
  mi_calculated <- mi_calculated[which(!is.na(mi_calculated$mi_ratio)), ]

## Cap at lower cap. Regardless of cap, all values must be at least slightly above zero so a logarithm can be calculated 
  if(buffer > 0) {
    mi_calculated$mi_ratio[mi_calculated$mi_ratio < buffer] <- buffer
  } else {  
    mi_calculated$mi_ratio[which(mi_calculated$mi_ratio < 0.000005)] <- 0.000005
  }  

## Cap input MI ratios at upper_cap if running a logit model
  if (mi_model_method == "logit") {
    mi_calculated$mi_ratio[mi_calculated$mi_ratio > (upper_cap - buffer)] <- (upper_cap - buffer)
  } else {mi_calculated$mi_ratio[mi_calculated$mi_ratio > upper_cap] <- upper_cap}

################################################################################
## MERGE INPUTS WITH PREDICTION FRAME (AUTORUN)
################################################################################
print("Merging with prediction frame...")
## Merge with prediction covariates. 
  covars <- unique(pred_frame[, c("ihme_loc_id", "location_id", "year", "super_region_name", "super_region_id", "region_name", "region_id", "developed", "SDS")])
  covars <- covars[!duplicated(covars),]
  merged_input <- merge(mi_calculated, covars, by = c("ihme_loc_id", "year"))

## Display data availability by super region
  print("Data Availability by Super Region:")
  print(unique(merged_input[, c("super_region_name", "super_region_id")]))

## Drop countries that don't belong to a super-region
  merged_input <- merged_input[which(!is.na(merged_input$super_region_name)), ]

## Ensure that categorical variables are factors
  merged_input$sex <- as.factor(merged_input$sex)
  merged_input$super_region_name <- as.factor(merged_input$super_region_name)
  merged_input$region_name <- as.factor(merged_input$region_name)
  merged_input$super_region_id <- as.factor(merged_input$super_region_id) 
  merged_input$region_id <- as.factor(merged_input$region_id)
  merged_input$ihme_loc_id <- as.factor(merged_input$ihme_loc_id)

## Ensure that continuous variables are numeric or character
  merged_input$SDS <- as.numeric(as.character(merged_input$SDS))

## Ensure that specially assigned classes are correctly assigned
  ## age
  if (model_control$age_categorical[model_control$modnum == modnum] == "TRUE") {
    merged_input$age <- as.factor(merged_input$age)
  } else if (model_control$age_categorical[model_control$modnum == modnum] == "FALSE") {
    merged_input$age <- as.numeric(as.character(merged_input$age))
  }
  ## year
  if (model_control$year_categorical[model_control$modnum == modnum] == "TRUE") {
    merged_input$year <- as.factor(merged_input$year)
  } else if (model_control$year_categorical[model_control$modnum == modnum] == "FALSE") {
    merged_input$year <- as.numeric(as.character(merged_input$year))
  }

################################################################################
## IDENTIFY OUTLIERS, OUTPUT QUALITY CHECKS
################################################################################
## drop duplicates
  final_mi_input <- merged_input[!duplicated(merged_input),]

## Display the total number of ihme_loc_ids in the final dataset
  print(paste("Total number of ihme_loc_ids in the final dataset:",length(unique(final_mi_input$ihme_loc_id))))

## rename outliers
names(final_mi_input)[names(final_mi_input) %in% "manual_outlier"] <- "outlier"

## test for duplicates
  test <- final_mi_input[final_mi_input$manual_outlier == 0,c("ihme_loc_id", "year", "sex", "acause", "age")]
  message = paste("Number of duplicates:", nrow(test[duplicated(test),]))
  print(message)

################################################################################
## SAVE (AUTORUN)
################################################################################
print("Saving...")
## save mi input for next step
  mi_input <- final_mi_input
  save(mi_input, file = paste0(output_folder, "/mi_input_", modnum, ".RData"))

## save a copy for the database
  write.csv(mi_input, file = final_input_file, row.names =FALSE)

## #######
## END
## #######