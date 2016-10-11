################################################################################
## Description: Prep data and estimates from 5q0, DDM, and 45q15 for iDie
################################################################################

rm(list=ls())
library(foreign); library(reshape)

setwd("strPath")    

# set objects for each of your filepaths so you only have to change them once!

wpp5q0_45q15filepath <- "strPath/un_wpp_data_5q0_45q15.dta"
hivcounterfactual_filepath <- "strPath/mean_hiv_counterfacutal.csv"

filepath_45q15prior <- "strPath/prediction_model_results_all_stages_2014-05-13.txt"
filepath_noshocks45q15 <- "strPath/estimated_45q15_noshocks.txt" 
filepath_shocks45q15 <-"strPath/estimated_45q1517 May 2014.txt"
save_45q15_est_filepath <- "strPath/estimates_45q15.dta"



############################
## prep UN WPP estimates
#############################
wpp <- read.dta(wpp5q0_45q15filepath)

wppkids <- wpp[wpp$process == "UN 5q0", c("year", "data_final","iso3")]
names(wppkids)[names(wppkids) == "data_final"] <- "wpp"
wppkids$iso3 <- as.factor(as.character(wppkids$iso3))
wppadult <- wpp[wpp$process == "UN 45q15", c("year", "sex", "data_final", "iso3")]
names(wppadult)[names(wppadult) == "data_final"] <- "wpp"
wppadult$iso3 <- as.factor(as.character(wppadult$iso3))
wppadult$sex <- as.factor(as.character(wppadult$sex))

file <- data.frame(file = "WPP",
                   date = file.info(wpp5q0_45q15filepath)$mtime,
                   stringsAsFactors=F)

############################
## prep hiv counterfactuals
###############################
hiv <- read.csv(hivcounterfactual_filepath)  

file <- rbind(file, data.frame(file = "HIV counterfactual",
                               date = file.info(hivcounterfactual_filepath)$mtime,
                               stringsAsFactors=F))    

hiv$year <- hiv$year + .5

# males and females for kids are the same; keep only one
hivkids <- hiv[hiv$sex == "female",c("iso3","year","sex","c_v5q0")]                                 
hivkids$sex <- NULL
names(hivkids)[names(hivkids) == "c_v5q0"] <- "hivfree"

# adult
hivadult <- hiv[,c("iso3","year","sex","c_v45q15")]
names(hivadult)[names(hivadult) == "c_v45q15"] <- "hivfree" 


####################
## 45q15 - Estimates
####################

prior <- read.csv(filepath_45q15prior)
# added in because the old model had this variable. This will be stage 1.  
prior$pred.1b <- prior$pred.1.noRE  
est1 <- read.csv(filepath_noshocks45q15, header = T)
est2 <- read.csv(filepath_shocks45q15, header = T)

file <- rbind(file, data.frame(file = "45q15 Prior",
                               date = file.info(filepath_45q15prior)$mtime,
                               stringsAsFactors=F))
file <- rbind(file, data.frame(file = "45q15 Noshocks Estimates",
                               date = file.info(filepath_noshocks45q15)$mtime,                      
                               stringsAsFactors=F))
file <- rbind(file, data.frame(file = "45q15 Shocks Estimates",
                               date = file.info(filepath_shocks45q15)$mtime,                      
                               stringsAsFactors=F))

## format
# rename things
names(prior)[names(prior) %in% c("pred.1a.wRE", "pred.1a.noRE")] <- c("pred.1.wRE", "pred.1.noRE")
all.est <- unique(prior[,c("iso3", "sex", "year", "pred.1.wRE", "pred.1.noRE", "pred.1b", "pred.2.final")])
names(est1) <- c("sex", "year", "iso3", "gpr.med", "gpr.upper", "gpr.lower")
all.est <- merge(all.est, est1, all.x=T)
names(est2) <- c("year", "sex", "iso3", "shocks.med", "shocks.lower", "shocks.upper")
all.est <- merge(all.est, est2, all.x=T)
all.est <- all.est[all.est$year >= 1950.5 & all.est$year <= dropyear,]



# add in HIV numbers
all.est <- merge(all.est,hivadult, by = c("iso3","year","sex"), all.x=T, all.y=T)

# merge on wpp 5q0 estimates
all.est <- merge(all.est,wppadult, by = c("iso3","year","sex"), all.x=T, all.y=T)


## save
write.dta(all.est, save_45q15_est_filepath)


####################
## Make Archive
####################

a <- paste("strPath", gsub(" ", "_", gsub(":", "-", Sys.time())), sep="")
dir.create(a)
for (ff in dir("strPath")) {
  file.copy(paste("strPath", ff, sep=""),
            paste(a, "/", ff, sep=""))
}


