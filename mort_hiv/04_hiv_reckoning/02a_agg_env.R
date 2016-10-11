## Grant Nguyen
## Aggregate from location-specific, granular ages to all-location, age- and sex-aggregated results
rm(list=ls())
library(data.table); library(foreign); library(reshape2)

## Setup filepaths
if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  user <- Sys.getenv("USERNAME")
  
  type <- "BHS"
  in_dir <- "strPath/"
} else {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  
  type <- commandArgs()[3]
  
  if(type == "hiv_free") {
    master_dir <- paste0("strPath")
    in_dir <- paste0(master_dir,"/draws/result")
    region_dir <- paste0(master_dir,"/draws")
    out_dir_draw <- in_dir
    out_dir_summary <- paste0(master_dir,"/summary/result")
  } else if(type == "with_hiv") {
    master_dir <- paste0("strPath")
    in_dir <- paste0(master_dir,"/result")
    region_dir <- paste0(master_dir)
    out_dir_draw <- in_dir
    out_dir_summary <- paste0(master_dir,"/summary")
  }
}

## Grab functions to aggregate everything
source(paste0(root,"/strPath/agg_results.R"))
source(paste0(root,"/strPath/get_locations.r"))
source(paste0(root,"/strPath/get_age_map.r"))

locations <- data.table(get_locations(level="all"))
locations <- locations[,list(location_id,ihme_loc_id)]

lowest <- data.table(get_locations(level="lowest"))
lowest <- lowest[,list(location_id)]

aggs <- unique(locations[!location_id %in% unique(lowest[,location_id]),location_id])
sdi_aggs <- data.table(get_locations(gbd_type="sdi"))
sdi_aggs <- unique(sdi_aggs[level==0,location_id])
all_aggs <- c(aggs,sdi_aggs) # This should have all location aggregates that we want to keep

age_map <- data.table(get_age_map(type="all"))
age_map <- age_map[,list(age_group_id,age_group_name)]

## Provide ID variables, value variables, and dataset -- then aggregate
data <- data.table(fread(paste0(in_dir,"/combined_env.csv")))
value_vars <- c(rep(paste0("env_",0:999)),"pop")
id_vars <- c("location_id","year_id","sex_id","age_group_id")
data <- agg_results(data,id_vars = id_vars, value_vars = value_vars, age_aggs = "gbd_compare", agg_sex = T, loc_scalars=T, agg_sdi=T)

## Output aggregated locations
save_aggs <- function(data) {
  for(loc in all_aggs) {
    write.csv(data[location_id==loc,],paste0(region_dir,"/agg_env_",loc,".csv"),row.names=F)
  }
}

save_aggs(data)


## Merge on identifiers
data <- merge(data,age_map,by="age_group_id")
write.csv(data,paste0(out_dir_draw,"/combined_env_aggregated.csv"))

## Collapse to summary statistics
enve_mean <- apply(data[,.SD,.SDcols=c(rep(paste0("env_",0:999)))],1,mean)
enve_lower <- apply(data[,.SD,.SDcols=c(rep(paste0("env_",0:999)))],1,quantile,probs=.025,na.rm=T)
enve_upper <- apply(data[,.SD,.SDcols=c(rep(paste0("env_",0:999)))],1,quantile,probs=.975,na.rm=T)
data <- data[,.SD,.SDcols=c(id_vars,"pop","location_id","age_group_name")]
data <- cbind(data,enve_mean,enve_lower,enve_upper)

write.dta(data,paste0(out_dir_summary,"/agg_env_summary.dta"))

