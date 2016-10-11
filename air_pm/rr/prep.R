#----HEADER-------------------------------------------------------------------------------------------------------------
# Project: RF: air_pm
# Purpose: Prep relative risk data for fitting of the IER curve
#***********************************************************************************************************************
 
#----CONFIG-------------------------------------------------------------------------------------------------------------
# clear memory
rm(list=ls())

# disable scientific notation
options(scipen = 999)

# runtime configuration
if (Sys.info()["sysname"] == "Linux") {
  
  arg <- commandArgs()[-(1:3)]  # First args are for unix use only

} else { 
  
  arg <- c(7, 1000)
  
}

# load packages, install if missing
pacman::p_load(data.table, ggplot2, grid, magrittr, reshape2, stringr)

# set working directories
home.dir <- file.path(j_root, "WORK/05_risk/risks/air_pm/")
setwd(home.dir)

# set parameters
version <- arg[1]
draws.required <- arg[2]
terminal.age <- 110   # age at which age-specific causes no longer are at risk for caues

##in/out##
# in
raw.dir <- file.path(home.dir, 'data/rr/raw')
  #updated dataset for active smoking based on studies sent by air EG
  data.2015.as <- file.path(raw.dir, "rr_gbd2015_as.csv") %>% fread
  #updated dataset for all OAP RRs, new extraction methodology and some new studies
  data.2015.oap <- file.path(raw.dir, "rr_gbd2015_oap.csv") %>% fread
  #data from 2013, all OAPs will be dropped to favor the updated versions
  data.2013 <- file.path(raw.dir, "rr_gbd2013.csv") %>% fread
tmrel.dir <- file.path(home.dir, 'data/tmrel/')
  #define tmrel file(draws) based on current model version. only version 1 will use the gbd2013 tmrel
  tmrel.file <- ifelse(version<2, file.path(tmrel.dir, "tmrel_gbd2013.csv"), file.path(tmrel.dir, "tmrel_gbd2015.csv")) %>% fread
  tmrel.mean <-  ifelse(version!=4, mean(tmrel.file[[1]]), 0)

# out
prepped.dir <- file.path(home.dir, 'data/rr/prepped/', version)
  dir.create(prepped.dir, recursive=T)
graphs.dir <- file.path(home.dir, 'diagnostics/rr')
  dir.create(graphs.dir, recursive=T)

#function library
air.function.dir <- file.path(h_root, '_code/risks/air_pm/_lib')
  # this pulls the miscellaneous helper functions for air pollution
  file.path(air.function.dir, "misc.R") %>% source()
  
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
  # this pulls the general misc helper functions
  file.path(central.function.dir, "misc.R") %>% source()
  # this pulls the current locations list
  file.path(central.function.dir, "get_locations.R") %>% source()
  
#bring in locations
  locations <- get_locations() %>% as.data.table
  
#bring in list of ages and causes to output data for
  age.cause <- ageCauseLister()
#***********************************************************************************************************************
 
#----PREP 2013 DATA-----------------------------------------------------------------------------------------------------
# first prep the 2013 data
# cleanup
  meta.variables <- c('zotero', 'exprr', 'explower', 'expupper', 'listed_cigarettes', 'per_cig', 'div_12', 
                      'notes', 'smaller_site_unit', 'site_memo', 'year_issue', 'note_atardif', 'updated')
  #drop outliers, points that have been updated, and unnecessary metavariables
  data.2013 <- data.2013[outlier!=1 & updated!=1, -meta.variables, with=F]
  #create index variable for vectorized functions
  data.2013[, index := seq_len(.N)]
