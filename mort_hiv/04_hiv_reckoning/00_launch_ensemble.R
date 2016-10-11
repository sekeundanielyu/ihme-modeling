## Run all portions of Ensemble process
## Involving, for Group 1 (GEN): Average Spectrum and Envelope HIV results
## For Group 2A (Non-GEN incomplete): Subtract ST-GPR results from all-cause
## For Group 2B/2C: Use CIBA Spectrum results 

## Outputs: post-reckoning, without-shock, with-HIV and HIV-deleted envelopes and lifetables

###############################################################################################################
## Set up settings
  rm(list=ls())
  library(foreign); library(RMySQL); library(dplyr); library(data.table)
  
  if (Sys.info()[1]=="Windows") {
    root <- "J:" 
    user <- Sys.getenv("USERNAME")
  } else {
    root <- "/home/j"
    user <- Sys.getenv("USER")
  }
  
## Grab functions
  source(paste0(root,"/Project/Mortality/shared/functions/qsub.R"))
  source(paste0(root,"/Project/Mortality/shared/functions/check_loc_results.r"))
  source(paste0(root, "/Project/Mortality/shared/functions/get_locations.r"))
  source(paste0(root, "/Project/Mortality/shared/functions/get_age_map.r"))

## Set start and end options
## Note: These are categorized toggles rather than numeric because of the number of possibilities that can be run in parallel
## First, do you want to run the ensemble process?
  run_ensemble <- T
  
## Run LTs based off of ensemble
  run_lts <- T
  
## Run envelope aggregation and prep for upload
  env_agg <- T
  lt_agg <- T
  
## Run envelope upload, and potentially mark as best
  upload_results <- T
  mark_best <- T

## Set other run options
  spec_name <- "160515_echo1" # Update this with the new Spectrum run results each time
  test <- F # Test submission of everything 
  file_del <- T
  
## Set directories
  out_dir <- "strPath"
  out_dir_hiv <- paste0("strPath",spec_name)
  out_dir_hiv_free <- "strPath"
  out_dir_lt_free <- "strPath"
  out_dir_lt_whiv <- "strPath"
  out_dir_products <- paste0(root,"strPath")
  out_dir_adjust_summary <- paste0(root,"strPath")

## Grab locations
  codes <- get_locations(level = "lowest")
  run_countries <- unique(codes$ihme_loc_id)
  write.csv(codes,paste0(root,"strPath/locations.csv"))

## Set code_dir
  code_dir <- paste0("strPath/",user,"/strPath")
  setwd(code_dir)

## Find and save an age map for use in 01_ensemble for formatting
  age_map <- get_age_map()
  write.csv(age_map,"strPath/age_map.csv")

## Get new version number for the next upload
  myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
  sql_command <- paste0("SELECT MAX(output_version_id) ",
                        "FROM mortality.output_version ")
  max_version <- dbGetQuery(myconn, sql_command)
  dbDisconnect(myconn)
  new_upload_version <- max_version[1][[1]] + 1

## Create draw maps to scramble draws so that they are not correlated over time
  ## This is because Spectrum output is semi-ranked due to Ranked Draws into EPP
  ## Then, it propogates into here
  ## We make sure that each location_id has their seed set to a unique seed to avoid cross-location correlation
  create_draws <- function(location_id) {
    new_seed <- location_id * 100 + 121 # Just to avoid any unintended correlation with other seeds that rely on location_id
    set.seed(new_seed)
    data <- data.table(expand.grid(location_id=location_id,old_draw=c(0:999)))
    data[,draw_sort:=rnorm(1000)]
    data <- data[order(location_id,draw_sort),]
    data[,new_draw:=seq_along(draw_sort)-1,by = location_id] # Creates a new variable with the ordering based on the values of draw_sort 
    data[,draw_sort:=NULL]
  }
  draw_map <- rbindlist(lapply(unique(codes$location_id),create_draws))
  
  write.csv(draw_map,paste0(root,"strPath/draw_map.csv"),row.names=F)

  
