## Grant Nguyen
## Create lifetables for aggregate locations, create summary lifetable file, add onto current LT file
rm(list=ls())
library(data.table); library(foreign); library(reshape2)

## Setup filepaths
  if (Sys.info()[1]=="Windows") {
    root <- "J:" 
    user <- Sys.getenv("USERNAME")
    
    type <- "hiv_free"
  } else {
    root <- "/home/j"
    user <- Sys.getenv("USER")
    
    type <- commandArgs()[3]
    
    if(type == "hiv_free") {
      master_dir <- paste0("strPath")
      lt_dir <- paste0("strPath")
    } else if(type == "with_hiv") {
      master_dir <- paste0("strPath")
      lt_dir <- paste0("strPath")
    }
  }

## Grab function to calculate lifetables at the region level
  source(paste0(root,"/strPath/lt_functions.R"))
  source(paste0(root,"/strPath/get_locations.r"))
  source(paste0(root,"/strPath/get_age_map.r"))
  age_map <- data.table(get_age_map(type="lifetable"))
  age_map <- age_map[,list(age_group_id,age_group_name_short)]
  setnames(age_map,"age_group_name_short","age")
  
## Read in data (stored as 10 files called region_#.csv)
  setwd(paste0(master_dir,"/result"))
  files <- paste0("region_",rep(0:9),".csv")
  mx_ax_compiled <- data.table(rbindlist(lapply(files,function(x) fread(x))))

## Output location-specific files
  save_mx_ax <- function(data) {
    data <- data[,list(location_id,age_group_id,sex_id,year_id,draw,mx,ax)]
    for(loc in unique(data[,location_id])) {
      write.csv(data[location_id==loc,],paste0(master_dir,"/agg_mx_ax_",loc,".csv"),row.names=F)
    }
  }
  
  save_mx_ax(mx_ax_compiled)

## Format combined file for LT function
  format_for_lt <- function(data) {
    data[,qx:=0]
    data[sex_id==1,sex:="male"]
    data[sex_id==2,sex:="female"] 
    data[sex_id==3,sex:="both"]
    data[,id:=paste0(location_id,"_",draw)]
    data[,age:=as.numeric(age)]
    setnames(data,"year_id","year")
    
    return(data)
  }
  
  mx_ax_compiled <- merge(mx_ax_compiled,age_map,by="age_group_id")
  mx_ax_compiled <- format_for_lt(mx_ax_compiled)

## Summarize regions as a whole, add on summary file from earlier, and save combined_agg results file
  summarize_lt <- function(data) {
    varnames <- c("ax","mx")
    data <- data.table(data)[,lapply(.SD,mean),.SDcols=varnames,
                             by=c("location_id","age_group_id","age","sex_id","sex","year")]
    data[,id:=location_id] 
    data[,qx:=0]
    
    # Rerun lifetable function to recalculate life expectancy and other values based on the mean lifetable
    data <- lifetable(data.frame(data),cap_qx=1)
    data$id <- NULL
    return(data)
  }
  
  mx_ax_compiled <- summarize_lt(mx_ax_compiled)
  lowest_lts <- data.table(fread(paste0(lt_dir,"/result/combined_lt.csv")))
  print(colnames(mx_ax_compiled))
  print(colnames(lowest_lts))
  lts_compiled <- rbindlist(list(mx_ax_compiled,lowest_lts),use.names=T)
  
  write.csv(lts_compiled,paste0(lt_dir,"/result/combined_aggregated_lt.csv"),row.names=F)
  

