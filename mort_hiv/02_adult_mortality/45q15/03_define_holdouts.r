################################################################################
## Description: Defines holdouts for each region
################################################################################
# source("strPath/03_define_holdouts.r")

  rm(list=ls())

  if (Sys.info()[1] == "Linux") root <- "/home/j" else root <- "J:"
  setwd(paste(root, "strPath/prediction_model", sep=""))

  num.holdouts <- as.numeric(commandArgs()[3])

  set.seed(234890)

## load data; identify each row; make an indicator for whether or not data is knocked out
  data <- read.csv(file="first_stage_results.csv", header=T, stringsAsFactors=F)
  data <- data[,names(data)[!grepl("pred.2", names(data))]]

  
## loop through regions & holdouts 
  setwd("strPath")
  set.seed(25)
  for (rr in sort(unique(data$region_name))) {
    cat(paste("\n", rr, "\n  ", sep="")); flush.console()
    region.data <- data[data$region_name == rr,]
    ho <- matrix(0, nrow=nrow(region.data), ncol=num.holdouts)
    for (hh in 1:num.holdouts) { 
      cat(paste(hh, if (hh%%10==0) "\n   " else " ", sep="")); flush.console()
      
## select block length to drop most recent data
      max <- max(region.data$year)
      length <- sample(10:20, 1)
      knockout <- (region.data$year >= (max - length) & region.data$data == 1) 
      ho[knockout,hh] <- 1
      
## select random blocks to drop 
      for (ii in 1:length(unique(region.data$ihme_loc_id))) { 
        country <- sample(unique(region.data$ihme_loc_id),1)
        length <- sample(5:10,1)
        mid <- sample(1950:2015,1)+0.5
        knockout <- (region.data$year >= (mid - length) & region.data$year <= (mid + length) & region.data$ihme_loc_id == country & region.data$data == 1)
        ho[knockout,hh] <- 1
      } 
    } 
## save knocked-out & region-specific data file
    colnames(ho) <- paste("ho", 1:num.holdouts, sep="")
    save <- cbind(region.data, ho)
    write.csv(save, file=paste("input_", rr, ".txt", sep=""), row.names=F)    
  } 

