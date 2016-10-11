## Check for all alcohol output files

rm(list=ls()); library(foreign); library(data.table)

if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- "J:/"
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
}

##############
## Set options
##############

temp_dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
cause_cw_file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/meta/cause_crosswalk.csv")
version <- 1
out_dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output"	


## demographics
sexes <- c(1,2)
ages <- c(seq(15,80,by=5))
age_group_ids <- c(8:21)
years <- c(1990,1995,2000,2005,2010,2015)
if (length(ages) != length(age_group_ids)) stop("these must be equal length for files below to read in right")


missing_files <- c()
cause_groups <- c("chronic", "ihd","russia","russ_ihd_is","ischemicstroke","inj_self") 
for (ccc in cause_groups) {
  for (sss in sexes) {
    for (aaa in age_group_ids) {
      for (yyy in years) {
        ## inj_self still saved with age instead of age_group_id, so fix that for reading in here
        read_age <- aaa
        cat(paste0("checking ",read_age," ",yyy," ",sss," ",ccc,"\n")); flush.console()
        if (file.exists(paste0(temp_dir,"/AAF_",yyy,"_a",read_age,"_s",sss,"_",ccc,".csv"))) {
          
        } else {
          missing_files <- c(missing_files,paste0(temp_dir,"/AAF_",yyy,"_a",read_age,"_s",sss,"_",ccc,".csv"))
        }
      }
    }
  }
}

cause_groups <- c("inj_mvaoth","inj_aslt")
for (ccc in cause_groups) {
  for (yyy in years) {
    cat(paste0("checking ",yyy," ",ccc,"\n")); flush.console()
    if (file.exists(paste0(temp_dir,"/AAF_",yyy,"_",ccc,".csv"))) {
      
    } else {
      missing_files <- c(missing_files,paste0(temp_dir,"/AAF_",yyy,"_",ccc,".csv"))
    }
  }
}