###############################################################################################################
## Create HIV type file
  ## Find GEN country indicators
  gen_list <- data.frame(read.csv(paste0(root,"/strPath/gen_countries_final.csv"),header=FALSE,stringsAsFactors=FALSE))
  gen_list <- unique(gen_list)
  gen_countries <- unique(gen_list$V1)
  gen_list$group <- "1A"
  gen_list$group[grepl("IND",gen_list$V1)] <- "1B" ## We want to subtract HIV from with-HIV, but still average it, in the case of IND
  names(gen_list)[names(gen_list)=="V1"] <- "ihme_loc_id"
  
  ## Get indicators of countries classified as complete by CoD (>25 years post-1980 of complete VR) (for use in 1.5)
  comp_list <- read.csv(paste0(root,"/strPath/cod_completeness_gbd2015_final.csv"),stringsAsFactors=FALSE)
  comp_list <- merge(comp_list,gen_list,all.x=T)
  comp_list <- comp_list[is.na(comp_list$group),] # Only the non-GEN countries are Group 2A
  comp_list$group <- "2A"
  comp_list <- comp_list[,c("ihme_loc_id","group")]
  
  ## Use parent country completeness for all subnationals
  comp_list$ihme_loc_id[comp_list$ihme_loc_id == "CHN_44533"] <- "CHN"
  comp_list <- comp_list[!grepl("_",comp_list$ihme_loc_id) | comp_list$ihme_loc_id == "CHN_354" | comp_list$ihme_loc_id == "CHN_361",]
  comp_list$parent_iso3 <- comp_list$ihme_loc_id
  
  subnat_locs <- get_locations(level="subnational")
  subnat_locs <- subnat_locs[subnat_locs$ihme_loc_id != "CHN_354" & subnat_locs$ihme_loc_id != "CHN_361",]
  subnat_locs$parent_iso3 <- gsub("_.*","",subnat_locs$ihme_loc_id)
  subnat_locs <- select(subnat_locs,parent_iso3,new_ihme=ihme_loc_id)
  comp_list <- merge(comp_list,subnat_locs,by="parent_iso3",all.x=T)
  comp_list$ihme_loc_id[!is.na(comp_list$new_ihme)] <- comp_list$new_ihme[!is.na(comp_list$new_ihme)]
  comp_list <- select(comp_list,ihme_loc_id,group)
  
  ## Get list of countries that have data in the VR database
  ## Use the list generated by ST-GPR to figure this out
  vr_data <- fread('/strPath/test_hiv_dataset_12022015.csv')
  vr_countries <- data.frame(ihme_loc_id = unique(vr_data$ihme_loc_id), vr_exists = 1)
  
  ## Create master list of countries, for reference by other processes
  groups <- rbind(gen_list,comp_list)
  master_types <- get_locations()
  master_types <- merge(master_types,groups,all.x=T)
  master_types <- merge(master_types,vr_countries,all.x=T)
  master_types$group[is.na(master_types$group) & master_types$vr_exists==1] <- "2B" # Incomplete VR
  master_types$group[is.na(master_types$group) & is.na(master_types$vr_exists)] <- "2C" # No data countries
  
  ## Manual fixes
  master_types$group[master_types$ihme_loc_id=="MDG"] <- "2C" ## Even if it has VR data, we consider it a 2C for ensemble purposes
  master_types$group[master_types$ihme_loc_id=="KHM"] <- "2B"
  
  ## Apply child groups to parents, up to level 3
  max_count <- function(char_list) {
    names(which.max(table(char_list)))
  }
  
  master_types <- data.table(master_types)
  for(agg_level in 4:3) {
    loc_list <- unique(master_types[level == agg_level & location_id %in% unique(parent_id),location_id])
    
    ## Check that all the children actually exist in the source dataset, to prevent a parent location being an incomplete composite of all of its children
    child_list <- master_types[level==(agg_level + 1) & parent_id %in% loc_list,location_id]
    child_exist <- unique(master_types[parent_id %in% loc_list,location_id])
    missing_list <- child_list[!(child_list %in% child_exist)]
    if(length(missing_list) != 0) {
      stop(paste0("The following child locations are missing, cannot generate ID: ",missing_list))
    }
    
    # Take the value that has the most values within subnationals
    for(parent in loc_list) {
      print(parent)
      master_types[location_id==parent, group:= max_count(master_types[parent_id==parent,group])] 
    }
  }
  
  master_types <- master_types[,list(location_id,ihme_loc_id,group)]
  write.csv(master_types,paste0(root,"/strPath/ensemble_groups.csv"),row.names=F)
  

