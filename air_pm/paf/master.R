#----HEADER----------------------------------------------------------------------------------------------------------------------
# Purpose: Launch the parallelized calculation of PAF calculation for air PM for GBD2015
#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# load packages, install if missing
pacman::p_load(data.table, magrittr)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/air_pm/")
setwd(home.dir)

# Settings
rr.data.version <- 7
rr.model.version <- "power2_simsd_source"
rr.functional.form <- "power2"
exp.grid.version <- 16
draws.required <- 1000

###in/out###
##in##
code.dir <- file.path(h_root, '_code/risks/air_pm/paf')
  calc.script <- file.path(code.dir, "calc.R")
r.shell <- file.path(h_root, "_code/_lib/shells/rshell.sh")

#********************************************************************************************************************************	

#----FUNCTIONS----------------------------------------------------------------------------------------------------------  
##function lib##
#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the general misc helper functions
file.path(central.function.dir, "misc.R") %>% source()
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source()
#----LAUNCH CALC--------------------------------------------------------------------------------------------------------
 
#********************************************************************************************************************************	
# Get the list of most detailed GBD locations
location_id.list <- get_locations() %>% data.table # use a function written by mortality (modified by me to use epi db) to pull from SQL
locations <- unique(location_id.list[location_id!=6, ihme_loc_id]) %>% sort

  launchModel <- function(country) {
    
    #define the number of cores to be provided to a given job by the size of the country gridded file
    #larger countries are going to be more memory intensive
    
    #currently using ifelse to launch with low cores if exp file doesnt exist (will break anyways)
    grid.size <- ifelse(file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp/gridded", exp.grid.version, paste0(country, ".csv")) %>% file.exists,
                        file.info(file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp/gridded", exp.grid.version, paste0(country, ".csv")))$size,
                        1)

    if (grid.size > 1e9) { 
      cores.provided <- 50 #give 50 cores and 200gb of mem to any files larger than 1gb
    } else if(grid.size > 25e6) {
      cores.provided <- 40 #give 40 cores and 160gb of mem to any files larger than 25mb
    } else if(grid.size > 25e5) {
      cores.provided <- 20 #give 20 cores and 80gb of mem to any files larger than 2.5mb
    } else cores.provided <- 10 #give 10 cores and 40gb of mem to any files less than 2.5mb
    
    
    message("launching PAF calc for loc ", country, "\n --using ", cores.provided*2, " slots and ", cores.provided*4, "GB of mem")

    	# Launch jobs
    	jname <- paste0("calc_paf_v", output.version, "_loc_", country)
    	sys.sub <- paste0("qsub ", project, sge.output.dir, " -N ", jname, " -pe multi_slot ", cores.provided*2, " -l mem_free=", cores.provided*4, "G")
    	args <- paste(country,
                    rr.data.version,
    	              rr.model.version,
    	              rr.functional.form,
    	              exp.grid.version,
    	              output.version,
    	              draws.required,
    	              cores.provided)
    	
    	system(paste(sys.sub, r.shell, calc.script, args))

  }

  lapply(locations, launchModel)

#********************************************************************************************************************************

