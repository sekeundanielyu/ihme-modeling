################################################################################
## Description: Sets up input data and directories for space-time GPR

################################################################################
## Import Libraries
library(boot)
library(plyr)

################################################################################
## SET MI Model Number (MANUAL)
################################################################################
## Model number
  modnum <- commandArgs()[3]
  linear_output <- commandArgs()[4]
  cause <- commandArgs()[5]
  sex <- commandArgs()[6]
  mi_model_method <- commandArgs()[7]
  upper_cap <- as.numeric(commandArgs()[8])


################################################################################
## Set Directories and Load Data
################################################################################
## Set directories
  root <- ifelse(Sys.info()[1]=='Windows', 'J:/', '/home/j/')
  setwd(paste0(root, 'WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/'))
  cluster_output = '/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio' 
  output_dir = paste0(cluster_output, '/03_st_gpr/model_', modnum, '/', cause, '/', sex)
  dir.create(paste0(output_dir, '/_temp'), recursive = TRUE)

## Load Prediction Frame
  load('../../01_mi_ratio/02_data/pred_frame.RData')

## Load linear model output
  load(paste0(cluster_output, '/02_linear_model/model_', modnum, '/', linear_output))
  data <- final_model$data

################################################################################
## Format Data and Save
################################################################################

## Keep only Relevant Data
  ## Keep only data for the current sex and cause (can optionally also subset to superregion if the data files end up being too big). 
  data <- droplevels(data[data$sex == sex, ])
  preds <- droplevels(pred_frame[pred_frame$sex == sex, ])
  
  ## Keep only input data that is not marked as an outlier
  data <- data[data$outlier == 0, ]
  
  ## drop Japan and Saudi data from subnational
  data$mi_ratio[substr(data$ihme_loc_id,1,4) == 'JPN_' | substr(data$ihme_loc_id,1,4) == 'SAU_' ] <- NA
  data$cases[substr(data$ihme_loc_id,1,4) == 'JPN_' | substr(data$ihme_loc_id,1,4) == 'SAU_'] <- NA
  data$deaths[substr(data$ihme_loc_id,1,4) == 'JPN_' | substr(data$ihme_loc_id,1,4) == 'SAU_'] <- NA

## Calculate Log Variance input calculates variance input for Spactime-GPR
  ## Add data variance in log space
  if (mi_model_method == 'logit') { 
    data$data_var <- data$mi_ratio/upper_cap * (1-data$mi_ratio/upper_cap) / data$cases
    data$lg_var <- data$data_var/(upper_cap^2) * (1/(data$mi_ratio/upper_cap*(1-data$mi_ratio/upper_cap)))^2
    data$lg_var[data$mi_ratio < .5 & !is.na(data$mi_ratio)] <- data$data_var[data$mi_ratio < .5 & !is.na(data$mi_ratio)]/(upper_cap^2) * (1/(.5/upper_cap*(1-.5/upper_cap)))^2
    data$obs_data_variance <- data$lg_var
    
    # Add correction to data variance
    data$obs_data_variance <- data$obs_data_variance * 10
    
    ## Transform data and predictions
    orig_input <- data$observed_data
    orig_pred <- preds$stage1_prediction
    data$observed_data <- logit(data$mi_ratio/upper_cap)
    preds$stage1_prediction <- logit(preds$preds/upper_cap)
    
  } else  if (mi_model_method == 'log'){
    ## Method for log variance using poisson approximation
    data$data_var <- 1/data$deaths
    data$log_var <- data$data_var/(data$mi_ratio^2)
    data$obs_data_variance <- data$log_var
    
    ## Add correction to data variance: The data variance is far too low, which causes overfitting problems for the model. 
    data$obs_data_variance <- data$obs_data_variance * 10
    
    ## Transform data and predictions 
    data$observed_data <- log(data$mi_ratio)
    preds$stage1_prediction <- log(preds$preds)
    
  } else {
    stop('model_method entered will not work with the current code')
  }

  ## Merge the input data with predictions
    st_input <- merge(preds[, c('ihme_loc_id', 'location_id', 'year', 'age', 'sex', 'cause', 'super_region_id', 'region_id', 'developed', 'stage1_prediction')],  data[, c('ihme_loc_id', 'year', 'age', 'observed_data', 'obs_data_variance', 'cases')], all.x = TRUE)
    st_input <- st_input[!is.na(st_input$stage1_prediction),]
    st_input <- st_input[!duplicated(st_input),]
  
  ## Calculate ST-GPR input for global data 
    st_input <- ddply(st_input, .(age), function(x) {
      x$few_datapoints = ifelse(length(x$observed_data[!is.na(x$observed_data)]) < 4, 1, 0)
      x$global_mad <- mad(x$stage1_prediction - x$observed_data, na.rm = TRUE)
      return(x)
    })
  
  ## If there are fewer than 4 datapoints for an age category, use the maximum possible mad 
    st_input$global_mad[st_input$few_datapoints == 1 | is.na(st_input$global_mad)] <- max(st_input$global_mad, na.rm = TRUE)
    if (nrow(st_input[is.na(st_input$global_mad),])) {
      stop("ERROR: not all data is assigned a global mad")
    }
    st_input <- st_input[, !(names(st_input) %in% "few_datapoints")]

## Create input for each super-region for the cause-sex and save
  print("saving st_inputs...")
  for(sr in unique(st_input$super_region_id)) {
    print(sr)
    write.csv(st_input[st_input$super_region_id == sr, ], paste0(output_dir, '/', sr, '_st_input.csv'), na = '', row.names = FALSE)
  }

################################################################################
## END
################################################################################
