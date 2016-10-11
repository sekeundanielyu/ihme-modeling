#----CONFIG-------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# disable scientific notation
options(scipen = 999)

# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  
  arg <- commandArgs()[-(1:3)]  # First args are for unix use only
  
#   #toggle for targetted run on the cluster
#   arg <- c(44552, #location
#            2, #sex
#            2010, #current year
#            497, #st-gpr data version
#            126, #st-gpr model version
#            1, #output version
#            100, #draws required
#            1) #number of cores to provide to parallel functions
  
} else { 
  
  arg <- c(101, #location
           1, #sex
           2010, #current year
           497, #st-gpr data version
           126, #st-gpr model version
           1, #output version
           100, #draws required
           1) #number of cores to provide to parallel functions
  
} 

# load packages, install if missing
pacman::p_load(data.table, flux, ggplot2, magrittr, parallel, plyr)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/envir_lead_bone/")
setwd(home.dir)

# Set parameters from input args
this.location <- arg[1]
this.sex <- arg[2]
current.year <- as.numeric(arg[3])
data.version <- arg[4]
model.version <- arg[5]
output.version <- arg[6]
draws.required <- as.numeric(arg[7])
cores.provided <- as.numeric(arg[8])

#other settings
age.cores <- 4 #number of ages to run simultaneously (all other cores are divided by this to keep from death)
bone.ages <- c(10:21) # bone lead is only a relevant exposure to age 25+ (its a long term cardiovascular outcome)
apex.year <- 1970 #no longer really used as apex.year, its just as far back as we can estimate via st-gpr
nadir.year <- 1920 #assumed to be where lead was always steadily at 2.0 ug/dL (pre-industrial time)
nadir.value <- 2.0 #see above
years <- seq(apex.year, current.year) #years produced by st-gpr for blood lead (up to the year we are estimating now)

draw.colnames <- paste0("draw_", 0:(draws.required-1))
#***********************************************************************************************************************

#----IN/OUT-------------------------------------------------------------------------------------------------------------
##in##
age.map <- file.path(j_root, "WORK/05_risk/central/documentation/age_mapping.csv") %>% fread
data.dir <- file.path(home.dir, "data")
exp.parent <- "/share/covariates/ubcov/04_model/envir_lead_blood/_models/"
exp.dir <- file.path(exp.parent, data.version, model.version, "draws")

#this file will be read in by each parallelized run in order to preserve draw covariance
clean.envir <- file.path(home.dir, "data", "clean.Rdata") 
  #objects imported:
  #coeff.draws = draws of the conversion factor to estimate bone lead from CBLI
  load(clean.envir)

##out##
summary.dir <- file.path(home.dir, 'products/exp', output.version, "summary")
out.dir <- file.path("/share/gbd/WORK/05_risk/02_models/02_results/envir_lead_bone/exp", output.version)

# Prep directories to save outputs
#Exposure
dir.create(summary.dir, recursive = T)
dir.create(out.dir, recursive = T)

#***********************************************************************************************************************  

#----FUNCTIONS----------------------------------------------------------------------------------------------------------  
##function lib##
#lead functions#

#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the general misc helper functions
file.path(central.function.dir, "misc.R") %>% source
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source
#***********************************************************************************************************************
 
#----PREP DATA----------------------------------------------------------------------------------------------------------  
#bring in and append all years for this country/sex
yearBind <- function(this.year,
                     ...) {
  
  #read in this year file
  file <- file.path(exp.dir, paste0("19_", this.location, "_", this.year, "_", this.sex, ".csv")) %>% fread
  
  
}

all.data <- mclapply(years,
                     yearBind,
                     mc.cores = cores.provided) %>% rbindlist

#merge on the age starts in order to calculate the midpoint age of group (used to calculate birth year of cohort)
age.map[age_group_id < 5, age_mid := 1] #everyone under age 1 was born last year
age.map[age_group_id >= 5, age_mid := age_start + 2] #self explanatory
age.map[age_group_id == 21, age_mid := 90] #everyone above age 80 was born ~90 years ago
all.data <- merge(all.data, age.map[, c('age_group_id', 'age_start', 'age_mid'), with=F], by="age_group_id")

#***********************************************************************************************************************

