
#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# load packages, install if missing
pacman::p_load(data.table, magrittr)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/envir_lead_bone/")
setwd(home.dir)

# Run settings
data.version <- 497 #st-gpr data version
model.version <- 126 #st-gpr model version
draws.required <- 1000
cores.provided <- 20

# Analysis settings
years <- c(1990, 1995, 2000, 2005, 2010, 2013, 2015) #gbd 2015 calculation years
sexes <- c(1,2) #male/female
prep.data <- F

###in/out###
##in##
code.dir <- file.path(h_root, '_code/risks/envir_lead_bone/exp')
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
#********************************************************************************************************************************	
 
#----PREP--------------------------------------------------------------------------------------------------------
if (prep.data == TRUE) {
  
  clean.envir <- file.path(home.dir, "data", "clean.Rdata") #this file will be read in by each parallelized run in order to preserve draw covariance
  #objects exported:
  #coeff.draws = draws of the conversion factor to estimate bone lead from CBLI

  #create 1000 draws of the conversion factor
  #currently using the .05 conversion factor from HH paper
  coeff.mean <- 0.05
  coeff.sd <- (0.055-0.046)/(2*1.96)
  coeff.draws <- rnorm(draws.required, mean=coeff.mean, sd=coeff.sd)

  save(coeff.draws,
       file=clean.envir)
  
}
 
#----LAUNCH CALC--------------------------------------------------------------------------------------------------------
 
#********************************************************************************************************************************	
# Get the list of most detailed GBD locations
location_id.list <- get_locations() %>% data.table # use a function written by mortality (modified by me to use epi db) to pull from SQL
locations <- unique(location_id.list[location_id!=6, location_id])

#Launch the jobs to calculate exposure

  launchModel <- function(location) {
    
    sexWrapper <- function(sex) {
    
      yearWrapper <- function(year) {
    
      	# Launch jobs
      	jname <- paste0("calc_exp_v", output.version, "_loc", location, "y", year, "s", sex )
      	sys.sub <- paste0("qsub ", project, sge.output.dir, " -N ", jname, " -pe multi_slot ", cores.provided*2, " -l mem_free=", cores.provided*4, "G")
      	args <- paste(location,
                      sex,
      	              year,
      	              data.version,
      	              model.version,
      	              output.version,
      	              draws.required,
      	              cores.provided)
      	system(paste(sys.sub, r.shell, calc.script, args))
      	
      }
      
      lapply(years, yearWrapper)

    }
    
    lapply(sexes, sexWrapper)
    
  }  

  lapply(locations, launchModel)

#********************************************************************************************************************************

