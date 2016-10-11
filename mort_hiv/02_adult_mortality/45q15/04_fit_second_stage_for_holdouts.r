################################################################################
## Description: Runs the second stage prediction model for a given holdout
################################################################################

# source("strPath/04_fit_second_stage_for_holdouts.r")
  rm(list=ls())

  if (Sys.info()[1] == "Linux") {
    root <- "/home/j"
    user <- Sys.getenv("USER")
  } else {
    root <- "J:"
    user <- Sys.getenv("USERNAME")
  }

  library(data.table)

## Set local working directory (toggles by GIT user) 
  code_dir <- paste0("strPath")

  ## setwd(paste(root, "strPath/", sep=""))
  source(paste(code_dir,"/space_time.r", sep=""))  
  setwd("strPath")

## set trasfomation for the data in the GPR step: choose from c("log10", "ln", "logit")
  transform <- "logit"

## load data 
  rr <- commandArgs()[3] 
  ho <- as.numeric(commandArgs()[4])

#    rr <- "Central_Sub_Saharan_Africa"
#    ho <- 1
  
  zetas <- list(.7, .8, .9, .99) # note - these must also be changed in run-all script
  lambdas <- seq(.1, .9, .1)
  

# loop through lambda and zeta values and save each file 
for(zeta in zetas){
  for(lambda in lambdas){
#        zeta=.7 # temp
#        lambda=.2 #temp

      setwd("strPath")
      data <- read.csv(paste("./input_", rr, ".txt", sep=""), header=T, stringsAsFactors=F)
      data$include <- (data[,paste("ho", ho, sep="")] == 0)
      data <- data[,!grepl("ho",names(data))]
    
    ## fit second stage model
      source(paste0(root,"strPath/get_locations.r"))
      locations <- get_locations(level="estimate")
      locs_gbd2013 <- unique(locations$ihme_loc_id[!is.na(locations$local_id_2013)])
      
      level_1 <- unique(locations$ihme_loc_id[locations$level_1 == 1]) # All nationals without subnationals
      level_2 <- unique(locations$ihme_loc_id[locations$level_2 == 1]) # All subnationals at the India state level, minus parents
      level_3 <- unique(locations$ihme_loc_id[locations$level_3 == 1]) # All subnationals at the India state/urbanicity level, minus parents 
      
      keep_level_2 <- unique(locations$ihme_loc_id[locations$level_1 == 0 & locations$level_2 == 1 & locations$level_3 == 0])
      keep_level_3 <- unique(locations$ihme_loc_id[locations$level_1 == 0 & locations$level_3 == 1])
      keep_level_1 <- unique(locations$ihme_loc_id[!(locations$ihme_loc_id %in% keep_level_2) & !(locations$ihme_loc_id %in% keep_level_3)])
    
    ## if we want to run subnationals, then subnationals should be c(T,F). If we don't, it should be c(F)
    ## Default to running subnationals only if they actually exist in a given region
    
    # fit space-time
    # we do this three times: 
    #   once with subnational (India states) and no parent countries, 
    #   once with subnational (India states/urbanicity)
    #   once with no subnational and only national level data
    
    data$ihme_loc_id <- as.character(data$ihme_loc_id)

    print(paste(zeta, "is zeta and ", lambda, "is lambda", sep=" "))
    data_all <- data
    tmp <- list()
    i <- 0
    for (level in 1:3) {
      i <- i+1
      #level = 3 # temp
      total_list <- get(paste0("level_",level))
      keep_list <- get(paste0("keep_level_",level))
      
      cat(paste("Level ",level,"\n")); flush.console()
      
      ## only keep iso3s we want
      data <- data_all[data_all$ihme_loc_id %in% total_list,] 
      
      # make North Korea their own region
      nkr <- data$region_name[data$ihme_loc_id=="PRK"][1]
      data$region_name[data$ihme_loc_id=="PRK"] <- "North_Korea"
      
      # Taking out this separate subnational regions thing for now -- Sweden males have no data and crash
      # Double check with Haidong: Why did we make separate subnational regions when they aren't used in space-time if subnationals are separate from national
      ## make separate subnational regions
      #     if (subnational) {
      #       data$region_name <- paste(data$region_name,
      #                                 data$parent_id,
      #                                 sep="___")
      #       data$region_name[data$parent_id == 180] <- paste("Eastern_Sub-Saharan_Africa","174",sep="___") # Analyze Kenya with E SSA since there is NO KENYA DATA
      #     }
      
      
      ## do space time regression
      preds <- resid_space_time(data,subnational, lambda=lambda, zeta=zeta, post_param_selection=F)
      
      ## put North Korea back in its region
      data$region_name[data$ihme_loc_id=="PRK"] <- nkr
      
      ## put subnational data back into correct region
      # if (subnational) data$region_name <- gsub("___.","",data$region_name)
      
      ## get results
      data <- merge(data, preds, by=c("ihme_loc_id", "sex", "year"))
      data$pred.2.resid <- inv.logit(data$pred.2.resid)
      data$pred.2.final <- inv.logit(logit(data$pred.2.resid) + logit(data$pred.1.noRE))
      
      ## save for appending
      tmp[[i]] <- data[data$ihme_loc_id %in% keep_list,] 
    }
      
    ## get all results
    data <- rbindlist(tmp)
      
    ################
    # Calculate GPR inputs
    ################  
    
    ## Mean squared error
    if (transform == "log10") se <- (log(data$mort, base=10) - log(data$pred.2.final, base=10))^2 ## if log base 10
    if (transform == "ln") se <- (log(data$mort) - log(data$pred.2.final))^2 ## if natural log
    if (transform == "logit") se <- (logit(data$mort) - logit(data$pred.2.final))^2 ## if logit
    if (transform == "logit10") se <- (logit10(data$mort) - logit10(data$pred.2.final))^2 ## if logit10
#     mse <- tapply(se[data$type!="no data"], data$ihme_loc_id[data$type != "no data"], function(x) mean(x, na.rm=T)) 
#     for (ii in names(mse)) data$mse[data$ihme_loc_id == ii] <- mse[ii]
#     data$mse[data$type == "no data"] <- 999
    mse <- tapply(se[], data$super_region_name, function(x) mean(x, na.rm=T)) 
    for (ii in names(mse)) data$mse[data$super_region_name == ii] <- mse[ii]

    
    ## calculate data variance in normal space
    ## first, for all groups, calculate sampling variance for adjusted and unadjusted mortality. 
    ## We do this in Mx space, and then convert to qx and to transformed qx using the delta method
    # adjusted
    data$mx <- log(1-data$mort)/(-45)
    data$varmx <- (data$mx*(1-data$mx))/data$exposure
    data$varqx <- (45*exp(-45*data$mx))^2*data$varmx # delta transform to normal qx space
    data$varlog10qx <- (1/(data$mort * log(10)))^2*data$varqx # delta transform to log10 qx space
    if (transform == "log10") data$var <- data$varlog10qx # set variance for log10 qx space ## if log base 10
    if (transform == "ln") data$var <- (1/(data$mort))^2*data$varqx # delta transform to natural log qx space ## if natural log
    if (transform == "logit") data$var <-  (1/(data$mort*(1-data$mort)))^2*data$varqx ## if logit
    if (transform == "logit10") data$var <-  (1/(data$mort*(1-data$mort)*log(10)))^2*data$varqx ## if logit10
    
    # unadjusted
    data$mx_unadjust <- log(1-data$obs45q15)/(-45)
    data$varmx_unadjust <- (data$mx*(1-data$mx))/data$exposure
    data$varqx_unadjust <- (45*exp(-45*data$mx))^2*data$varmx_unadjust # delta transform to normal qx space
    data$varlog10qx_unadjust <- (1/(data$obs45q15 * log(10)))^2*data$varqx_unadjust # delta transform to log10 qx space for the addition of DDM variance
    if (transform == "log10") data$var_unadjust <- data$varlog10qx_unadjust # set variance for log10 qx space ## if log base 10
    if (transform == "ln") data$var_unadjust <- (1/(data$obs45q15))^2*data$varqx_unadjust # delta transform to natural log qx space ## if natural log
    if (transform == "logit") data$var_unadjust <-  (1/(data$obs45q15*(1-data$obs45q15)))^2*data$varqx_unadjust ## if logit
    if (transform == "logit10") data$var_unadjust <-  (1/(data$obs45q15*(1-data$obs45q15)*log(10)))^2*data$varqx_unadjust ## if logit10
    
    ## for category II, add in variance from DDM
    cc <- (((data$category == "ddm_adjust" & data$data == 1) | (grepl("_",data$ihme_loc_id,1,1) & grepl("DSP",data$source_type) & data$data == 1)) & data$adjust.sd != 0)
    cc[is.na(cc)] <- FALSE # Something in the logic statement on the line above makes it return NAs for 456 observations
    ## log10 is correct
    if (transform == "log10") data$var[cc] <- data$var_unadjust[cc] + data$adjust.sd[cc]^2 ## if log base 10
    
    ## ln is correct yet
    if (transform == "ln") {  ## if natural log
      # transform from log base 10 space to normal space using delta method
      data$adjust.sd[cc] <- (10^(log(data$comp[cc],10))*log(10))^2*(data$adjust.sd[cc]^2) ## note that now, adjust.sd is actually the variance
      # transform from normal space to natural log space using delta method
      data$adjust.sd[cc] <- (1/(data$comp[cc]))^2*(data$adjust.sd[cc])
      # make it a standard deviation again
      data$adjust.sd[cc] <- sqrt(data$adjust.sd[cc])
      # add on variance
      data$var[cc] <- data$var[cc] + data$adjust.sd[cc]^2
    }
    
    ## logit is currently correct
    if (transform == "logit") { ## if logit
      # combine variances in log10 space: 
      
      #############
      ## NOTE
      #############
      # We might want to calculate the combined variance in the following way, we should compare the two...
      # Let X be a random variable equal to the estimate of completeness unadjusted 45q15, and let Y be a random variable equal to the completeness estimate
      # Then the variable of interest is the completeness adjusted 45q15, which equals X/Y. So we want Var(X/Y).
      # Var(X/Y) ~ ((E(Y)^2)*Var(X) + (E(X)^2)*Var(Y))/E(Y)^4, this is derived in part using the delta method
      # Reference: http://stats.stackexchange.com/questions/32659/variance-of-x-y
      # The line of code would be:
      # data$totvar[cc] <- ((log(data$comp[cc],10)^2)*data$varlog10qx[cc] + (log(data$obs45q15[cc],10)^2*data$adjust.sd[cc]^2))/(log(data$obs45q15[cc],10))^4
      # For now, we will add them, because we want the Var(log(X/Y)) = Var(log(X) + log(Y)) = Var(log(X)) + Var(log(Y))
      data$totvar <- 0 
      data$totvar[cc] <- data$varlog10qx_unadjust[cc] + data$adjust.sd[cc]^2
      # transform from log base 10 space to normal space using delta method
      data$totvar[cc] <- (10^(log(data$mort[cc],10))*log(10))^2*(data$totvar[cc])
      # transform from normal space to logit space using delta method
      data$var[cc] <- (1/(data$mort[cc]*(1-data$mort[cc])))^2*(data$totvar[cc])
    }
    
    ## logit10 is currently correct
    if (transform == "logit10") { ## if logit10
      # combine variances in log10 space: 
      
      #############
      ## NOTE
      #############
      # We might want to calculate the combined variance in the following way, we should compare the two...
      # Let X be a random variable equal to the estimate of completeness unadjusted 45q15, and let Y be a random variable equal to the completeness estimate
      # Then the variable of interest is the completeness adjusted 45q15, which equals X/Y. So we want Var(X/Y).
      # Var(X/Y) ~ ((E(Y)^2)*Var(X) + (E(X)^2)*Var(Y))/E(Y)^4, this is derived in part using the delta method
      # Reference: http://stats.stackexchange.com/questions/32659/variance-of-x-y
      # The line of code would be:
      # data$totvar[cc] <- ((log(data$comp[cc],10)^2)*data$varlog10qx[cc] + (log(data$obs45q15[cc],10)^2*data$adjust.sd[cc]^2))/(log(data$obs45q15[cc],10))^4
      # For now, we will add them, because we want the Var(log(X/Y)) = Var(log(X) + log(Y)) = Var(log(X)) + Var(log(Y))
      data$totvar <- 0 
      data$totvar[cc] <- data$varlog10qx_unadjust[cc] + data$adjust.sd[cc]^2    # transform from log base 10 space to normal space using delta method
      # transform from log base 10 space to normal space using delta method
      data$totvar[cc] <- (10^(log(data$mort[cc],10))*log(10))^2*(data$totvar[cc])
      # transform from normal space to logit10 space using delta method
      data$var[cc] <- (1/(data$mort[cc]*(1-data$mort[cc])*log(10)))^2*(data$totvar[cc])
    }
    
    ## for category III and IV, replace with the highest data variance in the region
    cc <- (data$category %in% c("gb_adjust", "no_adjust") & data$data == 1)
    max <- tapply(data$var, data$region_name, function(x) max(x, na.rm=T))
    for (ii in names(max)) data$var[cc & data$region_name == ii] <- max[ii]
    
    ## for category V, replace with the MAD estimator of the sd compared to the first stage regression predictions 
    cc <- (data$category == "sibs" & data$data == 1)
    if(length(cc[cc==T]) >= 1){
    if (transform == "log10") data$dev <- abs(log(data$mort, base=10) - log(data$pred.1.noRE, base=10)) ## if log base 10
    if (transform == "ln") data$dev <- abs(log(data$mort) - log(data$pred.1.noRE)) ## if natural log
    if (transform == "logit") data$dev <- abs(logit(data$mort) - logit(data$pred.1.noRE))## if logit
    if (transform == "logit10") data$dev <- abs(logit10(data$mort) - logit10(data$pred.1.noRE))## if logit10
    mad <- aggregate(data$dev[cc], data[cc,list(super_region_name, sex)], median)
    data <- merge(data, mad, by=c("super_region_name", "sex"), all.x=T)
    cc <- (data$category == "sibs" & !is.na(data$category))
    data$var[cc] <- (1.4826*data$x[cc])^2
    }
    ## multiply the variance for sub-national estimates by 10 (AS: don't do this any more 11/24/2013)
    ## data$var[(data$source_type == "DSS" | (grepl("X",substr(data$ihme_loc_id,1,1)))) & data$data == 1] <- data$var[(data$source_type == "DSS" | (grepl("X",substr(data$ihme_loc_id,1,1)))) & data$data == 1]*10
    
    ## convert estimate to log space (and calculate std. errors)
    if (transform == "log10") data$log_mort <- log(data$mort, base=10) ## if log base 10
    if (transform == "ln") data$log_mort <- log(data$mort) ## if natural log
    if (transform == "logit") data$log_mort <- logit(data$mort) ## if logit
    if (transform == "logit10") data$log_mort <- logit10(data$mort) ## if logit10
    data$log_stderr <- sqrt(data$var)
    if (transform == "log10") data$stderr <- sqrt((10^(data$log_mort)*log(10))^2 * data$var) # delta transform back to normal qx space ## if log base 10
    if (transform == "ln") data$stderr <- sqrt(exp(data$log_mort)^2 * data$var) # delta transform back to normal qx space ## if natural log
    if (transform == "logit") data$stderr <- sqrt((exp(data$log_mort)/(1+exp(data$log_mort)))^4 * data$var) # delta transform back to normal qx space ## if logit
    if (transform == "logit10") data$stderr <- sqrt(log(10)*(exp(data$log_mort)/(1+exp(data$log_mort)))^4 * data$var) # delta transform back to normal qx space ## if logit10
    
    ################
    # Save output 
    ################    
    subset_list<-c("location_id", "location_name", "super_region_name", "region_name", "ihme_loc_id", "sex", "year", "LDI_id", "mean_yrs_educ", "hiv",
                   "data", "type", "category", "vr", "mort", "stderr", "log_mort", "log_stderr", 
                   "pred.1.wRE", "pred.1.noRE", "resid", "pred.2.resid", "pred.2.final", "mse", "include")
    data<-subset(data,select=subset_list)
    
#     data2 <- data[,c("location_id", "location_name", "super_region_name", "region_name", "ihme_loc_id", "sex", "year", "LDI_id", "mean_yrs_educ", "hiv",
#                     "data", "type", "category", "vr", "mort", "stderr", "log_mort", "log_stderr", 
#                     "pred.1.wRE", "pred.1.noRE", "resid", "pred.2.resid", "pred.2.final", "mse")]
    
    
    data <- data[order(ihme_loc_id, sex, year, data),]
    

    
    
    ## save output
    setwd("strPath")
    write.csv(data, file=paste("./prediction_model_results_all_stages_", rr, "_", ho,"_", lambda, "_", zeta, ".txt", sep=""), row.names=F)
  
      }
  }

