## Compile sims to make country files

# source("strPath/07c_hivsim_gpr_compile.R")

set.seed(123321)

rm(list=ls())
library(foreign); library(data.table); library(plyr) 

if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"

gpr_dir <- "strPath"

loc <- commandArgs()[3]
sims <- as.numeric(commandArgs()[4])

data <- list()

for (i in 1:sims) {
  if (file.exists(paste0(gpr_dir,"/gpr_",loc,"_sim_not_scaled",i,".txt"))) {
    data[[paste0(i)]] <- read.csv(paste0(gpr_dir,"/gpr_",loc,"_sim_not_scaled",i,".txt"),stringsAsFactors=F) 
    data[[paste0(i)]]$groups <- i
  } else {
    print(paste0("Sim ",i, " not read in"))
  }
}

data <- as.data.frame(rbindlist(data))


## sample down to 1000 draws- 1/14/16 THIS SHOULDN'T HAPPEN ANYMORE, DRAWS SELECTED WITHIN GPR
#   subs <- c()
#   groups <- c()
#   for (i in 1:250) {
#     print(i)
#     subs <- c(subs,sample((0:9)+(i-1)*10,4,replace=F))
#     groups <- c(groups,rep(i,4))
#   }
#   subs <- data.frame(sim=subs,newsim=0:999, groups = groups)
# 
# data <- data[data$sim %in% subs$sim,]

## add new sim numbers
newsim <- read.csv(paste0("strPath/",loc,"_chosen_draws.csv"),stringsAsFactors=F)
newsim$ihme_loc_id <- NULL


stopifnot(length(unique(data$sim))==1000) # If fails, check step 02 to see if regression didn't converge for sim i
data <- merge(data,newsim,by="sim")
stopifnot(length(unique(data$sim))==1000)
stopifnot(length(unique(data$newdraw))==1000)
data$sim <- data$newdraw
data$newdraw <- NULL

## Add HIV Sims and 1st stage with RE
  sim_list <- data.frame(groups=1:250)
  
  append_sims <- function(groups) {
    filepath <- paste0("strPath",groups)
    tryCatch(read.csv(paste0(filepath,".txt"), stringsAsFactors = F), error = function(e) print(paste(groups,"not found")))
  }
  
  hiv_sims <- mdply(sim_list,append_sims, .progress = "text")
  hiv_sims <- unique(hiv_sims[hiv_sims$ihme_loc_id == loc,c("hiv","pred.1.wRE","pred.1.noRE","pred.2.final","groups","sex","year")]) # Subset to columns and remove duplicate years for multiple datapoints

  ## Convert HIV Sims to Mx space
  hiv_sims$pred.1.wRE <- log(1-hiv_sims$pred.1.wRE)/(-45)

data <- merge(data,hiv_sims, by=c("year","groups","sex"))

data <- data[order(data$ihme_loc_id,data$sex,data$year,data$sim),]
stopifnot(length(unique(data$sim))==1000)

## draws file
for (sex in c("male","female")) {
  write.csv(data[data$sex == sex,],paste0(gpr_dir,"/compiled/gpr_",loc,"_",sex,"_sim_not_scaled.txt"),row.names=F)
}


data <- data.table(data)
setkey(data,ihme_loc_id,sex,year)
data <- as.data.frame(data[,list(mort_med = mean(mort),mort_lower = quantile(mort,probs=.025),
                                 mort_upper = quantile(mort,probs=.975),
                                 med_hiv=quantile(hiv,.5),mean_hiv=mean(hiv),
                                 med_stage1=quantile(pred.1.noRE,.5),
                                 med_stage2 =quantile(pred.2.final,.5)
                                 ),by=key(data)])

## summary file
for (sex in c("male","female")) {
  write.csv(data[data$sex == sex,],paste0(gpr_dir,"/compiled/gpr_",loc,"_",sex,"_not_scaled.txt"),row.names=F)  
}