# SHS needs to be mapped using the cigs/capita covariate and PM/cig derived from Semple 2014
  data.2013.shs <- data.2013[source == 'SHS',]
  #define midyear
  data.2013.shs[, year_id := as.character(round((as.integer(year_end) + year_start)/2, 0))]
  #set location/year to Global if its unknown or not in cigs ps dataset
  data.2013.shs[location_name=="", location_name := "Global"]
  data.2013.shs[location_name=="Greenland", location_name := "Global"] #dont have this country in dataset currently
  data.2013.shs[year_id=="1969", year_id := "1970"] #dont have this year in dataset currently
  data.2013.shs[is.na(year_id)==T, year_id := "Unknown"]
  
  #for now use the old cigarettes per smoker, but this needs to be a SQL pull instead
  cigs.ps <- fread(file.path(raw.dir, 'cigs_ps_db.csv'))
  #merge on location names
  cigs.ps <- merge(cigs.ps, locations[, c('location_name', 'location_id'), with=F])
  
  #store draw colnames in vector
  draw.colnames <- paste0("draw_", 0:(draws.required-1))

  # fill out with aggregates for datapoints that location/year is unknown (currently using average to collapse)
  # unknown location
  cigs.ps.global <- cigs.ps[, lapply(.SD, mean), by=year_id, .SDcols=c(draw.colnames)]
    cigs.ps.global[, location_name := "Global"]
  # unknown year  
  cigs.ps.timeless <- cigs.ps[, lapply(.SD, mean), by=location_name, .SDcols=c(draw.colnames)]
    cigs.ps.timeless[, year_id := "Unknown"]
  # unknown both  
  cigs.ps.total <- cigs.ps[, lapply(.SD, mean), .SDcols=c(draw.colnames)]
    cigs.ps.total[, location_name := "Global"]
    cigs.ps.total[, year_id := "Unknown"]
  #combine  
  cigs.ps <- rbind(cigs.ps, cigs.ps.global, cigs.ps.timeless, cigs.ps.total, fill=T)
  
  #merge on to the shs data
  data.2013.shs <- merge(data.2013.shs, cigs.ps, by=c('location_name', 'year_id'), all.y=FALSE)
  
  # based on previously defined qualitiative measure of intensity (current conc), pull a draw from the 
  # distribution of PM per cigarette, and then apply the country level of cigarettes per smoker
  data.2013.shs[conc == 20, conc := quantile(.SD, .25), .SDcols=draw.colnames, by=index]
  data.2013.shs[conc == 35, conc := rowMeans(.SD), .SDcols=draw.colnames, by=index]
  data.2013.shs[conc == 50, conc := quantile(.SD, .75), .SDcols=draw.colnames, by=index]
  
  #the SHS data is finished prepping, merge it back on (no longer need the added columns)
  data.2013 <- rbind(data.2013[source!="SHS"], data.2013.shs[, -c('year_id', 'location_id', draw.colnames), with=F])
  data.2013 <- data.2013[, -c('location_name', 'year_start', 'year_end', 'outlier'), with=F]
  
  #fill in the standard deviations using extracted CI and then generate weights
  data.2013[is.na(logrrsd), logrrsd := (logrrupper-logrrlower)/3.92]
  data.2013[, weight := 1/(logrrsd^2)]
  
  #standardize and clean to prep for later combination
  data.2013 <- data.2013[, -c('logrrupper', 'logrrlower', 'index'), with=F] #no longer need
  setnames(data.2013, c('logrr', 'medage', 'logrrsd'), c('log_rr', 'age_median', 'log_se'))
#***********************************************************************************************************************  
   
