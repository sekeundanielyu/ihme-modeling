#----HEADER----------------------------------------------------------------------------------------------------------------------
# Project: RF: air_pm
# Purpose: Take the global gridded shapefile and cut it up into different countries/subnationals using shapefiles
#********************************************************************************************************************************
 
#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())
  
# disable scientific notation
options(scipen = 999)
  
# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  
  arg <- commandArgs()[-(1:3)]# First args are for unix use only
  arg <- c("GLOBAL", "log_space", "16", 500, 50) #toggle targetted run
  
  
} else { 
  
  j_root <- "J:"
  h_root <- "H:"
  arg <- c("PNG", "log_space", "16", 100, 10)
  
}

#set the seed to ensure reproducibility and preserve covariance across parallelized countries
set.seed(42) #the answer of course

#set parameters based on arguments from master
this.country <- arg[1]
draw.method <- arg[2]
grid.version <- arg[3]
draws.required <- as.numeric(arg[4])
cores.provided <- as.numeric(arg[5])

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/air_pm/")
  setwd(home.dir)

# load packages, install if missing
pacman::p_load(data.table, ggplot2, parallel, magrittr, matrixStats)
  
#----FUNCTIONS----------------------------------------------------------------------------------------------------------  
##function lib##
#Air EXP functions#
exp.function.dir <- file.path(h_root, '_code/risks/air_pm/exp/_lib')  
file.path(exp.function.dir, "assign_tools.R") %>% source  

#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the general misc helper functions
file.path(central.function.dir, "misc.R") %>% source
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source
#********************************************************************************************************************************
   
#----IN/OUT----------------------------------------------------------------------------------------------------------------------
# Set directories and load files
# Get the list of most detailed GBD locations
location_id.list <- data.table(get_locations()) # use a function written by mortality (modified by me to use epi db) to pull from SQL

# where to output the split gridded files
out.dir <-  file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp/gridded", grid.version)

# file that will be created by the previous assign codeblock
assign.output <- file.path(out.dir, "all_grids.Rdata") %>% 
  load(envir = globalenv())
#********************************************************************************************************************************
 
#----DRAW---->SAVE---------------------------------------------------------------------------------------------------------------	
#subset pollution file to current country (unless producing global gridded file)
if (this.country!="GLOBAL") pollution <- pollution[ihme_loc_id==this.country]
# generate 1000 draws by grid and then save a csv of this country
setkeyv(pollution, c("long", "lat"))

# create a list of draw names based on the required number of draws for this run
draw.colnames <- c(paste0("draw_", 1:draws.required))

# add index
pollution[, index := seq_len(.N)]

#divide into a list where each piece is a chunk of the dt (#cores x ~equal pieces in total)
chunks <- split(pollution, as.numeric(as.factor(pollution$index)) %% (cores.provided*10))

#break DT into 1000 grid chunks in order to parallelize this calculation
chunkWrapper <- function(name,
                         this.chunk,
                         transformation=draw.method,
                         test.toggle=FALSE, #toggle to create mean/CI to test the draws have been done correctly
                         ...) {
  
  message(name)
  
  if (transformation == "log_space") {
    
    #create draws of exposure based on provided uncertainty
    #may need to make changes to this step to take into account spatial covariance
    #note changed this step on 06132016 in response to 05272016 email that the modelling is done in log and therefore draws
    #must be created in log and then exponeniated
    this.chunk[, draw.colnames := rnorm(draws.required, mean=log(median), sd=(log(upper)-log(lower))/3.92) %>% 
                 exp %>% 
                 as.list, 
               by="index", with=F]
    
  } else if (transformation == "normal_space") {
    
    this.chunk[, draw.colnames := rnorm(draws.required, mean=median, sd=(upper-lower)/3.92) %>% 
                 as.list, 
               by="index", with=F]
    
  }
  
  if (test.toggle == TRUE) {
    
    #test work
    this.chunk[, "lower_calc" := quantile(.SD, c(.025)), .SDcols=draw.colnames, by="index"]
    this.chunk[, "mean_calc" := rowMeans(.SD), .SDcols=draw.colnames, by="index"]
    this.chunk[, "median_calc" := as.matrix(.SD) %>% rowMedians, .SDcols=draw.colnames, by="index"]
    this.chunk[, "upper_calc" := quantile(.SD, c(.975)), .SDcols=draw.colnames, by="index"]
    
    this.chunk[, "diff_lower" := lower - lower_calc]  
    this.chunk[, "diff_median" := median - median_calc]  
    this.chunk[, "diff_upper" := upper - upper_calc]  
    
  }
  
  return(this.chunk)
  
}

exp <- mcmapply(chunkWrapper, names(chunks), chunks, mc.cores=(cores.provided), SIMPLIFY=FALSE) %>% rbindlist

# #create a summary table for diagnostics
# summary.table <- sapply(exp[, c("diff_lower", "diff_median", "diff_upper"), with=F], summary) %>% as.data.table(keep.rownames=T)
# summary.table[, iso3 := this.country]
# summary.table[, draw_method := draw.method]
# 
# #write this table
# write.csv(summary.table, 
#           file.path(out.dir, "summary", paste0(this.country, ".csv")), 
#           row.names=F)

#output each country to feed into PAF calculation in parallel
save(exp,
     file=file.path(out.dir, paste0(this.country, ".Rdata")))
#********************************************************************************************************************************
