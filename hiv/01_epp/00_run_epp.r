# Grant Nguyen
# June 22 2015
# Launch all stages of off-ART process

# Set up
rm(list=ls())

if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  code_dir <- paste0("/ihme/code/mortality/",user,"/hiv")
} else {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("C:/Users/",user,"/Documents/Git/hiv")
}


# Set toggles
  run_on_art <- T # Note: Make sure on_art launch script has appropriate toggles set
  run_no_art <- T # Note: Make sure no_art launch script has appropriate toggles set
  run_epp <- T
  epp_start <- 1
  epp_end <- 4
  test <- F

# Add run date and comments
  run_date <- gsub("-","",Sys.Date()) # Format: 20160126 aka yyyymmdd
  run_date <- substr(run_date,3,8) # Changes format to 160126 aka yymmdd
  run_comment <- "Echo_1"
  run_name <- paste0(run_date,"_",run_comment)

# Point to the current iso3 file
  iso3_file_date <- "160404"
  spectrum_file_date <- "151207" # For prep_epp_data

# Set list of countries to run
  country_list <- read.csv(paste0(root,"/strPath/EPP_countries_",iso3_file_date,".csv"),stringsAsFactors=F)
  run_countries <- unique(country_list$iso3)

# Set list of countries to look for in on- and off- ART processes
  source(paste0(root,"/strPath/get_locations.r"))
  art_file <- get_locations()
  art_locations <- unique(art_file$ihme_loc_id)
  
# Set folders for RankedDraws input and output
  param_dir <- paste0(root,"/strPath/transition_parameters")
  duration_dir <- paste0(param_dir,"/DurationCD4cats")
  no_art_dir <- paste0(param_dir,"/HIVmort_noART")
  on_art_dir <- paste0(param_dir,"/HIVmort_onART_regions")

# Set folders for EPP input and output
  epp_in_dir <- paste0("/strPath/",run_name)
  epp_out_dir <- paste0("/strPath/",run_name)

# Set Draws for run_epp_parallel
  num_draws <- 1000 # 1000 is standard


## ###############################################################
## Set up QSUB function and results checking function
source(paste0(code_dir,"/strPath/qsub.R"))
source(paste0(root,"/strPath/check_loc_results.r"))


##################################################################
## Make appropriate directories if they don't already exist
## Delete pre-existing outputs, to ensure that jobs don't run on old data
if(run_no_art == T) {
  system(paste0("perl -e 'unlink <",duration_dir,"/current_draws/*.csv>' "))
  system(paste0("perl -e 'unlink <",no_art_dir,"/current_draws/*.csv>' "))
}
if(run_on_art == T) {
  system(paste0("perl -e 'unlink <",on_art_dir,"/DisMod/*.csv>' "))
}
if (epp_start<=1 & run_epp == T) {
  system(paste0("mkdir ",duration_dir,"/",run_date,"_ranked"))
  system(paste0("mkdir ",no_art_dir,"/",run_date,"_ranked"))
  system(paste0("mkdir ",on_art_dir,"/",run_date,"_ranked"))

  system(paste0("perl -e 'unlink <",duration_dir,"/",run_date,"_ranked/*.csv>' "))
  system(paste0("perl -e 'unlink <",no_art_dir,"/",run_date,"_ranked/*.csv>' "))
  system(paste0("perl -e 'unlink <",on_art_dir,"/",run_date,"_ranked/*.csv>' "))

}

if (epp_end >= 2 & epp_start <= 2 & run_epp == T) {
  system(paste0("mkdir ",epp_in_dir))
  do.call(function(x) system(paste0("rm ",epp_in_dir,"/",x,"/*.RData>' ")), 
          list(run_countries))
}

if (epp_end >= 3 & epp_start <= 3 & run_epp == T) {
  system(paste0("mkdir ",epp_out_dir))
  for(country in run_countries) {
    dir.create(paste0(epp_out_dir,"/",country))
    system(paste0("perl -e 'unlink <",epp_out_dir,"/",country,"/results*.csv>' "))
    system(paste0("perl -e 'unlink <",epp_out_dir,"/",country,"/test_results*.pdf>' "))
  }
}

if (epp_start <=4 & epp_end >= 4 & run_epp == T) {
  system(paste0("mkdir ",duration_dir,"/",run_date,"_paired"))
  system(paste0("mkdir ",no_art_dir,"/",run_date,"_paired"))
  system(paste0("mkdir ",on_art_dir,"/",run_date,"_paired"))
  
  system(paste0("perl -e 'unlink <",duration_dir,"/",run_date,"_paired/*.csv>' "))
  system(paste0("perl -e 'unlink <",no_art_dir,"/",run_date,"_paired/*.csv>' "))
  system(paste0("perl -e 'unlink <",on_art_dir,"/",run_date,"_paired/*.csv>' "))
  
  system(paste0("mkdir ",root,"/strPath/",run_name))
  system(paste0("mkdir ",root,"/strPath/",run_name)) 
}

