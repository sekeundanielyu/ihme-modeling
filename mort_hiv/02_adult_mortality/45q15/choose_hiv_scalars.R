##################################
## calculate HIV deleted 45q15 with different scalars
##################################

## This performs the following steps
# 1. Fit the first stage model 
# 2. calculate 45m15 from the 45q15 GPR results
# 3. subtract HIV*scalar*Beta from the 45m15
# 4. back calculate to get the without HIV 45q15


################################################################################
## Description: Run the first stage of the prediction model for adult mortality
##              and calculate inputs to GPR 
################################################################################

# source("strPath/02_fit_prediction_model.r")

rm(list=ls())
library(foreign); library(zoo); library(nlme); library(data.table); library(ggplot2)

## Set local working directory (toggles by GIT user) 
if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  code_dir <- paste0("strPath")
  sim <- as.numeric(commandArgs()[3])  ## this gets passed as 1 if not doing HIV sims, but gets ignored in the rest of the code, so it doesn't matter
  hivsims <- as.logical(as.numeric(commandArgs()[4]))
} else {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("strPath")
  sim <- 1 ## this gets passed as 1 if not doing HIV sims, but gets ignored in the rest of the code, so it doesn't matter
  hivsims <- F
}
data_dir <- paste(root, "strPath", sep="")
source(paste(code_dir,"/space_time.r", sep = ""))


## set transformation of the data for the GPR stage: choose from c("log10", "ln", "logit", "logit10")
transform <- "logit"

###############
## Read in data
###############
setwd(data_dir)
data <- read.csv("input_data.txt", stringsAsFactors=F)
data <- data[!is.na(data$sex),] 

# # create a specific region type for the regression
# data$region_hiv <- "Rest_of_World"
# data[data$super_region_name=="Sub-Saharan_Africa" & (data$region_name !="Southern_Sub_Saharan_Africa"),]$region_hiv <- "SSA_no_south"
# data[data$region_name=="Southern_Sub_Saharan_Africa",]$region_hiv <- "Southern_Sub_Saharan_Africa"

# data[data$super_region_name=="Latin_America_and_Caribbean" & !(data$region_name=="Caribbean"),]$region_hiv <- "Latin_America"
# data[data$region_name=="Caribbean",]$region_hiv <- "Caribbean"


hiv <- as.data.table(data[,c("ihme_loc_id", "sex", "year", "hiv", "region_name")])


source(paste0(root,"strPath/get_locations.r"))
locations <- get_locations(level="estimate")
locs_gbd2013 <- unique(locations$ihme_loc_id[!is.na(locations$local_id_2013) | grepl("ZAF_", locations$ihme_loc_id)])
locs_gbd2013 <- locs_gbd2013[locs_gbd2013!="ZAF"]

# # temporary
# locs_gbd2013 <-  unique(locations$ihme_loc_id[locations$region_name=="Southern Sub-Saharan Africa"]) 
# locs_gbd2013 <- locs_gbd2013[locs_gbd2013!="ZAF"]
# temporarily reverse scalars so we can get fit with and without
# 
#   # .9 scalars
#   data[data$ihme_loc_id %in% c("BWA", "CAF", "TZA", "ZAF_487", "ZAF_488"),]$hiv <- data[data$ihme_loc_id %in% c("BWA", "CAF", "TZA", "ZAF_487", "ZAF_488"),]$hiv/.9
#   # .8 scalars
#   data[data$ihme_loc_id %in% c("LSO", "MOZ", "SWZ", "ZWE"),]$hiv <- data[data$ihme_loc_id %in% c("LSO", "MOZ", "SWZ", "ZWE"),]$hiv/.8
#   # .7 scalars
#   data[data$ihme_loc_id %in% c("MWI","UGA"),]$hiv <- data[data$ihme_loc_id %in% c("MWI","UGA"),]$hiv/.7
#   # .65 scalars
#   data[grepl("KEN",data$ihme_loc_id),]$hiv <- data[grepl("KEN",data$ihme_loc_id),]$hiv/.65
#   # .6 scalars
#   data[data$ihme_loc_id %in% c("ZAF_484", "ZAF"),]$hiv <- data[data$ihme_loc_id %in% c("ZAF_484", "ZAF"),]$hiv/.6
#   # .5 scalars
#   data[data$ihme_loc_id %in% c("GAB", "NAM", "NGA", "ZMB"),]$hiv <- data[data$ihme_loc_id %in% c("GAB", "NAM", "NGA", "ZMB"),]$hiv/.5
#   # .3 scalars
#   data[data$ihme_loc_id %in% c("ERI"),]$hiv <- data[data$ihme_loc_id %in% c("ERI"),]$hiv/.3
#   
# 


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
  
  
  
  ## Temp fix: Merge back in the subnational data onto the GBD2013
  data <- rbind(data,data_sub)
  
  #Merge iso3 random effects into data
  for (sex in unique(data$sex)) {
    for (ii in rownames(stage1.models[[sex]]$coefficients$random$ihme_loc_id)) data$ctr_re[data$ihme_loc_id == ii & data$sex == sex] <- stage1.models[[sex]]$coefficients$random$ihme_loc_id[ii,1]
  }
  data$ctr_re[is.na(data$ctr_re)] <- 0
  
  # create random slope variable for hiv
