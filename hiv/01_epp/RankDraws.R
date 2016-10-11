# clear environment
rm(list=ls(all=TRUE))

library(data.table)
library(reshape2)
library(RColorBrewer)     
library(ggplot2)
library(boot)

test <- F
if (Sys.info()[1] == "Linux" & test == F) {
  root <- "/home/j"
  run_date <- commandArgs()[3]
  iso3_file_date <- commandArgs()[4]
} else if (Sys.info()[1] == "Linux" & test == T) {
  root <- "/home/j" 
  run_date <- "160122"
  iso3_file_date <- "151209"
} else {
  root <- "J:"
  run_date <- "160122"
  iso3_file_date <- "151209"
}

iso3_f <- fread(paste0(root,'strPath/EPP_countries_',iso3_file_date,'.csv'))
iso3_list <- unique(iso3_f[,iso3])

for (iso3 in iso3_list) {
  print(iso3)
  tmp_iso3 <- iso3
  if (grepl('MOZ', iso3))
    tmp_iso3 <- 'MOZ'
  if (grepl('KEN', iso3))
    tmp_iso3 <- 'KEN'
  if (grepl('IND', iso3))
    tmp_iso3 <- 'IND'
  if (grepl('ZAF', iso3))
    tmp_iso3 <- 'ZAF'

  aims_folder <- 'strPath'
  
  progdata <- fread(paste0(root,aims_folder,'strPath',tmp_iso3,"_progression_par_draws.csv"))
  progdata <- progdata[,rank:=rank(-prog,ties.method="first"),by=c("age","cd4")]
  progdata <- progdata[,draw:=rank]
  progdata <- progdata[order(age,cd4,draw)]
  progdata <- progdata[,c("age","cd4","draw","prog"), with=F]
  write.csv(progdata, file = paste0(root,aims_folder,'strPath',iso3,"_progression_par_draws.csv"), row.names = F)
  
  mortnoart <- fread(paste0(root,aims_folder,'strPath',tmp_iso3,"_mortality_par_draws.csv"))
  mortnoart <- mortnoart[,rank:=rank(-mort,ties.method="first"),by=c("age","cd4")]
  mortnoart <- mortnoart[,draw:=rank]
  mortnoart <- mortnoart[order(age,cd4,draw)]
  mortnoart <- mortnoart[,c("age","cd4","draw","mort"), with=F]
  write.csv(mortnoart, file = paste0(root,aims_folder,'strPath',iso3,"_mortality_par_draws.csv"), row.names = F)
  
  mortart <- fread(paste0(root,aims_folder,"/HIVmort_onART_regions/DisMod/",tmp_iso3,"_HIVonART.csv"))
  mortart <- melt(mortart, 
                  id = c("durationart", "cd4_category", "age", "sex","cd4_lower",
                         "cd4_upper", "merge_super","_merge"))
  setnames(mortart, c("variable","value"), c("drawnum","draw"))
  mortart <- mortart[,drawnum := substr(drawnum, 5,8)]
  mortart <- mortart[,rank:=rank(-draw,ties.method="first"),by=c("durationart", "cd4_category", "age", "sex")]
  mortart <- mortart[,drawnum:=rank]
  mortart <- mortart[order(durationart,cd4_category,age,sex,drawnum)]
  mortart <- mortart[,c("durationart", "cd4_category", "age", "sex","cd4_lower",
                        "cd4_upper", "merge_super","_merge", "drawnum", "draw"), with=F]
  
  mortart <- data.table(dcast(mortart,durationart+cd4_category+age+sex~drawnum, value.var='draw'))
  for (i in 1:1000) {
    j <- i + 4
    setnames(mortart, j, paste0("draw",i))
  }
  write.csv(mortart, file = paste0(root,aims_folder,'strPath', iso3,"_HIVonART.csv"), row.names = F)
  print('...Finished')
}