#----CALC and SAVE------------------------------------------------------------------------------------------------------
ageWrapper <- function(this.age,
                       ...) {
  
  message("-calculating for ", this.age)
  
  # first subset to the current year and age group in order to create a placeholder dataset
  data <- all.data[year_id == current.year & age_group_id == this.age,]

  #calculate year of birth for this age cohort
  yob <- current.year - age.map[age_group_id == this.age, age_mid]
  years <- seq(ifelse(yob>apex.year, yob, apex.year), current.year) #years produced by st-gpr for blood lead (this time only up to yob)
  
  #now loop through all the years and keep rows relevant to our cohort
  cohortBuilder <- function(this.year,
                            ...) {
    
    #calculate what age our start cohort would have been in this year
    cohort.age <- round_any(age.map[age_group_id == this.age, age_start] - (current.year - this.year), 5)
    
    if (age.cores == 1) {message("age start: ", cohort.age, "for year", this.year)}
    
    year.data <- all.data[age_group_id == age.map[age_start == cohort.age, age_group_id] & year_id == this.year, ]
    
    return(year.data)
    
  }
  
  all.cohort <- mclapply(years,
                         cohortBuilder,
                         mc.cores = cores.provided/age.cores) %>% rbindlist
  
  # if the yob for this cohort is > 1970 (apex.year), you are done!
  # if not, need to backcast to the yob using our assumption of linear decrease to 2ug/dL in 1920
  if (yob < apex.year) {
    
    backCast <- function(this.year,
                         data=all.cohort,
                         ...) {
      
      if (age.cores == 1) {message("--backcasting for the year ~ ", this.year)}
  
      # first subset to the start year in order to create a placeholder dataset 
      data <- data[year_id == apex.year]
      
      # now create a function that will take as input one draw of the blood lead values for the start year of the backcast
      # aka the blood lead apex year
      backCastHelper <- function(apex.value) {
        
        apex.value - ((apex.value-nadir.value)/(apex.year-nadir.year))*(apex.year - this.year)
        
      }
      
      # now pass that function each draw and replace the draw with the backcasted value for the working year
      data[, (draw.colnames) := lapply(.SD, backCastHelper), .SDcols=draw.colnames]
      
      #finally, replace the year_id with the working year, we will append all these new rows at the end
      data[, year_id := this.year]
      
      return(data)
      
    }
    
    back.cohort <- mclapply((apex.year-1):yob,
                            backCast,
                            mc.cores = cores.provided/age.cores) %>% rbindlist
    
    all.cohort <- rbind(all.cohort, back.cohort)
  
  }
  
  # now create a function that will calculate the cbli as the area under the blood lead curve for this cohort
  # it will then multiply the cbli 
  # aka the blood lead apex year
  boneHelper <- function(draw.number) {
    
    if (age.cores == 1) {message("---working on draw #", draw.number)}
    #calculate area under the curve for each draw (uses flux package auc() trapezoidal method)
    cbli <- all.cohort[, auc(year_id, get(draw.colnames[draw.number]))]
    bone <- cbli * coeff.draws[draw.number]
    
  }
  
  # now pass that function each draw and replace with estimated bone lead for that draw
  data[, (draw.colnames) := mclapply(1:draws.required, boneHelper, mc.cores = cores.provided/age.cores), with=F]
  
}

#now loop through the relevant ages to calculate the bone lead exposure for each of them in current year
all.ages <- mclapply(bone.ages, 
                     ageWrapper,
                     mc.cores = age.cores) %>% rbindlist

#output the final result to upload into the database for dalynator
write.csv(all.ages, 
          paste0(out.dir, "/19_", this.location, "_", current.year, "_", this.sex, ".csv"))

#create estimates of the distribution and then save summary 
id.variables <- c("age_group_id", "year_id", "sex_id", "location_id")

all.ages[,bone_lower := quantile(.SD ,c(.025)), .SDcols=draw.colnames, by=id.variables]
all.ages[,bone_mean := rowMeans(.SD), .SDcols=draw.colnames, by=id.variables]
all.ages[,bone_upper := quantile(.SD ,c(.975)), .SDcols=draw.colnames, by=id.variables]

#save summary
write.csv(all.ages[,-draw.colnames, with=F], 
          paste0(summary.dir, "/", this.location, "_", current.year, "_", this.sex, ".csv"))
#***********************************************************************************************************************
