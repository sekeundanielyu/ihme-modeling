################################################################################
## Description: Run the second stage model 
################################################################################

# source("strPath/07a_fit_second_stage.R")

## set up 

rm(list=ls())
library(foreign); library(zoo); library(nlme); library(data.table); library(plyr); library(reshape); library(ggplot2)

## Set local working directory (toggles by GIT user) 
if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  code_dir <- paste0("strPath")
  sim <- as.numeric(commandArgs()[3])  ## this gets passed as 1 if not doing HIV sims
  hivsims <- as.logical(as.numeric(commandArgs()[4]))
} else if (Sys.getenv("USERNAME") != "msfraser") {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("strPath")
  sim <- 1 ## this gets passed as 1 if not doing HIV sims
  hivsims <- F
}  else {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("strPath")
  sim <- 1 ## this gets passed as 1 if not doing HIV sims
  hivsims <- F
}


if (hivsims) {
  setwd(paste0("strPath"))
  data <- read.csv(paste0("strPath/first_stage_results",sim,".csv"),stringsAsFactors=F)
} else {
  setwd(paste(root, "strPath", sep=""))  
  data <- read.csv("strPath/first_stage_results.csv", stringsAsFactors=F)
}

source(paste(code_dir,"/space_time.r", sep = ""))

transform="logit"
setwd(paste(root, "strPath", sep=""))
parameters <- read.csv("strPath/selected_parameters.txt")


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

## classify into 2013 categories so that we can use those for the mse

types <- ddply(.data=data, .variables=c("ihme_loc_id","sex"),.inform=T,
               .fun=function(x) {
                 cats <- unique(x$category)
                 cats <- cats[!is.na(cats)] # get rid of NA 
                 vr <- mean(x$vr, na.rm=T)
                 if(is.na(vr)) vr <- 0
                 vr.max <- ifelse(vr == 0, 0, max(x$year[x$vr==1 & !is.na(x$vr)]))
                 vr.num <- sum(x$vr==1, na.rm=T)
                 if (length(cats) == 1 & cats[1] == "complete" & vr == 1 & vr.max > 1980 & vr.num > 10){
                   type <- "complete VR only"
                 } else if (("ddm_adjust" %in% cats | "gb_adjust" %in% cats) & vr == 1 & vr.max > 1980 & vr.num > 10){
                   type <- "VR only"
                 } else if ((vr < 1 & vr > 0) | (vr == 1 & (vr.max <= 1980 | vr.num <= 10))){
                   type <- "VR plus"
                 } else if ("sibs" %in% cats & vr == 0){
                   type <- "sibs"
                 } else if (!("sibs" %in% cats) && length(cats) > 0 && vr == 0){
                   type <- "other"
                 } else{ 
                    type <- "no data"
                 }
                 return(data.frame(type2013=type, stringsAsFactors=F))
               })  

data <- merge(data, types, all.x=T, by=c("ihme_loc_id", "sex"))
# 
########################
# Fit second stage model
########################

# calculate residuals from final first stage regression
data$resid <- logit(data$mort) - logit(data$pred.1.noRE)

# fit space-time
# we do this three times: 
#   once with subnational (India states) and no parent countries, 
#   once with subnational (India states/urbanicity)
#   once with no subnational and only national level data

