################################################################################
## Description: Formats 5q0 data and covariates for the first and second
##              stage models
## Date Created: 04 May 2012
################################################################################

  rm(list=ls())
  
  library(foreign); library(reshape); library(plyr); library(data.table)

if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- ""
  code_dir <- ""
  source("get_locations.r")
  hivsims <- F
  rnum <- 1
} else {
  username <- commandArgs()[5]
  root <- ""
  code_dir <- paste("",username,"",sep="") # This is the username of the person running the code 
  source(paste0("get_locations.r"))
  rnum <- commandArgs()[3]
  hivsims <- as.integer(commandArgs()[4])
}

  print(hivsims)
  print(rnum)
  print(username)

####################
## Load covariates 
####################

## make a square dataset onto which we'll merge all covariates and data
  data <- get_locations()
  data <- data[data$level_all == 1,]
  data <- unique(na.omit(data[,c("ihme_loc_id","region_name","super_region_name","location_id","location_name")]))
  all_locs <- length(unique(data$ihme_loc_id))

  data$region_name <- gsub(" ", "_", gsub(" / ", "_", gsub(", ", "_", data$region_name)))
  data$super_region_name <- gsub(" ", "_", gsub("/", "_", gsub(", ", "_", data$super_region_name)))
  data$region_name[data$ihme_loc_id %in% c("GUY","TTO","BLZ","JAM","ATG","BHS","BMU","BRB","DMA","GRD","VCT","LCA","PRI")] <- "CaribbeanI"
  data <- merge(data, data.frame(year=1950:2015))
    
## get hiv numbers for this sim 
  hiv <- read.csv(ifelse(hivsims, paste("",rnum,sep = ""),
         paste(root,"formatted_hiv_5q0.csv", sep = "")), 
         stringsAsFactors = F)
  
  hiv <- hiv[,c("year","ihme_loc_id","hiv")]
  data <- merge(data,hiv,by=c("ihme_loc_id","year"), all.x= T)  
  data$hiv[is.na(data$hiv)] <- 0
  t1 <- dim(data)

## swap in updated hiv numbers where we have them
  hiv_update <- read.dta("compiled_hiv_summary.dta")
  hiv_update <- hiv_update[hiv_update$agegroup == "5q0",]
  names(hiv_update)[names(hiv_update) == "iso3"] <- "ihme_loc_id"
  hiv_update$agegroup <- NULL
  hiv_update$sex <- NULL
  
  data <- merge(data,hiv_update,by=c("ihme_loc_id","year"),all.x=T)
  data$hiv[!is.na(data$hiv_cdr)] <- data$hiv_cdr[!is.na(data$hiv_cdr)]
  data$hiv_cdr <- NULL
  stopifnot(dim(data) == t1)
  
## need to get covariates from database query function 
  source(paste0(root,"load_cov_functions.r"))
  ldi <- get_cov_estimates('LDI_pc')
  ldi_model_number <- unique(ldi$model_version_id)
  ldi <- ldi[,c("location_id","year_id","mean_value")]
  names(ldi) <- c("location_id","year","LDI_id")

  data <- merge(data,ldi,by=c("location_id","year"),all.x=T)
  stopifnot(length(unique(data$ihme_loc_id))==all_locs)
  
  educ <- get_cov_estimates('maternal_educ_yrs_pc')
  educ_model_number <- unique(educ$model_version_id)
  educ <- educ[,c("location_id","year_id","mean_value")]
  names(educ) <- c("location_id","year","maternal_educ")

  data <- merge(data,educ,by=c("location_id","year"),all.x=T)
  stopifnot(length(unique(data$ihme_loc_id))==all_locs)

stopifnot(!is.na(data$hiv))
stopifnot(!is.na(data$LDI_id))
stopifnot(!is.na(data$maternal_educ))

