################################################################################
## Description: Compile GPR results after getting output at the country-level
################################################################################

#source("strPath/08b_compile_all.r")

rm(list=ls())
library(foreign); library(data.table); library(dplyr)

if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
setwd(paste(root, "strPath", sep=""))

hivuncert <- as.logical(as.numeric(commandArgs()[3]))
if (hivuncert) setwd(paste("strPath", sep=""))

## Get locations
source(paste0(root,"strPath/get_locations.r"))
codes <- get_locations(level = "estimate")

data=NULL
unscaled = NULL
file_errors <- 0
i <- 0

## Import results
for (cc in unique(codes$ihme_loc_id)) { 
  for (ss in c("male", "female")) { 
    print(paste0("Importing ",cc," ",ss))
    file <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_", cc, "_", ss, ".txt")
    file2 <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_", cc, "_", ss, "_not_scaled.txt")
    file_sim <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc, "_", ss, "_sim.txt")
    file_sim2 <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc, "_", ss, "_sim_not_scaled.txt")
    if (file.exists(file) & file.exists(file2)) { 
      i <- i + 1
      data[[i]] <- fread(file)
      unscaled[[i]] <- fread(file2)
    } else {
      cat(paste("Does not exist:", file,"\n")); flush.console()
      file_errors <- file_errors + 1
    }
    if(! file.exists(file_sim) | ! file.exists(file_sim2)) {
      cat(paste("Does not exist:", file_sim,"\n")); flush.console()
      file_errors <- file_errors + 1
    }
  } 
} 

data <- as.data.frame(rbindlist(data))
unscaled <- as.data.frame(rbindlist(unscaled))
unscaled <- select(unscaled, ihme_loc_id, sex, year, unscaled_mort = mort_med)
data <- merge(data,unscaled, by = c("ihme_loc_id","sex","year"))


## Check whether we have a full dataset
years <- unique(data$year)
sexes <- unique(data$sex)
countries <- unique(codes$ihme_loc_id)

counter = length(years) * length(sexes) * length(countries)
length_dataset <- nrow(data[!is.na(data$mort_med),])

if(length_dataset == counter & file_errors == 0) {
  print("All observations are accounted for")
} else {
  stop(paste0("We are expecting ",counter," observations but get ", length_dataset, " instead, and ",file_errors," files are missing"))
  # print(unique(data$ihme_loc_id[is.na(data$mort_med)]))
  # print(unique(data$year[is.na(data$mort_med)]))
}

setwd(paste(root, "strPath", sep=""))
## save final file 
data <- data[order(data$ihme_loc_id, data$sex, data$year),]
write.csv(data[,c("ihme_loc_id","sex","year","mort_med","mort_lower","mort_upper","unscaled_mort")], file="strPath/estimated_45q15_noshocks.txt", row.names=F)
file.copy("strPath/estimated_45q15_noshocks.txt",paste("strPath/estimated_45q15_noshocks_", Sys.Date(), ".txt", sep=""))
write.csv(data[,c("ihme_loc_id","sex","year","mort_med","mort_lower","mort_upper","unscaled_mort","med_hiv","med_stage1","med_stage2")], file="strPath/estimated_45q15_noshocks_wcovariate.txt", row.names=F)
file.copy("strPath/estimated_45q15_noshocks_wcovariate.txt",paste("strPath/estimated_45q15_noshocks_wcovariate_", Sys.Date(), ".txt", sep=""))
