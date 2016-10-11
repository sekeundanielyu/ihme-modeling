#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  arg <- commandArgs()[-(1:3)]  # First args are for unix use only
  arg <- c("CHN", 1, 5, 1000, 20) # toggle for targeted run to debug
} else { 
  arg <- c("AND", 1, 4, 50, 20)
}

# Set parameters
country <- arg[1]
exp.grid.version <- arg[2]
output.version <- arg[3]
draws.required <- as.numeric(arg[4])
cores.provided <- as.numeric(arg[5])
years <- c(1990, 1995, 2000, 2005, 2010, 2013, 2015)

# load packages, install if missing
pacman::p_load(data.table, ggplot2, grid, parallel, magrittr, RColorBrewer, reshape2)

# function library
functions.dir <- file.path(h_root, "_code/_lib/functions")
# this pulls the current locations list
file.path(functions.dir, "get_locations.R") %>% source()

# Define important directories/information in objects
# IN
# clean environment with RR and TMRED draws
file.path(j_root, "WORK/05_risk/risks/air_ozone/data/clean.Rdata") %>% load(envir = globalenv())

#files
#gridded exposure dataset for this country
exp.dir <- file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_ozone/exp/gridded", exp.grid.version)
exp <- file.path(exp.dir, paste0(country, ".csv")) %>% fread


# OUT
#directories
out.paf.dir <- file.path(j_root, "WORK/05_risk/risks/air_ozone/products/pafs", output.version) 
out.exp.dir <- file.path(j_root, "WORK/05_risk/risks/air_ozone/products/exp", output.version)   
out.tmp <- file.path("/share/gbd/WORK/05_risk/02_models/02_results/air_ozone/paf", output.version) 
#********************************************************************************************************************************

#----PREP---------------------------------------------------------------------------------------------------------------------
#bring in locations
locations <- get_locations() %>% as.data.table()
location.id <- locations[ihme_loc_id == country, location_id]

# Prep gridded exposure dataset
setkeyv(exp, c('x', 'y', 'year')) #make sure there are no duplicate grids
exp <- unique(exp)
exp <- exp[!is.na(exp$pop) & !is.na(exp$fus) & !is.infinite(exp$fus) & !is.infinite(exp$pop), ] # Get rid of missings and infinites
exp[exp$pop <= 0, "pop"] <- 0.1 # set population values of 0 or smaller to be 0.1 
exp[exp$fus <= 0, "o3"] <- 0.1 # Set ozone values of 0 or smaller to be 0.1 (This will have a PAF of 0, so we don't wnat to drop.)