## load 5q0 data 
  q5.data <- read.table(paste(root, "raw.5q0.adjusted.txt", sep=""), 
                    sep="\t", header=T, stringsAsFactors=F)
  q5.data$source.date <- as.numeric(q5.data$source.date)
  names(q5.data)[names(q5.data) == "source.date"] <-"num_survey_date"
   
  #format
  names(q5.data)[names(q5.data) == "num_survey_date"] <- "source.yr" 
  q5.data$year <- floor(q5.data$year) + 0.5
                    

####################
## Merge everything together
####################
  data$year <- data$year + 0.5

## merge in 5q0 data
  data <- merge(data, q5.data[,names(q5.data) != "gbd_region"], by=c("ihme_loc_id", "year","location_name"), all.x=T)
  data$data <- as.numeric(!is.na(data$mort))      # this is an indicator for data avaialability across years 

## create variable for survey series indicator for survey random effects
  #this will identify 
  #SBH points by source, source year, and type (indirect)
  #CBH points by source and type (as we combine CBH data across source-years, and the years in source.yr don't actually relate to the survey dates)
  #VR points by source (just VR, assuming correlated across all years of VR)
  #NA points (SRS, CENSUSES, compiled estimates) by source (again, assuming correlated across all years of these estimates)
  #HH points by source (again, assuming correlated across years of estimation from one source)
  data$source1 <- rep(0, length(data$source))
  
  #sbh ind vector
  sbh_ind <- grepl("indirect", data$type, ignore.case = T)
  data$source1[sbh_ind] <- paste(data$source[sbh_ind], data$source.yr[sbh_ind], data$type[sbh_ind])
    
  #cbh indicator vector
  cbh_ind <- grepl("direct", data$type, ignore.case = T) & !grepl("indirect", data$type, ignore.case = T)
  data$source1[cbh_ind] <- paste(data$source[cbh_ind], data$type[cbh_ind]) 
  
  #hh indicator vector
  hh_ind <- grepl("hh", data$type, ignore.case = T)
  data$source1[hh_ind] <- paste(data$source[hh_ind], data$type[hh_ind])
  
  #everything else, only source
  data$source1[data$source1 == 0] <- data$source[data$source1 == 0]

  #fix for in-depth DHS's so that they have the same RE as normal DHS's (only PHL right now)
  data$source1[data$source1 == "DHS IN direct"] <- "DHS direct"
  data$source1[grepl("DHS SP",data$source1) & grepl("BGD|GHA|UZB",data$ihme_loc_id)] <- gsub("DHS SP","DHS", data$source1[grepl("DHS SP",data$source1) & grepl("BGD|GHA|UZB",data$ihme_loc_id)]) 
  
  #classify DHS completes from reports same as our DHS completes
  data$source1[grepl("DHS",data$source1, ignore.case = T) & grepl("report",data$source1, ignore.case = T) & grepl("direct",data$source1, ignore.case = T) & !grepl("indirect",data$source1, ignore.case = T)] <- "DHS direct"

  #classify province (and country) level DSP into before and after 2004
  #before = 0, after = 1
  dsp.ind <- data$source1 %in% c("DSP","China DSP hh")
  data$source1[dsp.ind] <- paste(data$source1[dsp.ind], as.numeric(data$year[dsp.ind] > 2004), sep = "_")
  
## format and save
  data <- data[order(data$ihme_loc_id, data$year),
    c("super_region_name", "region_name", "ihme_loc_id", "year", "LDI_id", "maternal_educ", "hiv", "mort", "category", "corr_code_bias","to_correct","source", "source.yr", "source1", "vr", "data","ptid","log10.sd.q5","location_name","type")]
  write.csv(data, ifelse(hivsims, paste("prediction_input_data_",rnum,".txt", sep=""),
                         paste(root, "prediction_input_data.txt", sep="")),
						 row.names=F)

  if(!hivsims) write.csv(data, paste(root, "prediction_input_data_", Sys.Date(), ".txt", sep=""),row.names=F)