#   data$hiv_re <- 0
#   #Merge region random effects into data
#   for (sex in unique(data$sex)) {
#     for (ii in rownames(stage1.models[[sex]]$coefficients$random$region_hiv)) data$hiv_re[data$region_hiv == ii & data$sex == sex] <- stage1.models[[sex]]$coefficients$random$region_hiv[ii,1]
#   }
#  
  
  #Get data back in order
  data <- data[order(data$sex,data$ihme_loc_id, data$year),]

  
  #Predictions with random effects (or, if RE == NA, then return without RE)
  ### REMOVE HIV
  for (sex in unique(data$sex)) {
    data$pred.mx.wRE[data$sex == sex] <- exp(stage1.models[[sex]]$coefficients$fixed[1]*data$tLDI[data$sex == sex] 
                                             + stage1.models[[sex]]$coefficients$fixed[2]*data$mean_yrs_educ[data$sex == sex]  
                                             + stage1.models[[sex]]$coefficients$fixed[4] 
                                             + data$ctr_re[data$sex == sex]) 
  } 
  data$pred.1.wRE <- 1-exp(-45*(data$pred.mx.wRE))
  return(list(stage1.models, data))
  
  
} # End run_first_stage function


models <- run_first_stage(data)
male_hiv_coef <- models[[1]][["male"]]$coefficients$fixed[3]
female_hiv_coef <- models[[1]][["female"]]$coefficients$fixed[3]
data <- as.data.table(models[[2]])

#####################################
## Read in 45q15 estimates 
#####################################

est <- fread(paste0(root,"strPath/estimated_45q15_noshocks.txt"))

# convert to 45m15
est[,mx:=log(1-mort_med)/(-45)]
est[,scalar:=0]


# # create random slope variable for hiv
# hiv$hiv_re <- 0
# #Merge region random effects into data
# for (sex in unique(hiv$sex)) {
#   for (ii in rownames(models[[1]][[sex]]$coefficients$random$region_hiv)) hiv$hiv_re[hiv$region_hiv == ii & hiv$sex == sex] <- models[[1]][[sex]]$coefficients$random$region_hiv[ii,1]
# }
# 

#merge in hiv

est <- merge(est, hiv, by=c("ihme_loc_id", "sex", "year"), all.x=T)





# create rows for each scalar
est_scale <- lapply(seq(.1,1,.1), function(scale){
  temp <- copy(est)
  temp[,scalar:=scale]
  return(temp)
})

est <- rbindlist(est_scale)
est[,coef:=ifelse(sex=="female",female_hiv_coef, male_hiv_coef)]

# merge in hiv

est[,mx_no_hiv:=mx-coef*scalar*hiv]

# convert mx back to qx


est[,mort_no_hiv:= 1-exp(-45*mx_no_hiv)]
est[,scalar:=as.factor(scalar)]




# 
pdf("strPath/45q15_hiv_deleted_with_scalars_delta2.pdf", width=11, height=8.5)
for(loc in unique(est$ihme_loc_id)){
  for(s in c("female", "male")){
    temp <- est[ihme_loc_id==loc & sex==s & year,]
    plot <- ggplot(data=temp) +
            geom_line(aes(x=year, y=mort_no_hiv, group=scalar, colour=scalar)) +
            geom_line(aes(x=year, y=mort_med)) +
            geom_line(data=data[ihme_loc_id==loc & sex==s,], aes(x=year, y=pred.1.wRE), linetype=2 ) +
            ggtitle(paste0(loc,"_", s))
    print(plot)
  }
}

dev.off()

# # Africa and IND
# africans <- as.character(unique(data[super_region_name=="Sub-Saharan_Africa",]$ihme_loc_id))
# indians <- as.character(unique(data[grepl("IND",ihme_loc_id),]$ihme_loc_id))
# 
# pdf("strPath/45q15_hiv_deleted_with_scalars_Africa_and_India.pdf", width=11, height=8.5)
# for(loc in c(africans, indians)){
#   for(s in c("female", "male")){
#     temp <- est[ihme_loc_id==loc & sex==s & year,]
#     plot <- ggplot(data=temp) +
#       geom_line(aes(x=year, y=mort_no_hiv, group=scalar, colour=scalar)) +
#       geom_line(aes(x=year, y=mort_med)) +
#       geom_line(data=data[ihme_loc_id==loc & sex==s,], aes(x=year, y=pred.1.wRE), linetype=2 ) +
#       ggtitle(paste0(loc,"_", s))
#     print(plot)
#   }
# }
# 
# dev.off()


# now check that what scalars we chose - hiv rates we pull in should already have scalars applied, so just plot where scalar=1
# 
# 
# pdf("strPath/45q15_hiv_deleted_check_scalars_SSSA_only.pdf", width=11, height=8.5)
# #for(loc in unique(est$ihme_loc_id)){
# for(loc in c(locs_gbd2013, "ZAF")){
#   for(s in c("female", "male")){
#     temp <- est[ihme_loc_id==loc & sex==s & year & scalar==1,]
# #     plot <- ggplot(data=temp) +
# #       geom_line(aes(x=year, y=mort_no_hiv, colour="counterfactual")) +
# #       geom_line(aes(x=year, y=mort_med, colour="GPR"), colour="black") +
# #       geom_line(data=data[ihme_loc_id==loc & sex==s,], aes(x=year, y=pred.1.wRE, colour="First Stage"), colour="black", linetype=2) +
# #       ggtitle(paste0(loc,"_", s))
# #     print(plot)
#     data_temp <- data[ihme_loc_id==loc & sex==s,]
#     maxy <- max(max(data_temp$pred.1.wRE), max(temp$mort_no_hiv), max(temp$mort_med))
#     miny <- min(min(data_temp$pred.1.wRE), min(temp$mort_no_hiv), min(temp$mort_med))
#     plot(y=temp$mort_no_hiv, x=temp$year,col="red", type="l",ylim=c(miny, maxy), main=paste0(loc,"_", s))
#     lines(x=temp$year, y=temp$mort_med, col="black")
#     lines(x=data_temp$year, y=data_temp$pred.1.wRE, col="black", type="b")
#     #print(plot)
#   }
# }
# 
# dev.off()

