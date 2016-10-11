#----HEADER----------------------------------------------------------------------------------------------------------------------
# Project: RF: air_pm/air_ozone
# Purpose: Take the global gridded shapefile and cut it up into different countries/subnationals using shapefiles
# This is an update of source("J:/WORK/05_risk/01_database/02_data/air_pm/01_exp/02_nonlit/01_code/gridded_dataset/01_assign_location_ids.r")
# source("/homes/jfrostad/_code/risks/air_pm/exp/1_master.R", echo=T)
# TODO: major wish list for this function is to add ability to produce agg national files for the subnats 
# right now i am just combining all the subnats and calling it national
# (avg exposure at this level often requested)
#********************************************************************************************************************************
 
#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# disable scientific notation
options(scipen = 999)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/air_pm/")
  setwd(home.dir)

# load packages, install if missing
pacman::p_load(data.table, ggplot2, parallel, magrittr, maptools, raster, rgdal, rgeos, sp, splines)

# set options
draw.method <- "normal_space" #how to generate draws? (either log_space or normal_space)
run.assign <- FALSE #toggle to run the prep step that assigns location_ids to each grid using shapefile
max.cores <- 50 # on big jobs i can ask for 100 slots, rule of thumb is 2 slots per core
draws.required <- 1000
#********************************************************************************************************************************
 
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

# this bash script will append all csvs to create a global file, then create national files for each subnational country
#aggregateResults <- paste0("bash ", file.path(h_root, "_code/risks/air_pm/exp/01b_aggregate_results.sh")) 
#*********************************************************************************************************************** 
  
#********************************************************************************************************************************
   
#----IN/OUT----------------------------------------------------------------------------------------------------------------------
# Set directories and load files
###Input###
code.dir <- file.path(h_root, '_code/risks/air_pm/exp')
  assign.script <- file.path(code.dir, "2_assign.R")
  save.script <- file.path(code.dir, "3_save_draws.R")
r.shell <- file.path(h_root, "_code/_lib/shells/rshell.sh")

# Get the list of most detailed GBD locations
location_id.list <- get_locations() %>% data.table # use a function written by mortality (modified by me to use epi db) to pull from SQL

###Output### 	
# where to output the split gridded files
out.dir <-  file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp/gridded", grid.version)
  dir.create(file.path(out.dir, "summary"), recursive=T, showWarnings=F)
# file that will be created if running the assign codeblock
assign.output <- file.path(out.dir, "all_grids.Rdata")
#********************************************************************************************************************************
 
#----RUN ASSIGN------------------------------------------------------------------------------------------------------------------
#if necessary, run the assign code to prep the gridded pollution Rdata file
if (run.assign==TRUE) {
  
  source(assign.script)
  
} else load(assign.output)
#********************************************************************************************************************************
 
#----LAUNCH SAVE-----------------------------------------------------------------------------------------------------------------
#Launch the jobs to TODO

#create vector of all the different countries in the pollution file
countries <- unique(pollution$ihme_loc_id) %>% sort
countries <- c(countries, "GLOBAL") #add on a global file

launchCountry <- function(country) {

  #set the number of cores to provide based on the number of grids in the country (object size)
  
  grid.size <- pollution[ihme_loc_id==country] %>% object.size
  
  if (grid.size > 5e7) { 
    cores.provided <- max.cores #give 50 cores and 200gb of mem to any files larger than 50mb
  } else if(grid.size > 15e6) {
    cores.provided <- 40 #give 40 cores and 160gb of mem to any files larger than 15mb
  } else if(grid.size > 25e4) {
    cores.provided <- 20 #give 20 cores and 80gb of mem to any files larger than .25mb
  } else cores.provided <- 10 #give 10 cores and 40gb of mem to any files less than .25 mb
  
  
  message("launching PAF calc for loc ", country, "\n --using ", cores.provided*2, " slots and ", cores.provided*4, "GB of mem")
  
  # Launch jobs
  args <- paste(country,
                draw.method,
                grid.version,
                draws.required,
                cores.provided)  
    
  jname.arg <- paste0("-N ", country, "_exp_draws_v", grid.version)
  mem.arg <- paste0("-l mem_free=", cores.provided*4, "G")
  slot.arg <- paste0("-pe multi_slot ", cores.provided*2)
  sys.sub <- paste("qsub", project, sge.output.dir, jname.arg, mem.arg, slot.arg)  
  
  paste(sys.sub, r.shell, save.script, args) %>% system

}

lapply(countries, launchCountry)
#********************************************************************************************************************************

