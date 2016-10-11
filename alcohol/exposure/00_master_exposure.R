## Code for the following purposes:
## 00_master.R: Submission script to run the alcohol exposure prepping process for alcohol PAF code
## 01_pull_dismod.do: Pull DisMod results, format, save in locations for next steps, if national, squeeze prevalences to 100%
## 02_scale_subnational.do: Scale subnational prevalences to national, then squeeze to 100%
## 03_split_total_consumption.do: Split total consumption into draws of age-sex-year-location-specific consumption, parallel by location, also split Nat'l consumption to subnationals
##                                For locations with subnationals, so just submit nationals to this code, have conditional part to run if location is a parent to split to subnats
## BINGE AMOUNT AND POPULATION TWO REMAINING INPUTS TO STORE BEFORE PAF CODE


############
## Settings
############
rm(list=ls()); library(foreign)

if (Sys.info()[1] == 'Windows') {
  username <- "mcoates"
  root <- "J:/"
  code_dir <- "C:/Users//Documents/repos/drugs_alcohol/exposure"
  source("J:/Project/Mortality/shared/functions/get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  code_dir <- paste("/ihme/code/risk/", username, "/drugs_alcohol/exposure", sep="")
  if (username == "") code_dir <- paste0("/homes//drugs_alcohol/exposure")  
  setwd(code_dir)
  source("/home/j/Project/Mortality/shared/functions/get_locations.r")
}

test <- F              # if T, no files are deleted and no jobs are submitted.
start <-  1            # code piece to start (1 to run whole thing)
end <- 7
errout <- F
update_demfile <- F
update_pops <- F
share <- T             ## save in directory not on J drive

## set up options that apply to all jobs
r_shell <- "r_shell.sh"
stata_shell <- "stata_shell.sh"
python_shell <- "python_shell.sh"
stata_shell_mp <- "stata_shell_mp.sh"
errout_paths <- paste0("-o /share/temp/sgeoutput/",username,
                       "/output -e /share/temp/sgeoutput/",username,"/errors ")
proj <- "-P proj_custom_models "


## set up directories both to pass to jobs and to use in this script for deletions
prescale_dir <- paste0(ifelse(share,"/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                              paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"prescale")
postscale_dir <- paste0(ifelse(share,"/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                               paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale")

########################################
## DELETE FILES updated in this code if running (other deletions below)
########################################
if (update_demfile & file.exists(paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv"))) file.remove(paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv"))
if (update_pops & file.exists(paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/temp/populations.dta"))) file.remove(paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/temp/populations.dta"))

##########################################
## UPDATE DEMFILE ########################
##########################################
if (update_demfile) {
  ## submit a stata job to use the central comp function get_location_metadata to update file
  jname <- "update_loc_data"
  mycores <- 1
  sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ")
  script <- "update_loc_metadata.do"
  args <- paste("nothing")
  if (test) print(paste(sys.sub, stata_shell, script, args))
  if (!test) system(paste(sys.sub, stata_shell, script, args))
  
  ## check for locations file to wait for it to produce, since this code requires it to be used
  checkfile <- 0
  while (checkfile == 0) {
    print("waiting for loc file")
    Sys.sleep(15)
    if (file.exists(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv"))) checkfile <- 1
  }
  if (checkfile == 1) print("loc file saved")
}

######################################
## UPDATE POPULATIONS ################
######################################
if (update_pops) {
  ## submit a stata job to use the central comp function get_location_metadata to update file
  jname <- "update_pops"
  mycores <- 2
  sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ")
  script <- "update_pops.do"
  args <- paste("nothing")
  if (test) print(paste(sys.sub, stata_shell, script, args))
  if (!test) system(paste(sys.sub, stata_shell, script, args))
  
  ## check for locations file to wait for it to produce, since this code requires it to be used
  checkfile <- 0
  while (checkfile == 0) {
    print("waiting for pop file")
    Sys.sleep(30)
    if (file.exists(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta"))) checkfile <- 1
  }
  if (checkfile == 1) print("pop file saved")
}

## pull in locations hierarchy for use in submitting
locations <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/locations.csv"),stringsAsFactors=F)
## only keep things below the region level
locations <- locations[locations$level >= 3,]


########################################
## DELETE FILES FOR OTHER PIECES OF CODE TO ENSURE WE DON'T USE OLD VERSIONS
########################################
if (start <= 1) for (ff in dir(prescale_dir)) file.remove(paste0(prescale_dir,"/",ff))
if (start <= 1) for (ff in dir(postscale_dir)) file.remove(paste0(postscale_dir,"/",ff))
## for step 2, we want to make sure we've deleted any subnational prevalences from the post-scale dir
loc_ids_step2 <- unique(locations[locations$parent_id %in% unique(locations$location_id),])
if (start <= 2) {
  for (loc in unique(loc_ids_step2$location_id)) {
    if (file.exists(paste0(postscale_dir,"/prevalences_",loc,".dta"))) file.remove(paste0(postscale_dir,"/prevalences_",loc,".dta"))
  }
}
## for step 3, we want to delete the subnational consumption split results
loc_ids_step3 <- unique(locations[locations$parent_id %in% unique(locations$location_id),])
if (start <= 3) {
  for (loc in unique(loc_ids_step3$location_id)) {
    if (file.exists(paste0(postscale_dir,"/split_total_consumption_",loc,".dta"))) file.remove(paste0(postscale_dir,"/split_total_consumption_",loc,".dta"))
  }
  ## we also want to delete the new compiled file
  file.remove(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/alcohol_lpc_postsub.dta"))
}
## for step 4, we want to delete all the age-sex split consumption
if (start <= 4) {
  for (loc in unique(locations$location_id)) {
    file.remove(paste0(postscale_dir,"/alc_lpc_",loc,".dta"))
  }
}

#######################################
## RUN EXPOSURE PREP STEPS ############
#######################################

## 01_pull_dismod.do ##################
if (start <= 1 & end >= 1) {
  ## STEP 1 - PULL DISMOD FOR PREVALENCE MODELS, SQUEEZE NATS TO 100%, SAVE IN PRESCALE OR POSTSCALE DIRECTORY APPROPRIATELY
  ## So, nationals postscaled, subnationals prescaled and get scaled in step 2
  jlist1 <- c()
  
  for (loc in locations$location_id) { 
    jname <- paste("e1_pull_",loc, sep="")
    mycores <- 2
    sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ")
    script <- "01_pull_dismod.do"
    args <- paste(loc,prescale_dir,postscale_dir, sep=" ")
    
    if (test) print(paste(sys.sub, stata_shell, script, args))
    if (!test) system(paste(sys.sub, stata_shell, script, args))
    jlist1 <- c(jlist1, jname)
  }
}


## 02_scale_subnationals.do ##################
if (start <= 2 & end >= 2) {
  ## STEP 2 - Scale prevalences to national level, then force to add to 100%
  jlist2 <- c()
  
  for (loc in locations$location_id[locations$location_id %in% locations$parent_id & locations$level > 2]) { 
    jname <- paste("e2_subnat_",loc, sep="")
    mycores <- 4
    if (start == 2) {
      holds <- ""
    } else {
      holds <- paste("-hold_jid \"",paste(jlist1,collapse=","),"\"",sep="") 
    }
    
    sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
    script <- "02_scale_subnationals.do"
    args <- paste(loc,prescale_dir,postscale_dir, sep=" ")
    
    if (test) print(paste(sys.sub, stata_shell_mp, script, args))
    if (!test) system(paste(sys.sub, stata_shell_mp, script, args))
    jlist2 <- c(jlist2, jname)
  }
  
}

 
## 03_split_total_consumption.do ##################
if (start <= 3 & end >= 3) {
  ## STEP 3 -Split total consumption draws to subnational total consumption draws
  
  
  jlist3 <- c()
  
  for (loc in locations$location_id[locations$location_id %in% locations$parent_id & locations$level > 2]) { 
    jname <- paste("e3_totcons_",loc, sep="")
    mycores <- 4
    if (start == 3) {
      holds <- ""
    } else {
      holds <- paste("-hold_jid \"",paste(jlist2,collapse=","),"\"",sep="") 
    }
    
    sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
    script <- "03_split_total_consumption.do"
    postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                   paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale")
    stgpr <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/alcohol_lpc.dta")
    post_split <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats")
    args <- paste(loc,prescale_dir,postscale_dir,post_split,stgpr, sep=" ")
    
    if (test) print(paste(sys.sub, stata_shell_mp, script, args))
    if (!test) system(paste(sys.sub, stata_shell_mp, script, args))
    jlist3 <- c(jlist3, jname)
  }
  
  ## we now have split subnationals, but we want to wait for these to finish 
  ## and then we want to have them compiled with the nationals in one file to proceed
  ## so, we'll submit a job that holds on this step and searches for the subnational sims
  ## then, we'll compile with the stgpr results, replacing subnationals, and resave working copy and archive
  jname <- paste0("e3-5_comp_subnat")
  mycores <- 4
  holds <- paste("-hold_jid \"",paste(jlist3,collapse=","),"\"",sep="") 
  sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
  script <- "035_recompile_sims.do"
  postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                 paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale")
  stgpr <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/alcohol_lpc.dta")
  stgpr_subs <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/alcohol_lpc_postsub.dta")
  args <- paste(prescale_dir,postscale_dir,stgpr,stgpr_subs, sep=" ")
  
  if (test) print(paste(sys.sub, stata_shell_mp, script, args))
  if (!test) system(paste(sys.sub, stata_shell_mp, script, args))
  jlist35 <- jname
  
}

## 04_consumption_age_sex_splits.do ##################
if (start <= 4 & end >= 4) {
  ## STEP 4 -Split total consumption draws to age-sex specific using dismod output
  
  jlist4 <- c()
  
  for (loc in locations$location_id) { 
    jname <- paste("e4_agealc_",loc, sep="")
    mycores <- 4
    if (start == 4) {
      holds <- ""
    } else {
      holds <- paste("-hold_jid \"",paste(jlist35,collapse=","),"\"",sep="") 
    }
    
    sys.sub <- paste0("qsub ",proj,ifelse(errout,errout_paths,""),"-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
    script <- "04_consumption_age_sex_splits.do"
    postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                   paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale")
    stgpr_subs <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/stgpr/resplit_subnats/alcohol_lpc_postsub.dta")
    pop_file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta")
    args <- paste(loc,prescale_dir,postscale_dir,stgpr_subs,pop_file, sep=" ")
    
    if (test) print(paste(sys.sub, stata_shell_mp, script, args))
    if (!test) system(paste(sys.sub, stata_shell_mp, script, args))
    jlist4 <- c(jlist4, jname)
  }
  
}

## 05_match_2013_paf_inputs.py ##################
if (start <= 5 & end >= 5) {
  ## STEP 5 - Format exposure results to match 2013 for PAF calculation (to be replaced later ones PAF accomodates draws)

  jlist5 <- c()
  for (loc in locations$location_id) {
    jname <- paste("e5_paf_inputs_", loc, sep="")
    mycores <- 2
  
    if (start ==5) {
      holds <- ""
    } else {
      holds <- paste("-hold_jid \"", paste(jlist4, collapse=","), "\"",sep="")
    }
  
    sys.sub <- paste0("qsub ",proj, ifelse(errout,errout_paths,""), "-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
    script <- "05_match_2013_paf_inputs.py"
    postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                     paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale/")
    pop_file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta")
    args <- paste(postscale_dir, pop_file, loc, sep= " ")
  
    if (test) print(paste(sys.sub, python_shell, script, args))
    if (!test) system(paste(sys.sub, python_shell, script, args))
    jlist5 <- c(jlist5, jname)
    
  }
  
  ## STEP 5: Part 2 - IHME Boogaloo. Compile outputs from above
  
  holds <- paste("-hold_jid \"", paste(jlist5, collapse=","), "\"",sep="")
  script <- "06_compile_paf_inputs.py"
  postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                 paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale/")
  sys.sub <- paste0("qsub ",proj, ifelse(errout,errout_paths,""), "-cwd -N compile_paf_inputs ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
  
  if (test) print(paste(sys.sub, python_shell, script, postscale_dir))
  if (!test) system(paste(sys.sub, python_shell, script, postscale_dir))
  
  ## step 5: part 3 - bind on the binge amount/threshold
  holds <- paste("-hold_jid \"", paste("compile_paf_inputs", collapse=","), "\"",sep="")
  script <- "swap_in_binge_and_thresh.R"
  sys.sub <- paste0("qsub ",proj, ifelse(errout,errout_paths,""), "-cwd -N swap_binge_thresh ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
  
  if (test) print(paste(sys.sub, r_shell, script))
  if (!test) system(paste(sys.sub, r_shell, script))
  
  
}



## make agesplits
if (start <= 7 & end >= 7) {
  ## STEP 5 - Format exposure results to match 2013 for PAF calculation (to be replaced later ones PAF accomodates draws)
  
  jlist7 <- c()
  for (loc in locations$location_id) {
    jname <- paste("e7_agesplit_", loc, sep="")
    mycores <- 1
    
    if (start ==7) {
      holds <- ""
    } else {
      holds <- paste("-hold_jid \"", paste(jlist4, collapse=","), "\"",sep="")
    }
    
    sys.sub <- paste0("qsub ",proj, ifelse(errout,errout_paths,""), "-cwd -N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
    script <- "07_create_agesplit_files.do"
    postscale_dir <- paste0(ifelse(share,"/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                                   paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale/")
    pop_file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta")
    temp_dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
    args <- paste(postscale_dir, temp_dir, pop_file, loc, sep= " ")
    
    if (test) print(paste(sys.sub, stata_shell, script, args))
    if (!test) system(paste(sys.sub, stata_shell, script, args))
    jlist7 <- c(jlist7, jname)
    
  }
  

  holds <- paste("-hold_jid \"", paste(jlist7, collapse=","), "\"",sep="")
  script <- "08_compile_resave_agefrac.do"
  args <- paste(postscale_dir, temp_dir, sep= " ")
  sys.sub <- paste0("qsub ",proj, ifelse(errout,errout_paths,""), "-cwd -N compile_agefrac ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",holds)
  
  if (test) print(paste(sys.sub, stata_shell, script, args))
  if (!test) system(paste(sys.sub, stata_shell, script, args))
}