yearWrapper <- function(this.year) {
  
  message("Working on the year ", this.year)
  
#subset to year, then generate SD based on previous assumption of 0.06
this.exp <- exp[year==this.year,]
this.exp[, sd := 0.06*o3/1.96]

#generate draws of exposure using sd and mean
ozone.draw.colnames <- paste0("ozone_",1: draws.required)

#sample draws of the ozone exposure using your predefined SD
#note that we need to do this by row because of restrictions on what the rnorm function can take as input/output
this.exp[, c(ozone.draw.colnames) := rnorm(draws.required, o3, sd) %>% as.list, by=list(rownames(this.exp))]
#********************************************************************************************************************************
 
#----CALC PAFS-------------------------------------------------------------------------------------------------------------------
# generate RR using draws of ozone, RR, and TMRED with formula rr = base.RR ^ ((exp-tmred)/10) because rr is in terms of 10 ppb ozone
RR <- lapply(1:draws.required, 
             function(draw.number) 
               ifelse(this.exp[, ozone.draw.colnames[draw.number], with=FALSE] > tmred[draw.number,], 
                      rr.draws[draw.number]^((this.exp[, ozone.draw.colnames[draw.number], with=FALSE]-tmred[draw.number,])/10),
                      1)) # if exposure <= TMRED, there is no elevated risk 

# new aggregation formula created to address the issue that population at the grid level 
# doesn't necessarily reflect the number of cases at a grid level
out.paf <- lapply(1:draws.required, 
                  function(draw.number) 
                    (sum((RR[[draw.number]] - 1)*this.exp[,pop]) / sum(RR[[draw.number]]*this.exp[,pop]))) %>% as.data.table
#********************************************************************************************************************************
 
#----FORMAT/SAVE-----------------------------------------------------------------------------------------------------------------
# Set up variables
# Currently we only estimate one cause/age group for ozone
out.paf[, acause := "resp_copd"]
out.paf[, cause_id := 509]
out.paf[, age_group_id := 99]
out.paf[, iso3 := country]
out.paf[, location_id := location.id]
out.paf[, year_id := this.year] 
out.paf[, measure_id := 18] 
out.paf[, risk := "air_pm"]

paf.draw.colnames <- c(paste0("paf_", 0:(draws.required-1)))
setnames(out.paf, paste0("V", 1:draws.required), paf.draw.colnames)

# generate mean and CI for summary figures
out.paf[,paf_lower := quantile(.SD ,c(.025)), .SDcols=paf.draw.colnames, by=list(cause_id,age_group_id)]
out.paf[,paf_mean := rowMeans(.SD), .SDcols=paf.draw.colnames, by=list(cause_id,age_group_id)]
out.paf[,paf_upper := quantile(.SD ,c(.975)), .SDcols=paf.draw.colnames, by=list(cause_id,age_group_id)]

#Order columns to your liking
out.paf <- setcolorder(out.paf, c("iso3", "location_id", "measure_id", "risk", "acause", "cause_id", "age_group_id", "year_id", "paf_lower", "paf_mean", "paf_upper", paf.draw.colnames))

# Save summary version of PAF output for experts 
out.paf.summary <- out.paf[, c("age_group_id","acause","paf_lower","paf_mean","paf_upper")  , with=F]
write.csv(out.paf.summary, paste0(out.paf.dir, "/summary/paf_yll_", country, "_", this.year,  ".csv"))

# Convert from age 99 to the correct ages
# LRI is between 0 and 5
for (cause.code in c("resp_copd")) {
  # Take out this cause
  temp.paf <- out.paf[out.paf$acause == cause.code, ]
  out.paf <- out.paf[!out.paf$acause == cause.code, ]    
  
  # Add back in with proper ages (need to use age.id instead of age number)
  if (cause.code %in% c("resp_copd")) ages <- seq(10,21) # resp_copd are between 25 and 80
  
  for (age.code in ages) {
    temp.paf$age_group_id <- age.code
    out.paf <- rbind(out.paf, temp.paf)
  }
}

# Save Mortality PAFs
for (type in c("yll","yld")) {
  for (sex in c(1, 2)) {
    
    write.csv(out.paf, paste0(out.tmp, "/draws/paf_yll_", location.id, "_", this.year, "_", sex, ".csv"))
    
    #save kiribati as american samoa (PAF=0, don't have ozone data, assume kiribati paf as 0 as well, closest island=american samoa)
    if (location.id == 298) {write.csv(out.paf, paste0(out.tmp, "/draws/paf_yll_23_", this.year, "_", sex, ".csv"))}
    
  }
} 
#********************************************************************************************************************************
 
#----EXPOSURE--------------------------------------------------------------------------------------------------------------------
# Save average ozone at the country level
# Prep datasets
out.exp <- rep(NA, draws.required)
out.exp.summary <- as.data.frame(matrix(as.integer(NA), nrow=1, ncol=3))

# calculate population weighted draws of exposure
out.exp <- sapply(1:draws.required, 
                  function(draw.number) 
                    weighted.mean(this.exp[[ozone.draw.colnames[draw.number]]], 
                                  this.exp[,pop]))

# calculate mean and CI for summary figures
out.exp.summary[,1] <- quantile(out.exp, .025)
out.exp.summary[,2] <- mean(out.exp)
out.exp.summary[,3] <- quantile(out.exp, .975)
names(out.exp.summary) <- c("exposure_lower","exposure_mean","exposure_upper")

write.csv(out.exp.summary, paste0(out.exp.dir, "/summary/exp_", country, "_", this.year, ".csv"))
write.csv(out.exp, paste0(out.tmp, "/exp_", country, "_", this.year, ".csv"))

}
#********************************************************************************************************************************

mclapply(years, yearWrapper, mc.cores=cores.provided)
