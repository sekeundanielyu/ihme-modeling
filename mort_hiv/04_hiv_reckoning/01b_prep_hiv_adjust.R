## Create HIV adjustment summary results for MortVIZ
rm(list=ls())
library(data.table); library(foreign); library(reshape2); library(haven)

## Setup filepaths
if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  user <- Sys.getenv("USERNAME")
  
  location <- 6
} else {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  
  location <- commandArgs()[3]
  spec_name <- commandArgs()[4]
  new_upload_version <- commandArgs()[5]
  
  in_dir_hiv <- paste0("strPath/",spec_name)
  results_dir <- paste0(root,"/strPath")
}

## Grab functions to aggregate everything
source(paste0(root,"/strPath/agg_results.R"))
source(paste0(root,"/strPath/get_locations.r"))
source(paste0(root,"/strPath/get_age_map.r"))

## Specify subnationals that you need to aggregate
locations <- data.table(get_locations(level="all"))
loc_name <- unique(locations[location_id==location,ihme_loc_id])
lowest <- data.table(get_locations(level="lowest"))

## If it's a national (not SDI), find children through getting lowest locations
if(length(loc_name == 1)) { 
  child_locs <- lowest[grepl(loc_name,ihme_loc_id),]
  files <- unique(child_locs[,ihme_loc_id])
} else {
  ## If it's SDI, find children through using the SDI map (NOT ACTUALLY USED RIGHT NOW)
  lowest <- data.table(get_locations(gbd_type="sdi"))
  files <- unique(lowest[parent_id==location,ihme_loc_id])
}


## Bring in appropriate data
import_files <- function(country) {
  data <- data.table(fread(paste0(in_dir_hiv,"/reckon_reporting_",country,".csv")))
}

reckon_data <- rbindlist(lapply(files,import_files))

## Collapse to total deaths across all locations (already in number-space, so just need to collapse)
collapse_vars <- c("value")
id_vars <- c("sex_id","year_id","age_group_id","measure_type")

reckon_data <- data.table(reckon_data)[,lapply(.SD,sum),.SDcols=collapse_vars,
                             by=c(id_vars,"sim")]

## Create a both-sexes aggregate
sex_agg_vars <- id_vars[!grepl("sex_id",id_vars)]
both_sexes <- data.table(reckon_data)[,lapply(.SD,sum),.SDcols=collapse_vars,
                                      by = c(sex_agg_vars,"sim")]
both_sexes[,sex_id:=3]
reckon_data <- rbindlist(list(reckon_data,both_sexes),use.names=T)

## Collapse to mean, lower, and upper
mean_vals <- data.table(reckon_data)[,lapply(.SD,mean),.SDcols=collapse_vars,
                                       by=id_vars]
setnames(mean_vals,c("value"),c("mean"))

lower_vals <- data.table(reckon_data)[,lapply(.SD,quantile,probs=.025),.SDcols=collapse_vars,
                                     by=id_vars]
setnames(lower_vals,c("value"),c("lower"))

upper_vals <- data.table(reckon_data)[,lapply(.SD,quantile,probs=.975),.SDcols=collapse_vars,
                                     by=id_vars]
setnames(upper_vals,c("value"),c("upper"))


## Combine and output data
output <- merge(mean_vals,lower_vals,by=id_vars)
output <- merge(output,upper_vals,by=id_vars)

output[,location_id:=location]
output[,run_id:=new_upload_version]
write.csv(output,paste0(results_dir,"/results_",location,".csv"),row.names=F)



