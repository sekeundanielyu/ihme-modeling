## Fill in missing variables in alcohol input

rm(list=ls()); library(foreign)

if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- "J:/"
  code_dir <- "C:/Users//Documents/repos/drugs_alcohol/exposure/"
  source("J:/Project/Mortality/shared/functions/get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  code_dir <- paste("/ihme/code/risk/", username, "/drugs_alcohol/exposure/", sep="")
  if (username == "") code_dir <- paste0("/homes//drugs_alcohol/exposure/")  
  setwd(code_dir)
  source("/home/j/Project/Mortality/shared/functions/get_locations.r")
}

locs <- get_locations(level="all")

## read in GBD 2013 files

dir_2013 <- paste0(root,"/WORK/2013/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output/GBD2013/")
dir_2015 <- "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/postscale/"
dir_2015_backup <- paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs/archive")

comp13 <- list()
for (i in c(1990,1995,2000,2005,2010,2013)) {
  comp13[[paste0(i)]] <- read.csv(paste0(dir_2013,"alc_data_",i,".csv"),stringsAsFactors = F)
  comp13[[paste0(i)]]$year <- i
}
comp13 <- do.call("rbind",comp13)

## vars I need to keep are BINGE_A, BINGE_A_SE, Threshold, and Threshold_SE
names(comp13)[names(comp13)=="REGION"] <- "ihme_loc_id"
comp13 <- merge(comp13,locs[,c("location_id","ihme_loc_id")],by="ihme_loc_id",all.x=T)
comp13$year[comp13$year == 2013] <- 2015
comp13$submerge <- comp13$ihme_loc_id


comp15 <- list()
for (i in c(1990,1995,2000,2005,2010,2015)) {
  comp15[[paste0(i)]] <- read.csv(paste0(dir_2015,"alc_data_",i,".csv"),stringsAsFactors = F)
  comp15[[paste0(i)]]$year <- i
}
comp15 <- do.call("rbind",comp15)

dims <- nrow(comp15)
comp15 <- comp15[,names(comp15)[!names(comp15) %in% c("parent_id","level","is_estimate","most_detailed","location_name","super_region_id","super_region_name","region_id","region_name","ihme_loc_id")]]

comp15 <- merge(comp15,locs[,c("location_id","ihme_loc_id")],by="location_id",all.x=T)
comp15 <- merge(comp15,comp13[,c("BINGE_A", "BINGE_A_SE", "Threshold","Threshold_SE","location_id","ihme_loc_id","year","SEX","AGE_CATEGORY")],
                by=c("ihme_loc_id","location_id","year","SEX","AGE_CATEGORY"),all.x=T)


## replace subnatioanals with nationals if missing
comp_add <- list()
for (i in unique(comp15$ihme_loc_id[is.na(comp15$BINGE_A)])) {
  cat(paste0(i,"\n")); flush.console()
  add <- comp15[comp15$ihme_loc_id == i,]
  add$submerge <- substr(add$ihme_loc_id,1,3)
  add$Threshold <- add$Threshold_SE <- add$BINGE_A <- add$BINGE_A_SE <- NULL
  add <- merge(add,comp13[,c("BINGE_A", "BINGE_A_SE", "Threshold","Threshold_SE","submerge","year","SEX","AGE_CATEGORY")],
               by=c("submerge","year","SEX","AGE_CATEGORY"),all.x=T)
  if (nrow(add) > 0) comp_add[[paste0(i)]] <- add
}
comp_add <- do.call("rbind",comp_add)

comp15 <- comp15[!comp15$location_id %in% unique(comp_add$location_id),]
comp_add$submerge <- NULL
comp15 <- rbind(comp15,comp_add)

## still some locations without binge amount, new gbd 2015 locations like American Samoa, Bermuda, Greenland
## we'll assume some normal juergen numbers for these
comp15$BINGE_A[comp15$ihme_loc_id %in% c("ASM","BMU","GRL","GUM","MNP","PRI","VIR","CHN","CHN_354","CHN_361","GBR") & comp15$SEX == 1] <- 84
comp15$BINGE_A[comp15$ihme_loc_id %in% c("MEX") & comp15$SEX == 1] <- 96 ## according to 2013 numbers used from Juergen
comp15$BINGE_A[comp15$ihme_loc_id %in% c("ASM","BMU","GRL","GUM","MNP","PRI","VIR","CHN","CHN_354","CHN_361","GBR","MEX") & comp15$SEX == 2] <- 72
comp15$BINGE_A_SE <- 0
comp15$Threshold_SE <- 0
comp15$Threshold[comp15$SEX == 1] <- 60
comp15$Threshold[comp15$SEX == 2] <- 48

if (any(is.na(comp15$Threshold)) | any(is.na(comp15$BINGE_A)) | any(is.na(comp15$BINGE_A_SE)) | any(is.na(comp15$Threshold_SE))) stop("missing values")

if (nrow(comp15)!=dims) stop("changed number of rows in dataset")

comp15$year <- comp15$ihme_loc_id <- NULL

for (i in unique(comp15$year_id)) {
  write.csv(comp15[comp15$year_id == i,],paste0(dir_2015,"alc_data_",i,".csv"),row.names=F)
  write.csv(comp15[comp15$year_id == i,],paste0(dir_2015_backup,"alc_data_",i,"_",Sys.Date(),".csv"),row.names=F)
  
}

