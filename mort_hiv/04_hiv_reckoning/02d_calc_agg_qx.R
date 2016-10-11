## Create lifetables for aggregate locations, create summary lifetable file, add onto current LT file
rm(list=ls())
library(data.table); library(foreign); library(reshape2)

## Setup filepaths
if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  user <- Sys.getenv("USERNAME")
  
  country <- "G"
  loc_id <- "1"
  type <- "hiv_free"
  
} else {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  
  loc_id <- commandArgs()[3]
  type <- commandArgs()[4]
 
   if(type == "hiv_free") {
    mx_dir <- paste0("strPath")
    lt_dir <- paste0("strPath")
    qx_dir <- paste0("strPath")
  } else if(type == "with_hiv") {
    mx_dir <- paste0("strPath")
    lt_dir <- paste0("strPath")
    qx_dir <- paste0("strPath")
  }
}

## Grab function to calculate lifetables at the region level
  source(paste0(root,"strPath/lt_functions.R"))
  source(paste0(root,"strPath/get_locations.r"))
  source(paste0(root,"strPath/get_age_map.r"))
  source(paste0(root,"strPath/calc_qx.R"))
  age_map <- data.table(get_age_map(type="lifetable"))
  age_map <- age_map[,list(age_group_id,age_group_name_short)]
  setnames(age_map,"age_group_name_short","age")
  
  locations <- data.table(get_locations(level="all"))

## Read in data 
  mx_ax_compiled <- data.table(fread(paste0(mx_dir,"/agg_mx_ax_",loc_id,".csv")))

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

## Run lifetable function on the data
  lt_total <- data.table(lifetable(data.frame(mx_ax_compiled),cap_qx=1))
  lt_total[,id:=NULL]
  write.csv(lt_total[,list(age_group_id,sex_id,year,draw,mx,ax,qx,sex,age,n,px,lx,dx,nLx,Tx,ex)],
            paste0(lt_dir,"/lt_agg_",loc_id,".csv"),row.names=F)

  ## Collapse to 5q0 and 45q15 before saving 5q0 and 45q15
  summary_5q0 <- calc_qx(lt_total,age_start=0,age_end=5,id_vars=c("location_id","sex_id","year","draw"))
  setnames(summary_5q0,"qx_5q0","mean_5q0")
  summary_5q0 <- summary_5q0[,lapply(.SD,mean),.SDcols="mean_5q0", by=c("location_id","sex_id","year")]
  setcolorder(summary_5q0,c("sex_id","year","mean_5q0","location_id"))

  summary_45q15 <- calc_qx(lt_total,age_start=15,age_end=60,id_vars=c("location_id","sex_id","year","draw"))
  setnames(summary_45q15,"qx_45q15","mean_45q15")
  summary_45q15 <- summary_45q15[,lapply(.SD,mean),.SDcols="mean_45q15",by=c("location_id","sex_id","year")]
  setcolorder(summary_45q15,c("sex_id","year","mean_45q15","location_id"))
  
  write.csv(summary_5q0,paste0(qx_dir,"/mean_5q0_agg_",loc_id,".csv"),row.names=F)
  write.csv(summary_45q15,paste0(qx_dir,"/mean_45q15_agg_",loc_id,".csv"),row.names=F)



