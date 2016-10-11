#----HEADER----------------------------------------------------------------------------------------------------------------------
# Purpose: Launch the parallelized calculation of IER curve fitting for GBD2015
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
cores.provided <- 12 #number of cores to request (this number x2 in ordert o request slots, which are a measure of computational time that roughly equal 1/2core)
draws.required <- 1000 #number of draws to create to show distribution, default is 1000 - do less for a faster run
prep.environment <- FALSE #toggle to launch prep code and compile the IER data
age.cause.full <- TRUE #toggle to calculate all age cause combinations, FALSE runs the lite version for testing
models <- c("power2_simsd_source") #power2 function with a source-specific heterogeneity parameter

###in/out###
##in##
code.dir <- file.path(h_root, '_code/risks/air_pm/rr')
  prep.script <- file.path(code.dir, "prep.R")
  model.script <- file.path(code.dir, "fit.R")
r.shell <- file.path(h_root, "_code/_lib/shells/rshell.sh")

# version history
version <- 7 #updated SHS exposure db, updated age_median for stroke/ihd, updated some incorrect data, dropped incidence
#version <- 6 # updated sourcing so NIDs should never be missing
#version <- 5 # outliered some incorrect data points, fixed misextracted ages, and now modifying SD with age age extrap
#version <- 4 # using the model to fit TMREL, so don't define TMREL, and define conc_den as very small if not extracted
#version <- 3 # using average SD for all to see how model follows data generally
#version <- 2 # using the new TMREL and new data
#version <- 1 # using the old TMREL and new data
#********************************************************************************************************************************	
 
#----LAUNCH LOAD-----------------------------------------------------------------------------------------------------------------
# Launch job to prep the clean environment if necessary
if (prep.environment != FALSE) {
  
  # Launch job
  jname.arg <- paste0("_N prep_data_v", version)
  slot.arg <- paste0("-pe multi_slot ", cores.provided/4)
  mem.arg <- paste0("-l mem_free=", cores.provided/2, "G")
  sys.sub <- paste("qsub", project, sge.output.dir, jname.arg, slot.arg, mem.arg)
  args <- paste(version,
                draws.required)
  
  system(paste(sys.sub, r.shell, prep.script, args))
  
  # Prep hold structure
  hold.text <- paste0(" -hold_jid ", jname)
  
} else {
  
  hold.text <- ""
  
}
#********************************************************************************************************************************
 
#----LAUNCH CALC-----------------------------------------------------------------------------------------------------------------
#Launch the jobs to fit IER curves
launchModel <- function(model) {
  
  message("launching IER calculation using ", model)
  
	# Launch jobs
	jname <- paste0("fit_ier_v", version, "_m", model)
	sys.sub <- paste0("qsub ", project, sge.output.dir, " -N ", jname, " -pe multi_slot ", cores.provided*2, " -l mem_free=", cores.provided*4, "G", hold.text)
	args <- paste(model,
	              version,
	              cores.provided,
	              draws.required,
	              age.cause.full)
	
	system(paste(sys.sub, r.shell, model.script, args))
	
}

lapply(models, launchModel)
#*******************************************************************************************************************************