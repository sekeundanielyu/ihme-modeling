#----HEADER----------------------------------------------------------------------------------------------------------------------
# Purpose: Launch the parallelized calculation of ozone exp/RR/PAF for GBD2015
#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())
	
	# System settings
  cores.provided <- 20 #number of cores to request (this number x2 in order to request slots, which are a measure of computational time that roughly equal 1/2core)
	rshell <- paste0(h_root, "/_code/_lib/shells/rshell.sh")
	prep.script <- paste0(h_root, "/_code/risks/air_ozone/paf/01_load.R")
	rscript <- paste0(h_root, "/_code/risks/air_ozone/paf/02_calculate.R")
	
	# Job settings.
	exp.grid.version <- "1" #first grid version created with all subnationals and AROC forecasting strategy
	draws.required <- 1000 #number of draws to create to show distribution, default is 1000 - do less for a faster run
	prep.environment <- TRUE
	
	# load packages, install if missing
	pacman::p_load(data.table, magrittr)
	
	# function library
	# this pulls the current locations list
	source(paste0(h_root, "_code/_lib/functions/get_locations.R")) 
	
	# Get the list of most detailed GBD locations
	location_id.list <- get_locations() %>% data.table() # use a function written by mortality (modified by me to use epi db) to pull from SQL
	  countries <- unique(location_id.list$ihme_loc_id)
	  countries <- c(countries,
	                 "BRA",
	                 "CHN", 
	                 "GBR",
	                 "IND",
	                 "JPN",
	                 "KEN",
	                 "MEX",
	                 "SAU",
	                 "SWE",
	                 "USA",
	                 "ZAF",
	                 "GLOBAL") # quick fix for adding aggregate nationals/global
#********************************************************************************************************************************	
   
#----PREP------------------------------------------------------------------------------------------------------------------------   
# Prep save directories
out.paf.dir <- file.path(j_root, "WORK/05_risk/risks/air_ozone/products/pafs", output.version) 
out.exp.dir <- file.path(j_root, "WORK/05_risk/risks/air_ozone/products/exp", output.version)   
out.tmp <- file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_ozone/paf", output.version) 
directory.list <- c(out.paf.dir, out.tmp, out.exp.dir)

# Prep directories
for (directory in directory.list) {
  
  dir.create(paste0(directory, "/draws"), recursive = TRUE)
  dir.create(paste0(directory, "/summary"), recursive = TRUE)
  
}

#********************************************************************************************************************************

#----LAUNCH LOAD-----------------------------------------------------------------------------------------------------------------
# Launch job to prep the clean environment if necessary
if (prep.environment != FALSE) {
  
  # Launch job
  jname <- paste0("load_clean_environment")
  sys.sub <- paste0("qsub ", project, sge.output.dir, "-N ", jname, " -pe multi_slot ", 2*cores.provided, " -l mem_free=", 4*cores.provided, "G")
  args <- paste(draws.required)
  
  system(paste(sys.sub, rshell, prep.script, args))
  
  # Prep hold structure
  hold.text <- paste0(" -hold_jid ", jname)
  
} else {
  
  hold.text <- ""
  
}
#********************************************************************************************************************************
 
#----LAUNCH CALC-----------------------------------------------------------------------------------------------------------------
#Launch the jobs to calculate ozone PAFs and exp
	for (country in countries) {
    
		# Launch jobs
		jname <- paste0("air_ozone_paf_", country, "_", output.version)
		sys.sub <- paste0("qsub ", project, sge.output.dir, " -N ", jname, " -pe multi_slot ", 2*cores.provided, " -l mem_free=", 4*cores.provided, "G", hold.text)
		args <- paste(country,
		              exp.grid.version,
		              output.version,
		              draws.required,
                  cores.provided)
		
		system(paste(sys.sub, rshell, rscript, args))	

	}

#********************************************************************************************************************************

