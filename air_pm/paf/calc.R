#----HEADER-------------------------------------------------------------------------------------------------------------
# Purpose: Calculate PAFs from air PM for a given country year
#***********************************************************************************************************************

#----CONFIG-------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# disable scientific notation
options(scipen = 999)

# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  
  arg <- commandArgs()[-(1:3)]  # First args are for unix use only
  
  #toggle for targeted run on cluster
  arg <- c("CHN", #location
           "7", #rr data version
           "power2_simsd_source", #rr model version
           "power2", #rr functional form
           "16", #exposure grid version
           11, #output version
           1000, #draws required
           40) #number of cores to provide to parallel functions
  
} else { 
  
  arg <- c("MEX_4650", #location
           "5", #rr data version
           "power2_simsd_source", #rr model version
           "power2", #rr functional form
           "11", #exposure grid version
           5, #output version
           1000, #draws required
           1) #number of cores to provide to parallel functionss
  
} 

# load packages, install if missing
pacman::p_load(data.table, ggplot2, magrittr)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/air_pm/")
setwd(home.dir)

# Set parameters from input args
country <- arg[1]
rr.data.version <- arg[2]
rr.model.version <- arg[3]
rr.functional.form <- arg[4]
exp.grid.version <- arg[5]
output.version <- arg[6]
draws.required <- as.numeric(arg[7])
cores.provided <- as.numeric(arg[8])
  cores.provided <- ifelse(cores.provided>40, 40, cores.provided) #give the bigger jobs (50) some buffer memory

# Memory settings
if (country == "RUS") {
  
  cause.cores <- 10
  year.cores <- 2
  years <- c(1990, 1995, 2000, 2005, 2010, 2013, 2015) #removing unnecessary years, takes too long
  
} else {
  
  years <- c(1990, 1995, 2000, 2005, 2010, 2011, 2012, 2013, 2014, 2015)
  cause.cores <- ifelse(cores.provided>1, cores.provided/length(years), 1)
  year.cores <- ifelse(cores.provided>1, length(years), 1)

}

print(paste0("splitting over #", year.cores, " for each year, and #", cause.cores, " for each age/cause"))

#***********************************************************************************************************************

#----IN/OUT-------------------------------------------------------------------------------------------------------------
##in##
exp.grid.dir <- file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp/gridded", exp.grid.version)
#exp.grid.dir <- file.path(home.dir, 'data/exp/gridded/', exp.grid.version)
rr.dir <- file.path(home.dir, 'data/rr/output/', paste0(rr.data.version, rr.model.version))
tmrel.dir <- file.path(home.dir, 'data/tmrel/')

##out##
out.paf.dir <-  file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/paf", output.version)
out.exp.tmp <-  file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_pm/exp", output.version)
out.exp.dir <- file.path(home.dir, 'products/exp', output.version)

#Exposure
dir.create(file.path(out.exp.dir, "summary"), recursive = T)
dir.create(file.path(out.exp.tmp, "final_draws"), recursive = T)

#PAFs
dir.create(file.path(out.paf.dir, "summary"), recursive = T)
dir.create(file.path(out.paf.dir, "draws"))
#***********************************************************************************************************************  

#----FUNCTIONS----------------------------------------------------------------------------------------------------------  
##function lib##
#PAF functions#
paf.function.dir <- file.path(h_root, '_code/risks/air_pm/paf/_lib')  
file.path(paf.function.dir, "paf_helpers.R") %>% source

#RR functions#
rr.function.dir <- file.path(h_root, '_code/risks/air_pm/rr/_lib') 
file.path(rr.function.dir, "functional_forms.R") %>% source
fobject <- get(rr.functional.form)  

#AiR PM functions#
air.function.dir <- file.path(h_root, '_code/risks/air_pm/_lib')
# this pulls the miscellaneous helper functions for air pollution
file.path(air.function.dir, "misc.R") %>% source()

#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the general misc helper functions
file.path(central.function.dir, "misc.R") %>% source()
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source()
#***********************************************************************************************************************
 
#----PREP DATA----------------------------------------------------------------------------------------------------------  
# Make a list of all cause-age pairs that we have.
age.cause <- ageCauseLister(full.age.range = T) 

#bring in locations
locations <- get_locations() %>% as.data.table()
location.id <- locations[ihme_loc_id == country, location_id]

# Prep gridded exposure dataset
#load the Rdata, bring in an object "exp" with exposure draws
paste0(exp.grid.dir, "/", country, ".Rdata") %>% 
  file.path %>%
  load(envir = globalenv())

# Potential cleanup
exp <- exp[!is.na(pop) & pop > 0, ] # Get rid of grids that have missing/0 pop since they have a weight of 

# Prep the RR curves into a single object, so that we can loop through different years without hitting the files extra times.
all.rr <- lapply(1:nrow(age.cause), prepRR, rr.dir=rr.dir)
#***********************************************************************************************************************