###############################################################################################################
## Remove Existing Files
if (file_del == T) {
  if (run_ensemble==T) {
    print("Deleting 01_ensemble output -- should take 5-10 minutes (maybe more)")
    system(paste0("perl -e 'unlink <",out_dir,"/en_summ_*dta>' "))
    system(paste0("perl -e 'unlink <",out_dir,"/scalars_*.dta>' "))
    system(paste0("perl -e 'unlink <",out_dir,"/env_*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir,"/comparison*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_hiv_free,"/draws/env_*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_hiv,"/hiv_death_*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_hiv,"/reckon_reporting_*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_adjust_summary,"/results*.csv>' "))
  }
  if(run_lts == T) {
    print("Deleting 02_lt output")
    system(paste0("perl -e 'unlink <",out_dir_lt_free,"/lt*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_free,"/summary*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_free,"/mx_ax/mx_ax*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_free,"/qx/qx*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_free,"/mean_qx/mean_*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_whiv,"/lt*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_whiv,"/summary*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_whiv,"/mx_ax/mx_ax*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_whiv,"/qx/qx*.csv>' "))
    system(paste0("perl -e 'unlink <",out_dir_lt_whiv,"/mean_qx/mean_*.csv>' "))
  }
  if (env_agg == T) {
    print("Deleting env_agg output")
    ## From agg_env
    file.remove(paste0(out_dir_hiv_free,"/draws/result/combined_env_aggregated.dta"))
    file.remove(paste0(out_dir_hiv_free,"/summary/result/agg_env_summary.dta"))
  }
  if(lt_agg == T) {
    print("Deleting lt_agg output")
    ## From agg_mx_ax
    system(paste0("perl -e 'unlink < ",out_dir_lt_free,"/mx_ax/result/region_*.csv>' "))
    system(paste0("perl -e 'unlink < ",out_dir_lt_whiv,"/mx_ax/result/region_*.csv>' "))

    ## From calc_lt_agg
    file.remove(paste0(out_dir_lt_free,"/result/combined_aggregated_lt.csv"))
    file.remove(paste0(out_dir_lt_whiv,"/result/combined_aggregated_lt.csv"))
    
    ## From 02d_calc_agg_qx
    system(paste0("perl -e 'unlink < ",out_dir_lt_free,"/mean_qx/mean_45q15_agg_*.csv>' "))
    system(paste0("perl -e 'unlink < ",out_dir_lt_free,"/mean_qx/mean_5q0_agg_*.csv>' "))
    system(paste0("perl -e 'unlink < ",out_dir_lt_whiv,"/mean_qx/mean_45q15_agg_*.csv>' "))
    system(paste0("perl -e 'unlink < ",out_dir_lt_whiv,"/mean_qx/mean_5q0_agg_*.csv>' "))
  }
}

###############################################################################################################
## Submit Jobs
  
## NOTE: MAKE SURE THAT IN HIV, PREP_SPEC_RESULTS HAS BEEN RUN ON ALL INPUT DATA

## Run ensemble process
  if (run_ensemble==T) {
    system(paste0("mkdir ",out_dir_hiv)) # Makes uniquely-named HIV results folder based on Spectrum name
    for(country in run_countries) {
      group <- unique(master_types$group[master_types$ihme_loc_id==country])

      qsub(paste0("ensemble_01_",country),paste0(code_dir,"/01_run_ensemble.R"), slots = 3,  pass=list(country,group,spec_name), proj="proj_mortenvelope", submit = !test, log = T)
    }

    print("Waiting 5 minutes before checking results for 01_ensemble")
    Sys.sleep(60*5)

    ## Check for output
    check_loc_results(run_countries,out_dir,prefix="env_",postfix=".csv")
    check_loc_results(run_countries,paste0(out_dir_hiv_free,"/draws"),prefix="env_",postfix=".csv")
    check_loc_results(run_countries,out_dir_hiv,prefix="hiv_death_",postfix=".csv")

    ## Now, compile all files together -- will save it in paste0(out_dir,"/result")
    file.remove(paste0(out_dir_hiv_free,"/draws/result/combined_env.csv"))
    file.remove(paste0(out_dir,"/result/combined_env.csv"))
    system(paste0("sh ",code_dir,"/combine_env.sh"))

    ## Create copies of the draw files for CoD to use them easily later
    system(paste0("cp ",out_dir,"/result/combined_env.csv ",out_dir,"/result/combined_env_v",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_hiv_free,"/draws/result/combined_env.csv ",out_dir_hiv_free,"/draws/result/combined_env_v",new_upload_version,".csv"))

    ## Submit jobs to summarize HIV adjustment output
    ## We want all locations at national except for GBR subnational
    adjust_locs <- data.table(get_locations(level="all"))
    adjust_locs <- adjust_locs[level ==3 | (level == 5 & grepl("GBR",ihme_loc_id)),]
    run_adj_locs <- unique(adjust_locs[,ihme_loc_id])
    check_adj_locs <- unique(adjust_locs[,location_id])
    
    for(country in run_adj_locs) {
      loc_id <- unique(adjust_locs[ihme_loc_id==country,location_id])
      if(country %in% c("USA","KEN","JPN","ZAF","CHN","IND","MEX","BRA","SAU","GBR")) { # Extra slots for extra special parent countries -- couldn't figure out the code to get the num of children, so just have this manual list for now
        qsub(paste0("sum_hiv_01b_",country),paste0(code_dir,"/01b_prep_hiv_adjust.R"), slots = 6,pass=list(loc_id,spec_name,new_upload_version), proj="proj_mortenvelope", submit = !test, log = T)
      } else {
        qsub(paste0("sum_hiv_01b_",country),paste0(code_dir,"/01b_prep_hiv_adjust.R"), slots = 1,pass=list(loc_id,spec_name,new_upload_version), proj="proj_mortenvelope", submit = !test, log = T)
      }
    }
    check_loc_results(check_adj_locs,out_dir_adjust_summary,prefix="results_",postfix=".csv")
    system(paste0("sh ",code_dir,"/combine_hiv_adjust.sh"))
    system(paste0("cp ",out_dir_adjust_summary,"/result/results_hiv_adjust.csv ",
                  out_dir_adjust_summary,"/result/results_hiv_adjust_",new_upload_version,".csv"))
  }

## Start envelope aggregation to region/age/sex aggregates now
  if (env_agg == T) {
    for(type in c("hiv_free","with_hiv")) {
      qsub(paste0("agg_env_02a_",type),paste0(code_dir,"/02a_agg_env.R"), slots = 40,pass=type, proj="proj_mortenvelope", intel=T, submit = !test, log = T)
    }
  }

  ## Upload the envelope results to the DB and mark as best
  if(upload_results == T) {
    qsub("upload_02b",paste0(code_dir,"/02b_envelope_upload.do"), slots = 10,  pass=new_upload_version, hold = ifelse(env_agg,"agg_env_02a_hiv_free,agg_env_02a_with_hiv","fakejob"), proj="proj_mortenvelope", submit = !test, log = T)
  }  
  
  if(mark_best==T) {
    qsub("best_02c",paste0(code_dir,"/02c_mark_best.do"), slots = 2,  hold = "upload_02b", proj="proj_mortenvelope", submit = !test, log = T)
  }

## At the same time, create new LTs based off of the new MX results from HIV
  if (run_lts==T) {
    for(country in run_countries) {
      group <- unique(master_types$group[master_types$ihme_loc_id==country])
      loc_id <- unique(codes$location_id[codes$ihme_loc_id == country])
      qsub(paste0("lt_gen_02_",country),paste0(code_dir,"/02_lt_gen.R"), slots = 4,  pass=list(country,loc_id,group,spec_name), proj="proj_mortenvelope", submit = !test, log = T)
    }
    
    print("Waiting 10 minutes before checking for 02_lt results")
    Sys.sleep(60*10)
    
    ## Check for output
    check_loc_results(run_countries,paste0(out_dir_lt_free),prefix="summary_",postfix=".csv")
    check_loc_results(run_countries,paste0(out_dir_lt_whiv),prefix="summary_",postfix=".csv")
  
    ## Compile LT summary files and mx-ax draw-level files
    file.remove(paste0(out_dir_lt_free,"/result/combined_lt.csv"))
    file.remove(paste0(out_dir_lt_whiv,"/result/combined_lt.csv"))
    system(paste0("sh ",code_dir,"/combine_lt_summary.sh"))
    
    ## Create copies of the summary files for CoD to use them easily later
    system(paste0("cp ",out_dir_lt_free,"/result/combined_lt.csv ",
                  out_dir_lt_free,"/result/combined_lt_v",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_lt_whiv,"/result/combined_lt.csv ",
                  out_dir_lt_whiv,"/result/combined_lt_v",new_upload_version,".csv"))

    ## Compile mx and ax values
    print("Combining mx and ax values -- will take around 1.5-2 hours")
    system(paste0("rm ",out_dir_lt_free,"/mx_ax/result/combined_mx_ax*.csv"))
    system(paste0("rm ",out_dir_lt_whiv,"/mx_ax/result/combined_mx_ax*.csv"))
    system(paste0("sh ",code_dir,"/combine_mx_ax.sh"))
  }
    
## Create age, sex, and region/global envelope aggregates at the draw level, and create draw- and summary-level files
  if (lt_agg == T) {
    for(type in c("hiv_free","with_hiv")) {
      ## Submit code to aggregate from mx_ax at country to mx_ax at region level
      for(count in 0:9) {
        qsub(paste0("agg_mx_ax_",type,"_",count),paste0(code_dir,"/02a_agg_mx_ax.R"), slots = 25,pass=list(type,count), proj="proj_mortenvelope", submit = !test, log = T)
      }
    }

    print("Waiting 30 minutes before beginning checks for 02a_agg_mx_ax")
    Sys.sleep(60*30)

    check_loc_results(paste0(rep(0:9)),paste0(out_dir_lt_free,"/mx_ax/result"),prefix="region_",postfix=".csv")
    check_loc_results(paste0(rep(0:9)),paste0(out_dir_lt_whiv,"/mx_ax/result"),prefix="region_",postfix=".csv")

    print("Waiting 5 mins for files to finish writing")
    Sys.sleep(300)

    ## Bring together all the 10 aggregate-draw files, create lifetables, output agg-specific draw files and summarize then make region-specific summaries
    for(type in c("hiv_free","with_hiv")) {
      qsub(paste0("calc_lt_agg",type),paste0(code_dir,"/02b_calc_lt_agg.R"),slots = 30,pass=type,proj="proj_mortenvelope", submit = !test, intel=T, log = T)
    }

    print("Waiting 20 minutes before beginning checks for 02b_calc_lt_agg")
    Sys.sleep(60*20)

    check_loc_results("combined_aggregated_lt",paste0(out_dir_lt_free,"/result"),prefix="",postfix=".csv")
    check_loc_results("combined_aggregated_lt",paste0(out_dir_lt_whiv,"/result"),prefix="",postfix=".csv")
    system(paste0("cp ",out_dir_lt_free,"/result/combined_aggregated_lt.csv ",
                  out_dir_lt_free,"/result/combined_aggregated_lt_v",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_lt_whiv,"/result/combined_aggregated_lt.csv ",
                  out_dir_lt_whiv,"/result/combined_aggregated_lt_v",new_upload_version,".csv"))

    ## Submit jobs to create summary 5q0 and 45q15 results for aggregate locations
    lowest <- data.table(get_locations(level="lowest"))
    aggs <- data.table(get_locations(level="all"))
    aggs <- unique(aggs[!location_id %in% unique(lowest[,location_id]),location_id])

    sdi_map <- data.table(get_locations(gbd_type="sdi"))
    sdi_locs <- unique(sdi_map[level==0,location_id])

    agg_countries <- c(aggs,sdi_locs)

    for(type in c("hiv_free","with_hiv")) {
      for(country in agg_countries) {
        qsub(paste0("calc_agg_qx_",country,"_",type),paste0(code_dir,"/02d_calc_agg_qx.R"), slots = 4,  pass=list(country,type), proj="proj_mortenvelope", submit = !test, log = T)
      }
    }
    
    ## Check for results before compiling
    check_loc_results(agg_countries,paste0(out_dir_lt_free,"/mean_qx"),prefix="mean_45q15_agg_",postfix=".csv")
    check_loc_results(agg_countries,paste0(out_dir_lt_whiv,"/mean_qx"),prefix="mean_45q15_agg_",postfix=".csv")
    
    ## Compile mean 5q0 and 45q15 output
    file.remove(paste0(out_dir_products,"/child_mortality/mean_5q0_hivdel.csv"))
    file.remove(paste0(out_dir_products,"/child_mortality/mean_5q0_whiv.csv"))
    file.remove(paste0(out_dir_products,"/adult_mortality/mean_45q15_hivdel.csv"))
    file.remove(paste0(out_dir_products,"/adult_mortality/mean_45q15_whiv.csv"))
    
    system(paste0("sh ",code_dir,"/combine_5q0_45q15.sh"))
    
    ## Create copies of the qx summary files for people to use them easily later
    system(paste0("cp ",out_dir_products,"/child_mortality/mean_5q0_hivdel.csv ",
                  out_dir_products,"/child_mortality/mean_5q0_hivdel_",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_products,"/child_mortality/mean_5q0_whiv.csv ",
                  out_dir_products,"/child_mortality/mean_5q0_whiv_",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_products,"/adult_mortality/mean_45q15_hivdel.csv ",
                  out_dir_products,"/adult_mortality/mean_45q15_hivdel_",new_upload_version,".csv"))
    system(paste0("cp ",out_dir_products,"/adult_mortality/mean_45q15_whiv.csv ",
                  out_dir_products,"/adult_mortality/mean_45q15_whiv_",new_upload_version,".csv"))
  }

  