data$ihme_loc_id <- as.character(data$ihme_loc_id)
data_all <- data
tmp <- list()
i <- 0
for (level in 1:3) {
  i <- i+1
  
  total_list <- get(paste0("level_",level))
  keep_list <- get(paste0("keep_level_",level))
  
  cat(paste("Level ",level,"\n")); flush.console()
  
  ## only keep iso3s we want
  data <- data_all[data_all$ihme_loc_id %in% total_list,] 
  
  # make North Korea their own region
  nkr <- data$region_name[data$ihme_loc_id=="PRK"][1]
  data$region_name[data$ihme_loc_id=="PRK"] <- "North_Korea"
  
  # Taking out this separate subnational regions -- Sweden males have no data and crash
  ## make separate subnational regions
  #     if (subnational) {
  #       data$region_name <- paste(data$region_name,
  #                                 data$parent_id,
  #                                 sep="___")
  #       data$region_name[data$parent_id == 180] <- paste("Eastern_Sub-Saharan_Africa","174",sep="___") # Analyze Kenya with E SSA since there is NO KENYA DATA
  #     }
  
  ## do space time regression
  preds <- resid_space_time(data,subnational, post_param_selection=T)
  
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
data <- as.data.frame(rbindlist(tmp))

####################################
#TESTING pt. 2
#   for (sex in c("male","female")) {
#     for(iso in unique(data$ihme_loc_id)){
#       plot(data$year[data$ihme_loc_id == iso & data$sex == sex], 
#               data$mort[data$ihme_loc_id == iso & data$sex == sex], 
#               xlim=c(1950,2013),ylim=c(0.05,.6),main = iso,col="black",pch=19)
#       lines(data$year[data$ihme_loc_id == iso & data$sex == sex], 
#            data$pred.1.noRE[data$ihme_loc_id == iso & data$sex == sex], 
#            col = "red",lty=1, lwd=2)
#       lines(data$year[data$ihme_loc_id == iso & data$sex == sex],
#             data$pred.2.final[data$ihme_loc_id == iso & data$sex == sex],
#             lty=1, lwd=2, col="blue")
#       legend(x=1950,y=0.6,
#              legend=c("Point Estimates","Stage 1 w/ RE","Stage 2"),
#              col=c("black","red","blue"),lty=1,lwd=8)
#       par(ask = T)
#     }
#   }
#####################################

################
# Calculate GPR inputs
################  

## Mean squared error
if (transform == "log10") se <- (log(data$mort, base=10) - log(data$pred.2.final, base=10))^2 ## if log base 10
if (transform == "ln") se <- (log(data$mort) - log(data$pred.2.final))^2 ## if natural log
if (transform == "logit") se <- (logit(data$mort) - logit(data$pred.2.final))^2 ## if logit
if (transform == "logit10") se <- (logit10(data$mort) - logit10(data$pred.2.final))^2 ## if logit10

# calculate mse by the 2013 type
# mse <- tapply(se[data$type2013!="no data"], data$type2013[data$type2013 != "no data"], function(x) mean(x, na.rm=T)) 
# for (ii in names(mse)) data$mse[data$type2013 == ii] <- mse[ii]
# data$mse[data$type == "no data"] <- max(data$mse, na.rm=T)

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
if (transform == "log10") data$dev <- abs(log(data$mort, base=10) - log(data$pred.1.noRE, base=10)) ## if log base 10
if (transform == "ln") data$dev <- abs(log(data$mort) - log(data$pred.1.noRE)) ## if natural log
if (transform == "logit") data$dev <- abs(logit(data$mort) - logit(data$pred.1.noRE))## if logit
if (transform == "logit10") data$dev <- abs(logit10(data$mort) - logit10(data$pred.1.noRE))## if logit10
mad <- aggregate(data$dev[cc], data[cc,c("super_region_name", "sex")], median)
data <- merge(data[,names(data)!="x"], mad, all.x=T)
cc <- (data$category == "sibs" & !is.na(data$category))
data$var[cc] <- (1.4826*data$x[cc])^2
# data$var[cc] <- 0 # Temp if you only want to use the VR data variance below, and not include the first stage DV


## For Sibs (category V), add in MSE of sibs vs. VR to data variance
## NOTE: Not used after 10/7 -- didn't add much to data variance compared to other changes, and complicated the overall calculations
## First, find the observations to compare (sibs vs. DDM adjusted/complete data points), where a given iso3/sex/year has at least 1 obs of each
# sibs <- unique(data[data$category == "sibs" | data$source_type == "VR" | data$source_type == "VR-SSA" ,c("ihme_loc_id","sex","category","year")])
# sibs$category[sibs$category != "sibs"] <- "not_sibs"
# sibs <- sibs[!is.na(sibs$ihme_loc_id),]
# sibs$id <- paste(sibs$ihme_loc_id,sibs$sex,sibs$year, sep = "__")
# sibs <- cast(sibs, id~category, length, value = "ihme_loc_id")
# sibs <- sibs[sibs$not_sibs >= 1 & sibs$sibs >= 1,]
# 
# vars <- colsplit(sibs$id,"__",names = c("ihme_loc_id","sex","year"))
# 
# sibs_analysis <- merge(data,vars)
# sibs_analysis <- sibs_analysis[,c("ihme_loc_id","sex","year","mort","category","exposure")]
# sibs_only <- sibs_analysis[sibs_analysis$category == "sibs",]
# nosibs <- sibs_analysis[sibs_analysis$category != "sibs",]
# 
# ## Second, get the logit difference of mortality in the sibs vs. VR datapoints and convert to variance
# names(nosibs)[names(nosibs) == "mort"] <- "mort_nosibs"
# nosibs$category <- NULL
# sibs_only$category <- sibs_only$exposure <- NULL
# sibs_only <- merge(sibs_only,nosibs, by = c("ihme_loc_id","sex","year"))
# sibs_only$dev <- abs(logit(sibs_only$mort) - logit(sibs_only$mort_nosibs))
# mad <- aggregate(sibs_only$dev, list(sibs_only[,c("sex")]), median)
# names(mad)[names(mad) == "Group.1"] <- "sex"
# mad$vrcomp_var <- (1.4826*mad$x)^2
# mad$x <- NULL
# mad$category <- "sibs"
# 
# # mad <- merge(mad,unique(data[,c("sex","var","category")]),all.x=T)
# 
# # Third, add the sibs vs. VR variance to the existing sibs vs. first-stage variance to generate a combined data variance metric
# # mad$newvar <- mad$vrcomp_var + mad$var
# # mad$vrcomp_var <- mad$var <- NULL
# 
# data <- merge(data,mad,by = c("sex","category"), all.x=T)
# data$var[data$category == "sibs" & !is.na(data$category)] <- data$var[data$category == "sibs" & !is.na(data$category)] + data$vrcomp_var[data$category == "sibs" & !is.na(data$category)]
# data$vrcomp_var <- NULL
# 
# # Fourth, graph sibs vs. no sibs data for general vetting purposes
# pdf(paste0(root, "strPath/sibs_vr_comparison.pdf"))
# scatter <- ggplot(sibs_only, aes(x = mort_nosibs, y = mort, color = ihme_loc_id, shape = sex)) +
#   geom_point(size = 3) + 
#   geom_abline() +
#   xlab("VR Mortality") +
#   ylab("Sibs Mortality") +
#   ggtitle("Comparison of Sibs vs. VR points in overlapping year/sex combinations")
# scatter
# dev.off()

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

# # bring in parameter file to calculate amp2 (this uses mse)
# 
# params <- read.csv(paste0(root, "strPath/selected_parameters.txt"))
# 
# #get rid of amp2 if it exists
# if(!(is.null(params$amp2))) params$amp2 <- NULL
# if(!(is.null(params$mse))) params$mse <- NULL
# params$X <- NULL
# 
# # this code used if need to calculate amp2 for all types
# data_collapsed <- data[,c("type", "mse")]
# 
# 
# data_collapsed <- data_collapsed[!duplicated(data_collapsed),]
# 
# params <- merge(params, data_collapsed, all.x=T, c("type"))
# params$amp2 <- params$mse*params$amp2x
# 
# #assign no data the maximum amp2 that occurs in other types
# maxamp2 <- max(params[params$type !="no data",]$amp2)
# 
# # nationals <- unique(locations[locations$level==3,]$ihme_loc_id)
# # 
# # maxamp2 <- max(data[data$type != "no data",]$amp2)
# # params$amp2 <- NA
# params[params$type=="no data",]$amp2 <- maxamp2
# 
# 
# 
# write.csv(params, paste0(root, "strPath/selected_parameters.txt"))
# write.csv(params, paste0(root, "strPath/", Sys.Date(), "selected_parameters_mse.txt"))
#           
# data <- merge(data, params[params$best==1,], all.x=T, by=c("type"))
# data$amp2 <- data$mse*data$amp2x
# maxamp2 <- max(data[data$type !="no data",]$amp2)
# params[params$type=="no data",]$amp2 <-
  
  
################
# Save output 
################    

data <- data[,c("location_id", "location_name", "super_region_name", "region_name", "ihme_loc_id", "sex", "year", "LDI_id", "mean_yrs_educ", "hiv",
                "data", "type", "category", "vr", "mort", "stderr", "log_mort", "log_stderr", 
                "pred.1.wRE", "pred.1.noRE", "resid", "pred.2.resid", "pred.2.final", "mse")]
data <- data[order(data$ihme_loc_id, data$sex, data$year, data$data),]

#write.csv(data, file="prediction_model/prediction_model_results_all_stages.txt", row.names=F)
#write.csv(data, file=paste("archive/prediction_model/prediction_model_results_all_stages_", Sys.Date() ,".txt", sep=""), row.names=F)


if (hivsims) {
  setwd(paste0("strPath"))
  write.csv(data, file=paste0("prediction_model/prediction_model_results_all_stages",sim,".txt"), row.names=F)
} else {
  write.csv(data, file="prediction_model/prediction_model_results_all_stages.txt", row.names=F)
  write.csv(data, file=paste("archive/prediction_model/prediction_model_results_all_stages_", Sys.Date() ,".txt", sep=""), row.names=F)
}



