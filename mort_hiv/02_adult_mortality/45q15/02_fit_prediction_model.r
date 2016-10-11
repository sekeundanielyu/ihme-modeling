################################################################################
## Description: Run the first stage of the prediction model for adult mortality
##              and calculate inputs to GPR 
################################################################################

# source("strPath/02_fit_prediction_model.r")

rm(list=ls())
library(foreign); library(zoo); library(nlme); library(data.table)

## Set local working directory (toggles by GIT user) 
if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  code_dir <- paste0("strPath/45q15")
  sim <- as.numeric(commandArgs()[3])  ## this gets passed as 1 if not doing HIV sims, but gets ignored in the rest of the code, so it doesn't matter
  hivsims <- as.logical(as.numeric(commandArgs()[4]))
} else {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("strPath/45q15")
  sim <- 1 ## this gets passed as 1 if not doing HIV sims, but gets ignored in the rest of the code, so it doesn't matter
  hivsims <- F
}
data_dir <- paste(root, "strPath/", sep="")
source(paste(code_dir,"/space_time.r", sep = ""))

print(sim)
print(hivsims)


## set countries that we have subnational estimates for
source(paste0(root,"strPath/get_locations.r"))
locations <- get_locations(level="estimate")
locs_gbd2013 <- unique(locations$ihme_loc_id[!is.na(locations$local_id_2013)])

level_1 <- unique(locations$ihme_loc_id[locations$level_1 == 1]) # All nationals without subnationals
level_2 <- unique(locations$ihme_loc_id[locations$level_2 == 1]) # All subnationals at the India state level, minus parents
level_3 <- unique(locations$ihme_loc_id[locations$level_3 == 1]) # All subnationals at the India state/urbanicity level, minus parents 

keep_level_2 <- unique(locations$ihme_loc_id[locations$level_1 == 0 & locations$level_2 == 1 & locations$level_3 == 0])
keep_level_3 <- unique(locations$ihme_loc_id[locations$level_1 == 0 & locations$level_3 == 1])
keep_level_1 <- unique(locations$ihme_loc_id[!(locations$ihme_loc_id %in% keep_level_2) & !(locations$ihme_loc_id %in% keep_level_3)])

# 
# 
#   sub_locations <- locations[locations$level_3 == 1 & !(locations$ihme_loc_id %in% level_1),]
#   children <- unique(sub_locations$ihme_loc_id)
#   sub_locations$parent_id[grepl("GBR_",sub_locations$ihme_loc_id)] <- 95 # Replace parent_id = GBR instead of England
#   parent_ids <- unique(sub_locations$parent_id)
#   parents <- unique(locations$ihme_loc_id[locations$location_id %in% parent_ids])

## if we want to run subnationals, then subnationals should be c(T,F). If we don't, it should be c(F)
#   subnationals <- c(T,F)
#   subnationals <- c(F)

## set transformation of the data for the GPR stage: choose from c("log10", "ln", "logit", "logit10")
transform <- "logit"

## Create sim importing function
import_sim <- function(sss) {
  subhiv <- read.csv(paste0("sim",sss,".csv"),stringsAsFactors=F)
  subhiv$year <- subhiv$year + .5
  if (is.null(subhiv$ihme_loc_id)) subhiv$ihme_loc_id <- subhiv$iso3
  subhiv$iso3 <- NULL
  subhiv$sex <- as.character(subhiv$sex)
  subhiv$sex[subhiv$sex == "1"] <- "male"
  subhiv$sex[subhiv$sex == "2"] <- "female"
  subhiv$sim <- NULL
  data <- data[data$ihme_loc_id %in% unique(subhiv$ihme_loc_id),]
  data <- merge(data,subhiv,all.x=T,by=c("year","sex","ihme_loc_id"))
  data$hiv[!is.na(data$hiv_cdr)] <- data$hiv_cdr[!is.na(data$hiv_cdr)]
  data$hiv_cdr <- NULL
  data$hiv[is.na(data$hiv)] <- 0
  return(data)
}

###############
## Read in data
###############
setwd(data_dir)
data <- read.csv("input_data.txt", stringsAsFactors=F)
data <- data[!is.na(data$sex),] 

setwd("strPath")

if(hivsims == 1) {
  data <- import_sim(sim) 
}

################
# Fit first stage model
################

