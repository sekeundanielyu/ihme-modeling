################################################################################
## Description: Compile results of all holdouts and select parameters
################################################################################

# source("strPath/06b_combine_selected_parameters.R")


rm(list=ls())
library(foreign); library(data.table); library(arm)

if (Sys.info()[1] == "Linux") root <- "/home/j" else root <- "J:"

in_dir <- "strPath"
user <- Sys.getenv("USER") # Default for linux user grab. "USERNAME" for Windows
code_dir <- paste0("strPath")

setwd(paste(root, "strPath", sep=""))

gen_new <- 1


## define loss function
## Note: This loss function minimizes loss up to 95%, and then starts adding "loss" (decreasing selection probability) for coverage that exceeds 95%
# loss_function <- function(are, coverage) loss = ifelse(coverage <= 0.95, are + ((1-coverage)-0.05)/5, are + (0.05 - (1-coverage))/1)
loss_function <- function(are, coverage) loss = are + abs(.95-coverage)/5

# bring in means
loss_files <- list.files(paste0(in_dir, "/means"), full.names=T)
# get rid of empty files (locations with no data)
info = file.info(loss_files)
loss_files = rownames(info[info$size > 0, ])

loss <- lapply(loss_files, read.csv, stringsAsFactors=F)
loss <- do.call(rbind, loss)
loss$X <- NULL

# # exclude small lambda values for countries with small pops
# pop20mill <- read.csv(paste0(root, "strPath/pop_over_20_million.csv"), stringsAsFactors=F)
# large_pops <- unique(pop20mill$ihme_loc_id)
# loss <- loss[(loss$type %in% large_pops) | (!(loss$type %in% large_pops) &  loss$lambda > .5),]
 loss <- data.table(loss)

## collapse means across type
setkey(loss, type,scale,amp2x, lambda, zeta)
loss <- loss[,list(are = mean(are), coverage = mean(coverage)),by=key(loss)]


# run the loss function
loss$loss <- loss_function(loss$are,loss$coverage)


# Find best combination for each data type
setkey(loss,type)
loss <- loss[,min:=min(loss),by=key(loss)]
loss$best <- as.numeric(loss$loss == loss$min)
loss$min <- NULL
min <- as.data.frame(loss)

# bring in countries
countries <- as.data.frame(read.csv("strPath/first_stage_results1.csv"))
countries <- unique(countries[,c("ihme_loc_id","sex","type")])#temp
countries$iso3_sex <- paste(countries$ihme_loc_id,countries$sex,sep = "_")
countries <- data.table(countries)
setkey(countries,iso3_sex)

## get rid of no data countries if they have loss files 
min <- min[min$type != "no data",]

## select parameters for no data countries as the highest parameters selected elsewhere (except for zeta, which is max)
min <- rbind(min, data.frame(scale = max(min$scale[min$best==1]),
                             amp2x =  max(min$amp2x[min$best==1]),
                             zeta = min(min$zeta[min$best==1]),
                             lambda = max(min$lambda[min$best==1]),
                             are = NA,
                             coverage = NA, 
                             loss = NA, 
                             best = 1, 
                             type = "no data")) 

## Ensure a square dataset: Each type that is output in prediction_model_results should have a square dataset
## All should have an obs for each scale and amp except for "no data", which should have one observation
amps <- unique(min$amp2x[!is.na(min$amp2x)])
scales <- unique(min$scale)  
types <- unique(countries$type)
zetas <- unique(min$zeta)
lambdas <- unique(min$lambda)

target_length <- length(amps) * length(scales) * length(zetas)*length(lambdas)*(length(types)-1) + 1 

# this test won't work because not all lambdas are tested for all countries

#   if(nrow(min) != target_length) {
#     print("The data types that are missing parameter results are:")
#     print(as.character(unique(countries$type)[!(unique(countries$type) %in% unique(min$type))]))
#     stop(paste0("We have ",nrow(min)," rows, and expect ",target_length))
#   }

## save
write.csv(min, file="strPath/selected_parameters.txt", row.names=F)
write.csv(min, file=paste("strPath/selected_parameters", Sys.Date(), ".txt", sep=""), row.names=F)
