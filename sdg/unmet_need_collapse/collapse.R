#----HEADER----------------------------------------------------------------------------------------------------------------------
# Purpose: Wrapper to launch the custom viz code from ST-GPR central
# source("/homes/username/_code/sdg/unmet_need/collapse.R")
#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  j_root <- "/home/j" 
  h_root <- "/homes/username"
} else { 
  j_root <- "J:"
  h_root <- "H:"
}

# load necessary packages
pacman::p_load(data.table, magrittr)

#settings
me.name <- "unmet_need"
model.id <- 204
#********************************************************************************************************************************
 
#----I/O-------------------------------------------------------------------------------------------------------------------------
# set directories
home.dir <- file.path(j_root, "Project/Coverage/Contraceptives/2015 Contraceptive Prevalence Estimates/gpr_data/input/")
  setwd(home.dir)

model.dir <- file.path(getwd(), me.name, "results")

draws.dir <- file.path("/share/covariates/ubcov/model/output", model.id, "draws_temp")

# load functions
# read in the central visualization function
central.function.lib <- file.path(j_root, "WORK/05_risk/central/code/custom_model_viz/")
  file.path(central.function.lib, "gpr_viz.r") %>% source(chdir=T)
#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source
file.path(central.function.dir, "db_tools.R") %>% source

aggregateResults <- function(model.id) {
  
  command <- paste0("bash /homes/username/_code/sdg/modern_contra/agg.sh ", model.id)
  
  return(command)
  
}
#********************************************************************************************************************************
 
#----POPWEIGHT-------------------------------------------------------------------------------------------------------------------
#begin by running a bash script to append all the results
aggregateResults(model.id) %>% system
draws.data <- file.path(draws.dir, "all.csv") %>% fread

#create some vectors with important varnames
id.vars <- c('location_id', "year_id", 'age_group_id', "sex_id")
draw.colnames <- paste0("draw_", 0:999)

#pull locations to merge on iso3
locations <- get_locations() %>% data.table # use a function written by mortality (modified by me to use epi db) to pull from SQL

#add on location hierarchy to subset to only graph natl
draws.data <- merge(draws.data, locations[, c('location_id', 'location_type'), with=F], by=c('location_id'))
draws.data <- draws.data[location_type=="admin0" | location_id %in% c(4749, 4636, 434, 433)] #only produces nationals and UK countries

#output the draws to J
fwrite(draws.data, file.path(model.dir, model.id, "met_need_collapsed_draws.csv"))
#********************************************************************************************************************************