#----CALC and SAVE------------------------------------------------------------------------------------------------------
yearWrapper <- function(this.year,
                        ...) {
  
  #subset exposure
  this.exp <- exp[year==this.year]
  
  message("calculating PAF and saving results for the year ", this.year)

  # Calculate Mortality PAFS using custom function
  out.paf.mort <- mclapply(1:nrow(age.cause), 
                           FUN=calculatePAFs, 
                           exposure.object = this.exp,
                           rr.curves = all.rr,
                           metric.type = "yll", 
                           function.cores = 1,
                           mc.cores = cause.cores)
  
  # Call to a custom function to do some final formatting and generate a lite summary file with mean/CI
  mortality.outputs <- formatAndSummPAF(out.paf.mort, "yll", draws.required)
  
  # Save Mortality PAFs/RRs
  write.csv(mortality.outputs[["summary"]], 
            file.path(out.paf.dir, "summary", 
                      paste0("paf_yll_", location.id, "_", this.year, ".csv")))  
  # write.csv(mortality.outputs[["draws"]], mort.draw.file)
  
  # Calculate Morbidity PAFS using custom function
  out.paf.morb <- mclapply(1:nrow(age.cause), 
                           FUN=calculatePAFs, 
                           exposure.object = this.exp, 
                           rr.curves = all.rr,
                           metric.type = "yld", 
                           function.cores = 1,
                           draws.required,
                           mc.cores = cause.cores)
  
  
  # Call to a custom function to do some final formatting and generate a lite summary file with mean/CI40/
  morbidity.outputs <- formatAndSummPAF(out.paf.morb, "yld", draws.required)
  
  #Save Morbidity PAFs
  write.csv(morbidity.outputs[["summary"]], 
            file.path(out.paf.dir, "summary", 
                      paste0("paf_yld_", location.id, "_", this.year, ".csv")))  
  # write.csv(morbidity.outputs[["draws"]], morb.draw.file)
  
  
  #combine the different pafs and then do prep/formatting for their dalynator run
  out.paf <- rbind(mortality.outputs[["draws"]],
                   morbidity.outputs[["draws"]])
  
  out.paf[, iso3 := country]
  out.paf[, location_id := location.id]
  out.paf[, year_id := this.year] 
  out.paf[, measure_id := 18] 
  out.paf[, risk := "air_pm"]
  out.paf[, acause := cause]
  
  # expand cvd_stroke to include relevant subcauses in order to prep for merge to YLDs, using your custom find/replace function
  # first supply the values you want to find/replace as vectors
  old.causes <- c('cvd_stroke')   
  replacement.causes <- c('cvd_stroke_cerhem', 
                          "cvd_stroke_isch")
  
  # then pass to your custom function
  out.paf <- findAndReplace(out.paf,
                            old.causes,
                            replacement.causes,
                            "acause",
                            "acause",
                            TRUE) #set this option to be true so that rows can be duplicated in the table join (expanding the rows)
  
  # now replace each cause with cause ID
  out.paf[, cause_id := acause] #create the variable
  # first supply the values you want to find/replace as vectors
  cause.codes <- c('cvd_ihd',
                   'cvd_stroke_cerhem', 
                   "cvd_stroke_isch",
                   "lri",
                   'neo_lung',
                   'resp_copd')
  
  cause.ids <- c(493,
                 496,
                 495,
                 322,
                 426,
                 509)
  
  # then pass to your custom function
  out.paf <- findAndReplace(out.paf,
                            cause.codes,
                            cause.ids,
                            "cause_id",
                            "cause_id")
  
  out.paf <- out.paf[, c("risk",
                         'type',
                         "age_group_id",
                         "iso3",
                         "location_id",
                         "year_id",
                         "acause",
                         "cause_id",
                         c(paste0("paf_", 0:(draws.required-1)))),
                     with=F]
  
  for (sex.id in c(1,2)) {
    
    out.paf[, sex_id := sex.id]
    
    write.csv(out.paf[type=="yll"], 
              paste0(out.paf.dir, "/draws/paf_yll_", 
                     location.id, "_", this.year, "_", sex.id, ".csv"))
    
    write.csv(out.paf[type=="yld"], 
              paste0(out.paf.dir, "/draws/paf_yld_", 
                     location.id, "_", this.year, "_", sex.id, ".csv"))
    
  }
  
  gc()

}

# mclapply(years, 
#          yearWrapper,
#          mc.cores = year.cores)
#***********************************************************************************************************************
 
#----EXPOSURE-----------------------------------------------------------------------------------------------------------
##EXPOSURE##
# Save average PM2.5 at the country level
# Prep datasets
out.exp.summary <- as.data.frame(matrix(as.integer(NA), nrow=1, ncol=3))

# calculate population weighted draws
calib.draw.colnames <- c(paste0("draw_",1:draws.required))

out.exp <- exp[,lapply(mget(calib.draw.colnames), weighted.mean, w=pop), by=year]

# calculate mean and CI for summary figures
out.exp[,exp_lower := quantile(.SD ,c(.025)), .SDcols=calib.draw.colnames, by=year]
out.exp[,exp_mean := rowMeans(.SD), .SDcols=calib.draw.colnames, by=year]
out.exp[,exp_upper := quantile(.SD ,c(.975)), .SDcols=calib.draw.colnames, by=year]

#output pop-weighted draws
write.csv(out.exp, paste0(out.exp.tmp, "/final_draws/", country, ".csv"))

#also save version with just summary info (mean/ci)
write.csv(out.exp[, -calib.draw.colnames, with=F], 
          paste0(out.exp.dir, "/summary/", country, ".csv"))
#***********************************************************************************************************************