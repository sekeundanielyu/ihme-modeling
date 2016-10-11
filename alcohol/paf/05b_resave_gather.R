## 05b- resave results by location-sex in chunks


rm(list=ls()); library(foreign); library(data.table); library(stringr); library(haven)

if (Sys.info()[1] == 'Windows') {
  username <- "strUser"
  root <- "J:/"
  code_dir <- "C:/Users//Documents/repos/drugs_alcohol/"
  
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  code_dir <- paste("/ihme/code/risk/", username, "/drugs_alcohol/", sep="")
  if (username == "") code_dir <- paste0("/homes//drugs_alcohol/")  
  arg <- commandArgs()[-(1:3)] 
  print(arg)
  temp_dir <- arg[1]
  yyy <- as.numeric(arg[2])
  cause_cw_file <- arg[3]
  version <- as.numeric(arg[4])
  out_dir <- arg[5]
  chunks <- as.numeric(arg[6])
  chunk <- as.numeric(arg[7])
  mort <- arg[8]
}


## read in year file
d <- as.data.frame(fread(paste0(out_dir,"/",version,"_prescale/paf_",mort,"_",yyy,".csv")))

num_locs <- length(unique(d$location_id))
n_locs <- ceiling(num_locs/chunks)
start <- (chunk - 1)*n_locs + 1
end <- (chunk - 1)*n_locs + n_locs
cat(paste0("saving locations ",start," to ",end,"\n")); flush.console()

locs <- sort(unique(d$location_id))
locs <- locs[start:end]

d <- d[d$location_id %in% locs,]


# Save
for (loc in unique(d$location_id)) {
  for (s in unique(d$sex_id)) {
    cat(paste0("writing ",loc," sex ",s,"\n")); flush.console()
    ## mort
    if (mort == "yll") write.csv(d[d$location_id == loc & d$sex_id == s & d$mortality == 1 & !is.na(d$mortality),],paste0(out_dir,"/",version,"_prescale/ylls/paf_yll_",loc,"_",yyy,"_",s,".csv"),row.names=F)
    ## morb
    if (mort == "yld") write.csv(d[d$location_id == loc & d$sex_id == s & d$morbidity == 1 & !is.na(d$morbidity),],paste0(out_dir,"/",version,"_prescale/ylds/paf_yld_",loc,"_",yyy,"_",s,".csv"),row.names=F)
  }
}