#----PREP 2015 DATA-----------------------------------------------------------------------------------------------------
# now prep 2015 data
  meta.variables <- c('location_id', 'ihme_loc_id', "year_start", 'year_end', 'exposure_type', 'sex', 'control_group', 
                      'control_pct', 'location_name', 'risk_factor_measure', 'measure', 'measure_adjustment', 'group', 'specificity', 'case_name', 
                      'case_definition', 'case_diagnostics', 'risk_factor', 'field_citation_value', 'page_num', 'table_num', 'source_type',
                      'group_review', 'note_modeler', 'note_sr', 'extractor', 'smaller_site_unit', 'site_memo', 'is_outlier')
  data.2015.as <- data.2015.as[is_outlier!=1, -meta.variables, with=F] #drop outliers and unnecessary metavariables
  data.2015.as[, study := str_replace(file_path, 'J:/WORK/05_risk/risks/air_pm/data/rr/incoming/lit/AS papers/', '')]
  
  # estimate median age if it was not given (take midpoint)
  data.2015.as[is.na(age_median), age_median := (age_end + age_start)/2]
  data.2015.as <- data.2015.as[, -c('age_start', 'age_end'), with=F] #no longer necessary
  
  # active smoking concentrations have been given in # of cigarettes
  # convert them to PM2.5 using method as described in email on 11/19/14: 
  # anyway,  the conversion used is correct 666.6 ug/m3 = 1 cig/day 
  # this comes from the 12ng of PM2.5 per 1 cig and a average adult breating rate of 18 m3/day 
  # 12,000 ug/1cig/(18 m3.day) = 666.6  ug/m3 per day)
  pm.per.cig <- 666.6
  data.2015.as[, conc := conc * pm.per.cig]
  
  # if we have the upper and lower, we can just log those and convert to log SE, which avoids delta approximating
  data.2015.as[!is.na(upper)&!is.na(lower), log_se := (log(upper)-log(lower))/3.92]
  
  #if not, transform using delta method
  # delta method in logspace is variance = (standard_error^2)*((1/mean)^2) = (standard_error/mean)^2 
  # sqrt(variance) = standard_error, so log_se = sqrt((standard_error/mean)^2) = standard_error/mean
  data.2015.as[is.na(log_se), log_se := (standard_error/mean)]

  # then generate weights using inverse variance
  data.2015.as[, weight := 1/(log_se^2)]
  
  #log transform the relative risks
  data.2015.as[, log_rr := log(mean)]
  
  #cleanup
  data.2015.as <- data.2015.as[, c('nid', 'source', 'cause', 'age_median', 'conc', 'conc_den', 'log_rr', 'log_se', 'weight', 'study'),
                         with=F]
  
  #prep 2015 OAP updated dataset
  meta.variables <- c('citation', 'notes')
  data.2015.oap <- data.2015.oap[, -c(meta.variables), with=F] #cleanup
  
  #assume increment is 10 if unlist
  data.2015.oap[is.na(conc_increment), conc_increment := 10]
  
  #estimate concentration p5/p95 from mean/sd using z if necessary
  data.2015.oap[is.na(conc_5), conc_5 := conc_mean - conc_sd * 1.645]
  data.2015.oap[is.na(conc_95), conc_95 := conc_mean + conc_sd * 1.645]
  
  #shift the RRs using p95/p5 range concentration increment
  data.2015.oap[, rr_shift := rr ^ ((conc_95-conc_5)/conc_increment)]
  data.2015.oap[, rr_lower_shift := rr_lower ^ ((conc_95-conc_5)/conc_increment)]
  data.2015.oap[, rr_upper_shift := rr_upper ^ ((conc_95-conc_5)/conc_increment)]
  
  #log transform the relative risks
  data.2015.oap[, log_rr := log(rr_shift)]
  
  # if we have the upper and lower, we can just log those and convert to log SE, which avoids delta approximating
  data.2015.oap[, log_se := (log(rr_upper_shift)-log(rr_lower_shift))/3.92]
  
  # then generate weights using inverse variance
  data.2015.oap[, weight := 1/(log_se^2)]
  
  #calculate median ages for cardiovascular outcomes
  data.2015.cardio <- data.2015.oap[cause %in% c("cvd_ihd", "cvd_stroke")]
  
  #first calcluate the avg years of followup if not extracted
  data.2015.cardio[is.na(age_median) & is.na(avg_follow_up), avg_follow_up := as.numeric(person_years) / as.numeric(sample_size)]
  
  #now assign age_median as age at enrollment + average follow in years / 2 (as specified in EG discussion)
  data.2015.cardio[is.na(age_median), age_median := age_enrollment + avg_follow_up/2]
  
  #we have decided not to use any incidence studies for cvd, given that we are adjusting morb later
  data.2015.cardio <- data.2015.cardio[outcome!="incidence"]
  
  #add the updated cardio back into the full OAP dataset
  data.2015.oap <- rbind(data.2015.oap[!(cause %in% c("cvd_ihd", "cvd_stroke"))], data.2015.cardio)
  
  #cleanup
  setnames(data.2015.oap, c('conc_5', 'conc_95'), c('conc_den', 'conc'))
  data.2015.oap <- data.2015.oap[, c('nid', 'study', 'source', 'cause', 'age_median', 'conc', 'conc_den', 'log_rr', 'log_se', 'weight'),
                         with=F]
  
  #combine all data
  input.data <- rbind(data.2015.oap, data.2015.as, data.2013, fill=TRUE)
  setcolorder(input.data, c('nid', 'source', 'cause', 'conc', 'conc_den', 'log_rr', 'log_se', 'weight', 'age_median', 'study'))
  
  write.csv(input.data, file = file.path(prepped.dir, "input_dataset.csv"), row.names=FALSE)