## Create first stage regression function
run_first_stage <- function(data) {
  #solve for mx
  data$mx <- log(1-data$mort)/(-45)
  data$tLDI <- log(data$LDI_id)
  
  # Temporary fix: the new subnational covariates mess with national estimates
  # Solution: run the first-stage regression with only GBD2013 locations
  # And then apply the results to both the national and subnational units
  data_sub <- data[!(data$ihme_loc_id %in% locs_gbd2013),]
  data <- data[data$ihme_loc_id %in% locs_gbd2013,]
  
  data$ihme_loc_id <- as.factor(data$ihme_loc_id)
  
  # Get starting values for stage 1 overall model (the model is not sensitive to starting values)
  start0 <- vector("list", 2)
  names(start0) <- c("male", "female")
  for (sex in unique(data$sex)) {
    start0[[sex]] <- c(beta1 = 0, 
                       beta2 = 0, 
                       beta3 = 0, 
                       beta5 = 0)
    names(start0[[sex]]) <- c("beta1","beta2","beta3","beta5")
  }
  
  ##Fit first stage model
  
  #grouped data object
  gr_dat <- vector("list", 2)
  names(gr_dat) <- c("male","female")
  for (sex in unique(data$sex)) {
    gr_dat[[sex]] <- groupedData(mx~ 1 | ihme_loc_id, data = data[data$sex == sex & !is.na(data$mort),])
  }
  
  #pre-specifying fixed effects, random effects, and formula
  fixed <- list(beta1 + beta2 + beta3 + beta5 ~ 1)
  random <- list(ihme_loc_id = beta4 ~ 1)
  form <- as.formula("mx ~ exp(beta1*tLDI + beta2*mean_yrs_educ + beta4 + beta5) + beta3*hiv")
  
  ##model with a random effect on country
  # set list to store models
  stage1.models <- vector("list", 2)
  names(stage1.models) <- c("male","female")
  for (sex in unique(data$sex)) {
    stage1.models[[sex]] <- nlme(form,
                                 data = gr_dat[[sex]],
                                 fixed = fixed,
                                 random = random, 
                                 groups = ~ihme_loc_id,
                                 start = c(start0[[sex]]),
                                 control=nlmeControl(maxIter=300,
                                                     pnlsMaxIter=30),
                                 verbose = F)
  }
  
  ## Save stage 1 model
  if (hivsims) {
    setwd(paste0("strPath"))
    #write.csv(data, paste0("prediction_model/first_stage_results",sim,".csv"))
    save(stage1.models, file=paste0("prediction_model/first_stage_regressions_", sim, ".rdata"))
    save(stage1.models, file=paste("prediction_model/archive/first_stage_regression_", sim, Sys.Date() ,".rdata", sep=""))
  } else {
    save(stage1.models, file="prediction_model/first_stage_regressions.rdata")
    save(stage1.models, file=paste("archive/prediction_model/first_stage_regression_", Sys.Date() ,".rdata", sep=""))
  }
  
  ## Temp fix: Merge back in the subnational data onto the GBD2013
  data <- rbind(data,data_sub)
  
  #Merge iso3 random effects into data
  for (sex in unique(data$sex)) {
    for (ii in rownames(stage1.models[[sex]]$coefficients$random$ihme_loc_id)) data$ctr_re[data$ihme_loc_id == ii & data$sex == sex] <- stage1.models[[sex]]$coefficients$random$ihme_loc_id[ii,1]
  }
  data$ctr_re[is.na(data$ctr_re)] <- 0
  
  #Get data back in order
  data <- data[order(data$sex,data$ihme_loc_id, data$year),]
  
  #predictions w/o any random effects
  pred.mx <- vector("list", 2)
  names(pred.mx) <- c("male","female")
  for (sex in unique(data$sex)) {
    data$pred.mx.noRE[data$sex == sex] <- exp(stage1.models[[sex]]$coefficients$fixed[1]*data$tLDI[data$sex == sex] 
                                              + stage1.models[[sex]]$coefficients$fixed[2]*data$mean_yrs_educ[data$sex == sex] 
                                              + stage1.models[[sex]]$coefficients$fixed[4]) + stage1.models[[sex]]$coefficients$fixed[3]*data$hiv[data$sex == sex]
  }
  data$pred.1.noRE <- 1-exp(-45*data$pred.mx.noRE)
  
  #Predictions with random effects (or, if RE == NA, then return without RE)
  for (sex in unique(data$sex)) {
    data$pred.mx.wRE[data$sex == sex] <- exp(stage1.models[[sex]]$coefficients$fixed[1]*data$tLDI[data$sex == sex] 
                                             + stage1.models[[sex]]$coefficients$fixed[2]*data$mean_yrs_educ[data$sex == sex]  
                                             + stage1.models[[sex]]$coefficients$fixed[4] 
                                             + data$ctr_re[data$sex == sex]) + stage1.models[[sex]]$coefficients$fixed[3]*data$hiv[data$sex == sex] 
  } 
  data$pred.1.wRE <- 1-exp(-45*(data$pred.mx.wRE))
  
  # calculate residuals from final first stage regression
  data$resid <- logit(data$mort) - logit(data$pred.1.noRE)
  return(data)
} # End run_first_stage function

## Run first stage model -- if it fails on this sim, use the data from the previous sim as input into the function
result <- tryCatch({
  run_first_stage(data)
}, error = function(err) {
  sim_minus = sim - 1
  data <- import_sim(sim_minus)  # Use previous sim's data
  run_first_stage(data)           # Run first stage off of previous sim's data
}) # End tryCatch


if (hivsims) {
  setwd(paste0("strPath"))
  write.csv(result, paste0("prediction_model/first_stage_results",sim,".csv"))
} else {
  write.csv(result, paste0("prediction_model/first_stage_results.csv"))
}

####################################
## TESTING Part 1
#   for (sex in c("male","female")) {
#     for(iso in unique(data$ihme_loc_id)){
#       plot(data$year[data$ihme_loc_id == iso & data$sex == sex], 
#            data$mort[data$ihme_loc_id == iso & data$sex == sex], 
#            xlim=c(1950,2013),ylim=c(0.05,.6),
#            col = "black",pch=19, main = iso)
#       lines(data$year[data$ihme_loc_id == iso & data$sex == sex],
#            data$pred.1.noRE[data$ihme_loc_id == iso & data$sex == sex],
#            lty=1, lwd=2, col="red")
#       lines(data$year[data$ihme_loc_id == iso & data$sex == sex],
#            data$pred.1.wRE[data$ihme_loc_id == iso & data$sex == sex],
#            lty=1, lwd=2, col="green")
#       legend(x=1950,y=0.6,
#              legend=c("Point Estimates","Stage 1 w/out RE","Stage 1 w/ RE"),
#              col=c("black","red","green"),lty=1,lwd=8)
#       par(ask = T)
#     }
#   }
#####################################


