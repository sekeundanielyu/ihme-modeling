################################################################################

## Description: Predicts best fit linear model

################################################################################
## Import Libraries
library(lme4)
library(boot)

run_model <- function(cause, modnum, code_dir, rmse_test = FALSE) {
  mi_dir = "/home/j/WORK/07_registry/cancer/03_models/01_mi_ratio"
    
  ## set paths
  model_control_path <- paste0(code_dir,"/_launch/model_control.csv")
  set_model_function <- paste0(code_dir,"/02_linear_model/subroutines/set_model.r")
  cause_information_path <- paste0(mi_dir,"/02_data/data_restrictions.csv")
  
  ## Get model specifications from the model record
  model_control <- read.csv(model_control_path, stringsAsFactors = FALSE)
  mi_formula <- model_control$formula[model_control$modnum == modnum]
  outlier_method <- model_control$outlier_method[model_control$modnum == modnum]
  buffer <- model_control$buffer[model_control$modnum == modnum]
  upper_cap <- as.numeric(model_control$upper_cap[model_control$modnum == modnum])
  wealth_cov <- model_control$wealth_cov[model_control$modnum == modnum]
  test_once = FALSE

  ## Get cause information
  cause_information <- read.csv(cause_information_path)
  sex <- as.character(unique(cause_information$sex[cause_information$acause == cause]))
    
  ## Source the fitModel function, which returns the model and it's random effects
  source(paste0(code_dir, "02_linear_model/subroutines/fit_model.r"))
  source(paste0(code_dir, '02_linear_model/subroutines/', outlier_method, ".r"))
  
  ################################################################################
  ## Get the model input data
  ################################################################################
  ## Load the model input
    load(paste0("/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model/model_", modnum, "/", cause, "/", sex, "/model_input.RData"))
 
  ## Add a sex covariate to the model function if "both sexes" are specified
    if(sex == "both") {
      mi_formula <- as.formula(paste0(mi_formula, " + sex"))
    } else {
      mi_formula <- as.formula(mi_formula)
    }
  
  ## Keep only data for those cause-specific ages that are predicted
  # Apply age restrictions
    lower_age <- cause_information$yll_age_start[cause_information$acause == cause]
    invalids <- which(as.numeric(as.character(pred_frame$age)) < lower_age)
    if(length(invalids) > 0) {
      pred_frame <- pred_frame[-invalids, ]
    }
  
  ## Check the model for possible class reassignment and reassign if necessary (random intercepts must be categorical/factors)
  print(paste("Age is", class(data$age)))
    ## age
    if (grepl("\\| age)",deparse(mi_formula, width.cutoff = 500L))) {
      data$age <- as.factor(data$age)
    }else if (class(data$age) != "factor") {
      data$age <- as.numeric(as.character(data$age))
      pred_frame$age <- as.numeric(as.character(pred_frame$age))
    } else if (class(data$age) == "factor") {
      pred_frame$age <- as.factor(pred_frame$age)
    }
  
    ## year
    if (grepl("\\| year)",deparse(mi_formula, width.cutoff = 500L))) {
      data$year <- as.factor(data$year)
      pred_frame$year <- as.factor(pred_frame$year)
    } else if (class(data$year) != "factor") {
      data$year <- as.numeric(as.character(data$year))
      pred_frame$year <- as.numeric(as.character(pred_frame$year))
    } else if (class(data$year) == "factor") {
      pred_frame$year <- as.factor(as.character(pred_frame$year))
    }
  
  ## Specially handle models running with development status
    ## remove development status from the model if there is not enough data to differentiate by development status
    if (grepl("developed", deparse(mi_formula, width.cutoff = 500L)) & nrow(subset(data, developed == 0 & outlier == 0))==0) {
      mi_formula <- as.formula(gsub(paste0(" \\+ developed"),"",deparse(mi_formula, width.cutoff = 500L)))
      mi_formula <- as.formula(gsub(paste0("developed \\+"),"",deparse(mi_formula, width.cutoff = 500L)))
    } 
    data$developed <- as.numeric(as.character(data$developed))
    pred_frame$developed <- as.numeric(as.character(pred_frame$developed))
  print(deparse(mi_formula, width.cutoff = 500L))
  
  ################################################################################
  ## Specially handle test data
  ################################################################################ 
  ## create data samples of only national data if running an 80/20 RMSE test. Use 80% of countries for in-sample, 20% for out-of-sample
  if (rmse_test) {
    orig_input_data <- data
    data$uid <- paste(data$ihme_loc_id, data$year, data$sex, data$age, sep = "_")
    # keep only country-sex-ages with at least four years of data
    data$country_sex <- paste(data$ihme_loc_id, data$sex, data$age, sep= "_")
    Count <- rle( sort( data$country_sex ) )
    data$count <- Count[[1]][ match( data$country_sex , Count[[2]] ) ]
    data <- data[data$count > 4,]
    # keep 80% of data from each country
    samp <- function(df, replace=FALSE)
    {
      grp <- split(seq_len(nrow(df)), df$country_sex)
      l <- lapply(grp, function(g) {
        sample(g, 0.8*length(g), replace=replace)
      })
      df[unlist(l), ]
    }
    
    in_sample <- samp(data)
    out_sample <- data[!(data$uid %in% in_sample$uid),]
    data <- in_sample
    
    out_sample <- out_sample[!grepl("_", out_sample$ihme_loc_id), ]
    
    ## format ihme_loc_id
    out_sample$ihme_loc_id <- as.factor(out_sample$ihme_loc_id)
    data$ihme_loc_id <- as.factor(data$ihme_loc_id)
  }

  ################################################################################
  ## Set the model arguments, then Run Model and Create Predictions
  ################################################################################  
  ## Save first iteration data
  test_data <- data
  
  ## save subnational data to be added later, and remove subnational data from the test data
  subnat_data <- data[grepl("_", data$ihme_loc_id), ]
  subnat_data <- droplevels(subnat_data)
  test_data <- test_data[!grepl("_", test_data$ihme_loc_id), ]
  test_data <- droplevels(test_data)
  
  ## Start model with the wealth covariate
  covariate = wealth_cov
  
  ## Set the first model iteration and print coefficient for the wealth covariate. Otherwise, set current, MAD outliered model data as test data (maintains mad outliers)
  model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame)
  print(paste(covariate, model_results$cov_coeff, sep =": "))

  ## Check the covariate coefficient. If the coefficient is positive run the model without a covariate.
  covariate_check <- model_results$cov_coeff
  
  if (grepl("super_region_id", deparse(mi_formula, width.cutoff = 500L))) {
    sr_random_slope <- ranef(model_results$model)$super_region_id
    sr_random_slope$effect <- sr_random_slope$SDS + model_results$cov_coeff
    covariate_check = mean(sr_random_slope$effect)
  }
  
  if(covariate_check > 0 & covariate == "SDS") {
    test_formula = mi_formula
    test_formula = as.formula(gsub(paste0(covariate," \\+ "),"",deparse(test_formula, width.cutoff = 500L)))
    print(paste("Test Formula:", deparse(test_formula, width.cutoff = 500L)))
    covariate <- "none"
    model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame)
    
    ## Set current model data as test data (maintains mad outliers)
    test_data <- model_results$data
    
    # Run with covariate to test if dropping mads corrected the issue
    covariate = wealth_cov
    print(paste0("Re-running with original formula: ", deparse(mi_formula, width.cutoff = 500L)))
    model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame)
    
    ## Check the covariate coefficient (as a function of super region). If the coefficient is more than 0 run the model without a covariate.
    covariate_check <- model_results$cov_coeff
    if (grepl("super_region_id", deparse(mi_formula, width.cutoff = 500L))) {
      sr_random_slope <- ranef(model_results$model)$super_region_id
      sr_random_slope$effect <- sr_random_slope$SDS + model_results$cov_coeff
      covariate_check = mean(sr_random_slope$effect)
    }
    if(covariate_check > 0 & covariate == "SDS") {
      covariate <- "none"
      model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame)
      test_once = TRUE
    }     
  } else {
    ## Set current model data as test data (maintains mad outliers)
    test_data <- model_results$data
    test_once = FALSE
  }
  
  ################################################################################
  ## Re-run the model until no all country-level random effects are acceptable (oulier data from developing countries with country-level random effects <= USA)
  ################################################################################  
  pre_RE_drop <- test_data
  unacceptable_rand_effects = ""
  covariate <- wealth_cov
  stop_while = FALSE
  print("Checking Random Effects")
  print(deparse(mi_formula, width.cutoff = 500L))
  while(unacceptable_rand_effects != "none remaining" & !stop_while){
    ## Set the test-run outputs
      test_rand_eff <- model_results$ihme_loc_id_rand_eff
      if (grepl("developed", deparse(mi_formula, width.cutoff = 500L))){
        ## get development status and development status related fixed effect
        dev_status <- test_data[,c("ihme_loc_id","developed")]
        dev_status <- dev_status[!duplicated(dev_status),]
        
        print(fixef(model_results$model))
        dev_re <- fixef(model_results$model)
        dev_re <- dev_re[labels(dev_re)%in%"developed"]
        dev_re <- as.numeric(as.character(dev_re))[1]

        ## merge results
        rand_eff_data <- merge(test_rand_eff, dev_status, by = "ihme_loc_id", all.x = TRUE, all.y = FALSE)
  
        rand_eff_data$dev_re <- 0
        if(!is.na(dev_re)) {rand_eff_data$dev_re[rand_eff_data$developed == 1] <- dev_re }
        rand_eff_data$RE <- rand_eff_data$country_rand_eff + rand_eff_data$dev_re
        
        ##  set final dataset
        test_rand_eff <- rand_eff_data[,c("ihme_loc_id","RE")]
        
      } else {
        names(test_rand_eff)[names(test_rand_eff) %in% "country_rand_effect"] <- "RE"
      }
              
    test_data <- merge(test_data, test_rand_eff, by="ihme_loc_id", all.x = TRUE)
    
    ## Check the random effects. Drop countries with unrealistic random effects and set model to re-test if data can be dropped.
    USA_rand_effect <- as.numeric(unique(test_data$RE[test_data$ihme_loc_id == "USA"]))
    if(length(USA_rand_effect) < 1) {
      unacceptable_re_ihme_loc_ids = vector()
      print(test_rand_eff)
      print(paste("Rows of US data:", nrow(test_data[test_data$ihme_loc_id == "USA",])))
    } else if (is.na(USA_rand_effect[[1]])) {
      unacceptable_re_ihme_loc_ids = vector()
      print(test_rand_eff)
      print(paste("Rows of US data:", nrow(test_data[test_data$ihme_loc_id == "USA",])))
    } else {
      print(paste0("USA random effect: ", USA_rand_effect))
      unacceptable_re_ihme_loc_ids <- unique(test_data$ihme_loc_id[(test_data$RE <= USA_rand_effect & test_data$developed == 0 & test_data$outlier == 0)])
    } 
    
    ## Check if all unacceptable random effects have been removed. If not, run the model again
    if(length(unacceptable_re_ihme_loc_ids) == 0) {
      unacceptable_rand_effects = "none remaining"
    } else if (is.na(unacceptable_re_ihme_loc_ids[[1]])) {
      unacceptable_rand_effects = "none remaining"
    }else {
      print("dropped data for the following ihme_loc_ids:")
      print(unacceptable_re_ihme_loc_ids)
      
      ## keep only data with acceptable random effects (drop developing countries with random effects <= USA)
      test_data$outlier[test_data$ihme_loc_id %in% unacceptable_re_ihme_loc_ids] <- 1
      
      # remove country random effect column from the test_data
      test_data <- test_data[,!(names(test_data) %in% "RE")]
      
      ## Reset the model
      model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame)
      print(paste(covariate, model_results$cov_coeff, sep =": "))
    }
    if(test_once){
      covariate_check <- model_results$cov_coeff
      if (grepl("super_region_id", deparse(mi_formula, width.cutoff = 500L))) {
        sr_random_slope <- ranef(model_results$model)$super_region_id
        sr_random_slope$effect <- sr_random_slope$SDS + model_results$cov_coeff
        covariate_check = mean(sr_random_slope$effect)
      }
      if(covariate_check > 0 & covariate == "SDS") {
        stop_while = TRUE
      }
    }
  }
  
  print("Random Effects Checked")
  
  ## Check the covariate coefficient. If the coefficient is more than 0 drop based on random effects without using covariate.
  re_run = FALSE
  covariate_check <- model_results$cov_coeff
  if (grepl("super_region_id", deparse(mi_formula, width.cutoff = 500L))) {
    sr_random_slope <- ranef(model_results$model)$super_region_id
    sr_random_slope$effect <- sr_random_slope$SDS + model_results$cov_coeff
    covariate_check = mean(sr_random_slope$effect)
  }
  if(covariate_check > 0 & covariate == "SDS") {
    re_run = TRUE
    test_formula = mi_formula
    test_formula = as.formula(gsub(paste0(covariate," \\+ "),"",deparse(test_formula, width.cutoff = 500L)))
    print(paste("Test Formula:", deparse(test_formula, width.cutoff = 500L)))  
    covariate <- "none"
    if (grepl("developed", deparse(test_formula, width.cutoff = 500L)) & nrow(subset(test_data, developed == 0 & outlier == 0))==0) {
      ## if already re-running, test formula is already defined. if not, define the test formula
      if (!re_run) {test_formula = mi_formula}
      re_run = TRUE
      test_formula <- as.formula(gsub(paste0(" \\+ developed"),"",deparse(test_formula, width.cutoff = 500L)))
      test_formula <- as.formula(gsub(paste0("developed \\+"),"",deparse(test_formula, width.cutoff = 500L)))
    }  
  }
  if(re_run){
    test_data <- pre_RE_drop
    print("Re-Checking Random Effects")
    print(deparse(test_formula, width.cutoff = 500L))
    
    ## Reset the model
    model_results <- fitModel(input_data=test_data, test_formula, upper_cap, buffer, covariate, pred_frame)
    print(paste(covariate, model_results$cov_coeff, sep =": "))
    
    ## Re-run the model until no all country-level random effects are acceptable (drop developing countries with country-level random effects <= USA).
    unacceptable_rand_effects = ""
    while(unacceptable_rand_effects != "none remaining"){
      
      ## Set the test-run outputs
      test_rand_eff <- model_results$ihme_loc_id_rand_eff
      if (grepl("developed", deparse(test_formula, width.cutoff = 500L))){
        ## get development status and development status related fixed effect
        dev_status <- test_data[,c("ihme_loc_id","developed")]
        dev_status <- dev_status[!duplicated(dev_status),]
        
        print(fixef(model_results$model))
        dev_re <- fixef(model_results$model)
        dev_re <- dev_re[labels(dev_re)%in%"developed"]
        dev_re <- as.numeric(as.character(dev_re))[1]
        
        ## merge results
        rand_eff_data <- merge(test_rand_eff, dev_status, by = "ihme_loc_id", all.x = TRUE, all.y = FALSE)
        
        rand_eff_data$dev_re <- 0
        if(!is.na(dev_re)) {rand_eff_data$dev_re[rand_eff_data$developed == 1] <- dev_re }
        rand_eff_data$RE <- rand_eff_data$country_rand_eff + rand_eff_data$dev_re
        
        ##  set final dataset
        test_rand_eff <- rand_eff_data[,c("ihme_loc_id","RE")]
        
      } else {
        names(test_rand_eff)[names(test_rand_eff) %in% "country_rand_effect"] <- "RE"
      }
      
      test_data <- merge(test_data, test_rand_eff, by="ihme_loc_id")
      
      ## Check the random effects. Drop countries with unrealistic random effects and set model to re-test if data can be dropped.
      USA_rand_effect <- as.numeric(unique(test_data$RE[test_data$ihme_loc_id == "USA"]))
      if(length(USA_rand_effect) == 0) {
        unacceptable_re_ihme_loc_ids = vector()
        print(test_rand_eff)
        print(paste("Rows of US data:", nrow(test_data[test_data$ihme_loc_id == "USA",])))
      } else if (is.na(USA_rand_effect[[1]])) {
        unacceptable_re_ihme_loc_ids = vector()
        print(test_rand_eff)
        print(paste("Rows of US data:", nrow(test_data[test_data$ihme_loc_id == "USA",])))
      } else {
        print(paste0("USA random effect: ", USA_rand_effect))
        unacceptable_re_ihme_loc_ids <- unique(test_data$ihme_loc_id[(test_data$RE <= USA_rand_effect & test_data$developed == 0 & test_data$outlier == 0)])
      } 
      
      ## Check if all unacceptable random effects have been removed. If not, run the model again
      if(length(unacceptable_re_ihme_loc_ids) == 0) {
        unacceptable_rand_effects = "none remaining"
      } else if (is.na(unacceptable_re_ihme_loc_ids[[1]])) {
        unacceptable_rand_effects = "none remaining"
      }else {
        print("dropped data for the following ihme_loc_ids:")
        print(unacceptable_re_ihme_loc_ids)
        
        ## keep only data with acceptable random effects (drop developing countries with random effects <= USA)
        test_data$outlier[test_data$ihme_loc_id %in% unacceptable_re_ihme_loc_ids] <- 1
        
        # remove country random effect column from the test_data
        test_data <- test_data[,!(names(test_data) %in% "RE")]
        
        ## Reset the model
        model_results <- fitModel(input_data=test_data, test_formula, upper_cap, buffer, covariate, pred_frame)
        print(paste(covariate, model_results$cov_coeff, sep =": "))
      }
    }
    print("Random Effects Re-Checked")
  } 
  
  ################################################################################
  ## Finalize
  ################################################################################ 
  ## Set current model data as test data (maintains mad outliers)
  test_data <- model_results$data
  if (exists("dev_re")){
    if(is.na(dev_re)){
    mi_formula <- as.formula(gsub(paste0(" \\+ developed"),"",deparse(mi_formula, width.cutoff = 500L)))
    mi_formula <- as.formula(gsub(paste0("developed \\+"),"",deparse(mi_formula, width.cutoff = 500L)))
    model_results <- fitModel(input_data=test_data, mi_formula, upper_cap, buffer, covariate, pred_frame, no_mad = TRUE)
    }
    print(dev_re)
    print(paste("final formula", mi_formula))
  }
  
 
  ## return information
  if (rmse_test) {
    obj <- list("model_results" = model_results, "covariate" = covariate, "pred_frame" = pred_frame, "input_data" = orig_input_data, "subnat_data" = subnat_data, "in_sample" = test_data, "out_sample" = out_sample, "final_formula" = mi_formula)
  } else {
    obj <- list("model_results" = model_results, "covariate" = covariate, "pred_frame" = pred_frame, "input_data" = data, "subnat_data" = subnat_data, "test_data" = test_data, "final_formula" = mi_formula)
  }
return(obj)
}