##################################################################
## Launch and check on- and off-ART processes
if (run_no_art == T) {
  setwd(paste0(code_dir,"/no_art"))
  qsub("no_art_launch", paste0(code_dir,"/no_art/00_run_all.r"), slots = 2, submit=!test)
}
if (run_on_art == T) {
  setwd(paste0(code_dir,"/on_art"))
  qsub("on_art_launch", paste0(code_dir,"/on_art/master.do"), slots = 2, submit=!test)
}

## Check that the on and off-ART draws exist
  if (run_on_art == T | run_no_art == T) {
    print("Waiting 10 minutes before starting to check files")
    Sys.sleep(600)
  }
  print("Checking Duration draws")
  check_loc_results(art_locations,paste0(duration_dir,"/current_draws"),prefix="",postfix="_progression_par_draws.csv")
  print("Checking No-ART draws")
  check_loc_results(art_locations,paste0(no_art_dir,"/current_draws"),prefix="",postfix="_mortality_par_draws.csv")
  print("Checking On-ART draws")
  check_loc_results(art_locations,paste0(on_art_dir,"/DisMod"),prefix="",postfix="_HIVonART.csv")

##################################################################
## Launch the EPP code
setwd(paste0(code_dir,"/EPP"))

if (epp_start<=1 & run_epp == T) {
  qsub("epp_01", paste0(code_dir,"/EPP/RankDraws.R"),pass=list(run_date,iso3_file_date),slots=2,submit=!test)
  
  # Check for output from RankDraws
  check_loc_results(run_countries,paste0(duration_dir,"/",run_date,"_ranked"),prefix="",postfix="_progression_par_draws.csv")
  check_loc_results(run_countries,paste0(no_art_dir,"/",run_date,"_ranked"),prefix="",postfix="_mortality_par_draws.csv")
  check_loc_results(run_countries,paste0(on_art_dir,"/",run_date,"_ranked"),prefix="",postfix="_HIVonART.csv")
}

if (epp_start<=2 & epp_end >= 2 & run_epp == T) {
  ran_ZAF <- FALSE
  for (iso3 in run_countries) {
  # for(iso3 in "AGO") {
    prep_epp <- paste0("qsub -P proj_hiv -pe multi_slot 8 ",
                       "-e /share/temp/sgeoutput/",user,"/errors ",
                       "-o /share/temp/sgeoutput/",user,"/output ",
                       "-N ",iso3,"_prep_epp ",code_dir,"/EPP/shell_R.sh ",
                       code_dir,"/EPP/prep_epp_data.R ",
                       iso3, " ", run_date," ",run_name," ",spectrum_file_date)
    print(prep_epp)
    if (!grepl('ZAF_', iso3) | !ran_ZAF)
      system(prep_epp)
    if (grepl('ZAF_', iso3) & !ran_ZAF)
      ran_ZAF <- TRUE
  }
  
  # Check for output from launch_prep_data step
  for(loc in run_countries) {
    print(paste0("Checking ",loc))
    check_loc_results(1:num_draws,paste0(epp_in_dir,"/",loc),prefix="data_for_jeff_epp_",".RData") 
  }
}

n_jobs <- 0

for(iso3 in run_countries) {
  if(epp_start <= 3 & epp_end >= 3 & run_epp == T) {    
    tmp_model <- unique(country_list$model[country_list$iso3 == iso3])
    Sys.sleep(3)
    for (i in 1:num_draws) {
      prep_epp <- paste0("qsub -o /dev/null -e /dev/null -P proj_hiv -pe multi_slot 6 -N ",
                         iso3,"_epp_",i,
                         " ",code_dir,"/EPP/shell_R.sh ",
                         code_dir,"/EPP/run_epp_parallel.R ",
                         tmp_model," ",i," ", iso3," ",run_name)
      print(prep_epp)
      system(prep_epp)
      n_jobs <- n_jobs + 1
    }
  }
  
  if (epp_start<=4 & epp_end >= 4 & run_epp == T) {
    # Create holds if we ran 03
    if(epp_start < 4) {
      job_list <- NULL
      for(n in 1:num_draws) {
        job_list <- c(job_list,paste0(iso3,"_epp_",n))
      }
    }
    qsub(paste0("epp_04_",iso3), paste0(code_dir,"/EPP/save_paired_draws.R"),pass=list(iso3,run_date,run_name,num_draws),hold=ifelse(epp_start<4,paste(job_list,collapse=","),"fakejob"),slots=2,submit=!test)
    n_jobs <- n_jobs + 1
  }
}
if(epp_end >= 3) sprintf('Launched %i jobs', n_jobs)



