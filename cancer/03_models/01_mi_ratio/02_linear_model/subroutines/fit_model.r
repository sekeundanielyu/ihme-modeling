################################################################################

## Description: Calls script to apply MAD outliers and generates the MI model
################################################################################
## Set the model 
################################################################################  
fitModel <- function(input_data, mi_formula, upper_cap, buffer, covariate, pred_frame, mad_function, no_mad = FALSE) {
  
  ## Determine if running a logit model
  if (grepl("logit", deparse(mi_formula)[[1]])){
    logit_model = TRUE
  } else {logit_model = FALSE} 
  
  if (no_mad == FALSE) {
    ## set the model data. transform data if running a logit model
    model_data <- input_data
      ## cap input data at value just under cap so logit transform can be taken, then divide input data by cap
      if(logit_model){
        model_data$mi_ratio[model_data$mi_ratio > (upper_cap - buffer)] <- (upper_cap - buffer)
        model_data$mi_ratio <- model_data$mi_ratio/upper_cap
      }
    
    ## drop outliers
    keep <- model_data$outlier == 0
    model_data <- model_data[keep, ]
    model_data$ihme_loc_id <- as.factor(as.character(model_data$ihme_loc_id))
    model_data <- droplevels(model_data)
    
    ## run model to make predictions so that MAD can be determined. Mark MAD outliers as data points 3 MADs from the mean (mean is used because it reduces the number of outliers)
    lm <- lmer(mi_formula, model_data, weights = cases)
    input_data$preds <- predict(lm, newdata= input_data, re.form = NULL, allow.new.levels = TRUE) #re.form = NA sets all random effects to 0
    
    ## Calculate MAD and mark outliers (outliers are those datapoints greater than 3 mads from the mean prediction, by age group)
     input_data <- apply_madOutliers(input_data)
    
    ## Set environment variables (this is a suggested workaround to argument passing in lm.
    environment(formula) <- environment()
  }
  
  ## (re)set the model data. transform data if running a logit model
  model_data <- input_data
 
  ## cap input data at value just under cap so logit transform can be taken, then divide input data by cap
  if(logit_model){
    model_data$mi_ratio[model_data$mi_ratio > (upper_cap - buffer)] <- (upper_cap - buffer)
    model_data$mi_ratio <- model_data$mi_ratio/upper_cap
  }
  
  ## drop outliers
  keep <- model_data$outlier == 0
  model_data <- model_data[keep, ]
  model_data$ihme_loc_id <- as.factor(as.character(model_data$ihme_loc_id))
  model_data <- droplevels(model_data)
  
  ## run model to make predictions so that MAD can be determined. Mark MAD outliers as data points 3 MADs from the mean (mean is used instead of median because it reduces the number of outliers)
  lm <- lmer(mi_formula, model_data, weights = cases)
  
  ## Get coefficient of the wealth covariate
  if (covariate != "none") {
    cov_coeff <- fixef(lm)[covariate]
  } else {
    cov_coeff = 0
  }
  
  ## Back-transform data if running logit model
  if (logit_model){
    model_data$mi_ratio <- model_data$mi_ratio * upper_cap
  }
  
  ## Create dataframe with country-level random effects
  ihme_loc_id_rand_eff <- data.frame(ranef(lm)$ihme_loc_id)
  ihme_loc_id_rand_eff$ihme_loc_id <- rownames(ihme_loc_id_rand_eff)
  names(ihme_loc_id_rand_eff)[names(ihme_loc_id_rand_eff) == "X.Intercept."] <- "country_rand_effect"
  
  ## Return objects
  obj <- list("model" = lm, "ihme_loc_id_rand_eff" = ihme_loc_id_rand_eff, "cov_coeff" = cov_coeff, "data" = input_data, "model_data" = model_data)
  return(obj)
}