#*********************************************************************************************************************** 
    
#----PREP ALL-----------------------------------------------------------------------------------------------------------  
#now that your data has been cleaned up and combined, there are some general prep steps before it can be saved
  #fill in conc_den with the tmrel if the control group's exposure is unknown
  input.data[is.na(conc_den), conc_den := tmrel.mean]

  #fill in age.median with average age for cause/source if missing
  input.data[, mean_age := mean(age_median, na.rm=T), by='cause,source']
  input.data[is.na(age_median), age_median := mean_age]
  input.data[, mean_age := NULL]
  
  # We hold the IER curve to be 1 when it is below the tmrel, but the 
  # function would actually go below 1. Therefore, we set the z to be the
  # tmrel when it goes below. 
  input.data[conc < tmrel.mean, conc := tmrel.mean]
  input.data[conc_den < tmrel.mean, conc_den := tmrel.mean]
  
# now loop through the age cause pairs and save an Rdata file for each
  
  saveData <- function(age.cause.number,
                       age.cause.list,
                       output.dir) {
    
    this.cause <- age.cause.list[age.cause.number, 1]
    this.age <- age.cause.list[age.cause.number, 2]
    
    draw.data <- input.data[cause == this.cause, ]
    
    output.name <- paste0(this.cause, "_", this.age, ".RData")
    message("generating ", output.name)
    
    ### For age specific RRs (currently only cvd_ihd/stroke), interpolate all-age log RR to terminal age to
    ### get RR estimates. Implement Steve's approach:
    ### Force x-intercept to be equal to terminal age. That is
    ### 0 = \beta_0 + \beta_1*term.age
    ### and in general
    ### log(RR_age) = \beta_0 + \beta_1*age
    ### So, we have that
    ### \beta_1 = (log(RR_age) - 0) / (age - term.age)
    ### And log(RR_age)= \beta_1(age - term.age)
    if (this.age == 99) {
      
      draw.data[, log_rr := log_rr] # no change necessary
      
    } else {

      draw.data[, log_rr := ((log_rr - 0)/(age_median - terminal.age)) * (as.numeric(this.age) - terminal.age)]
      
      #also apply the same formula to the uncertainty
      draw.data[, log_se := ((log_se - 0)/(age_median - terminal.age)) * (as.numeric(this.age) - terminal.age)]

    }
    
    # add in the mean TMREL
      draw.data[, tmrel := tmrel.mean]
    
    save(draw.data, file=file.path(output.dir, output.name))
    
    return(draw.data)
    
  }
  
  all.data <- lapply(1:nrow(age.cause), saveData, output.dir = prepped.dir, age.cause.list = age.cause)
  
#***********************************************************************************************************************     
  
#----SCRAP--------------------------------------------------------------------------------------------------------------
