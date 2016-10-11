################################################################################
## Date Created: 09 April 2012
## Description: Submit shells scripts to run all code necessary to produce 
##              estimates of adult mortality. This code must be run on the 
##              cluster and assumes that you have already done everything up
##              through compiling the data (i.e. producing 'raw.5q0_adjusted.txt'
################################################################################

############
## Settings
############
rm(list=ls()); library(foreign)

if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- ""
  code_dir <- ""
  source("get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- ""
  code_dir <- paste0("",username, "") # This is the username of the person running the code 
  setwd(code_dir)
  source("get_locations.r")
}

  test <- F               # if T, no files are deleted and no jobs are submitted.
  start <- 1             # code piece to start (1 to run whole thing)
  end <- 2

  #options for parameter selection - NOTE THAT num.holdouts NEEDS TO BE CHANGED IN 04 AS WELL
  parameter.selection <- F # should parameter selection be run? (if F, skips steps 4-7 regardless of start)
  num.holdouts <- 5      # this needs to be changed in 04 as well

  #these options are for the HIV sims - but the code isn't set up to do parameter selection and HIV sims at the same time, which would be way too many jobs
  errout <- T          # If T, it will create error and output files on the cluster.
                        #Only do this if the number of HIV simulations is less than 100 (to be safe).
  delete_errout <- F
  runisos <- NULL   # set this = NULL if you want to run all countries. Otherwise, make it a c() of the iso3s you want to run e.g. c("ZAF","USA") or c("TUR")
  hivsims <- 0      #F if only one set of hiv numbers, T if running all 5q0 multiple times for multiple hiv numbers
    
  save_prerake <- 1   # decide whether or not to save sims of preraked subnationals
  
  codes <- get_locations()
  codes <- codes[codes$level_all != 0,]
  codes <- codes[!duplicated(codes$ihme_loc_id),c("ihme_loc_id","region_name")]
  names(codes) <- c("ihme_loc_id","gbd_region")
  codes <- codes[order(codes$gbd_region, codes$ihme_loc_id),]
  codes$gbd_region <- gsub(" ", "_", codes$gbd_region)

  ## If just running a subset of countries, keep only those
  if (!is.null(runisos)) codes <- codes[codes$ihme_loc_id %in% runisos,]

############
## Define qsub function
############

  qsub <- function(jobname, code, hold=NULL, pass=NULL, submit=F) { 
    # choose appropriate shell script 
    # if(code == "13_graph_5q0_compstage.r") shell <- "r_shell_email.sh" else if(grepl(".r", code, fixed = T) | grepl(".R",code,fixed = T)) shell <- "r_shell.sh " else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh " else shell <- "stata_shell.sh "
    if(grepl(".r", code, fixed = T) | grepl(".R",code,fixed = T)) shell <- "r_shell.sh" else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh" else shell <- "stata_shell.sh" 
	# set up jobs to hold for 
    if (!is.null(hold)) { 
      hold.string <- paste(" -hold_jid \"", hold, "\"", sep="")
    } 
    # set up arguments to pass in 
    if (!is.null(pass)) { 
      pass.string <- ""
      for (ii in pass) pass.string <- paste(pass.string, " \"", ii, "\"", sep="")
    }
    #For 
    parallel <- NULL
    if(grepl(".py",code,fixed = T)) {
      parallel <- " -pe multi_slot 9"
    } else {
      parallel <- " -pe multi_slot 8"
    }
    # construct the command
	sub <- paste("qsub -cwd", ifelse(errout,paste0(" -o sgeoutput/",username,"/output -e sgeoutput/",username,"/errors")," -o [output_dir] -e [error_dir]"), 
			 if (!is.null(hold)) hold.string,
			 if (!is.null(parallel)) parallel,
			 " -N ", jobname, " ",
			 " -P [project_name] ",
			 shell, " ",
			 code, " ",
			 if (!is.null(pass)) pass.string,
			 sep="")				 

    # submit the command to the system
    if (submit) {
      system(sub) 
    } else {
      cat(paste("\n", sub, "\n\n "))
      flush.console()
    } 
  } 

#################
## First, make sure that the error and output files on the cluster are clear (only if we are saving error and outputs)
#################
if (delete_errout) {
  if (errout) {
    ## delete all error and output files
    system(paste("find sgeoutput/",username, "/ -type f -exec rm -f {} \\;", sep=""))
    
    ## wait until they are all deleted
    while (!length(list.files(paste("sgeoutput/",username,"/errors",sep=""))) == 0) {
      while (!length(list.files(paste("sgeoutput/",username,"/outputs",sep=""))) == 0) Sys.sleep(10)
    }
  }
}
  
############
## Delete all current output files
############

  if (!test) {
    if(hivsims){
      if (start<=1) for (ff in dir("")) file.remove(paste("",ff,sep=""))
      if (start<=1) for (ff in dir("",pattern="input")) file.remove(paste("",ff,sep=""))
      if (start<=2) for (ff in dir("",pattern="pred")) file.remove(paste("",ff,sep=""))
      if (start<=3) for (ff in dir("",pattern="gpr_5q0")) file.remove(paste("",ff,sep=""))
       setwd("")
       if (start<=4 & parameter.selection) for (ff in dir("inputs")) file.remove(paste("inputs/", ff, sep=""))
       if (start<=5 & parameter.selection) for (ff in dir("holdouts")) file.remove(paste("holdouts/", ff, sep=""))
       if (start<=6 & parameter.selection) for (ff in dir("gpr")) file.remove(paste("gpr/", ff, sep=""))
       if (start<=6 & parameter.selection) for (ff in dir("loss")) file.remove(paste("loss/", ff, sep=""))
       setwd("")
       if (start<=8) for (ff in dir("")[dir("") %in% c(paste0("gpr_",codes$ihme_loc_id,".txt"),paste0("gpr_",codes$ihme_loc_id,"_sim.txt"))]) file.remove(paste("gpr_files/final/", ff, sep=""))
       if (start<=8) for (ff in dir("")) file.remove(paste("",ff,sep=""))
    }else{
      setwd("")
      if (start<=1) file.remove("prediction_input_data.txt")
      if (start<=2) file.remove("prediction_model_results_all_stages_GBD2013.txt")
      if (start<=3) file.remove("gpr_5q0_input_GBD2013.txt")
    }

    setwd("")
   
    if (start <=8) for(ff in dir("/", pattern="gpr", full.names=T, include.dirs=F)) {file.remove(ff)}
	  if (start<=9) file.remove("prediction_model_results_all_stages.txt")
    if (start<=10) file.remove("gpr_5q0_input.txt")	
    if (start <=11) for(ff in dir("/", pattern="gpr", full.names=T, include.dirs=F)) {file.remove(ff)}
    
    setwd("")

    if (start<=12) file.remove("estimated_5q0_noshocks.txt")

  }
  
  setwd(code_dir)

###########################
#Run everything 250 times with different hiv draws
##########################

  #get all hiv draws
  hivdr <- read.csv("formatted_hiv_5q0_sim_level.csv", stringsAsFactors = F)
  nhiv <- max(hivdr$sim)
  
  ## testing
  if (test) nhiv <- 5

  ## if only one run - no hiv sims
  if(hivsims == F) nhiv <- 1
  
runids <- NULL
for(rnum in 1:nhiv){
  
  ##save subset of hiv sim data to cluster directory
  if (start <= 1 & hivsims) write.csv(hivdr[hivdr$sim == rnum,], paste("",rnum,sep = ""))

############
## Format the data; Run the prediction model; Define the holdouts 
############
  setwd(code_dir)
  if (start<=1) qsub(paste0("m01_",rnum), "01_format_covariates_for_prediction_models.r", pass = list(rnum,hivsims,username), submit=!test)
  if (start<=2 & end >= 2) qsub(paste0("m02_",rnum), "02_fit_prediction_model.r", hold = paste0("m01_",rnum), pass = list(rnum,hivsims,username), submit=!test)
  setwd(code_dir)
  if (start<=3 & end >= 3) qsub(paste0("m03_",rnum), "03_calculate_data_variance.do", hold = paste0("m02_",rnum), pass = paste(rnum,as.numeric(hivsims),sep = "-"), submit=!test)

  if (parameter.selection) {
    if (start<=4 & end >=4) qsub("m04", "04_define_holdouts.r", "m03", pass = list(username), submit=!test)

############
## Run second stage prediction model for each region-holdout
## Run GPR for each country-sex-holdout
############


    ## loop through regions, loop through holdouts: fit the second stage regression for each region-holdout
    for (rr in sort(unique(codes$gbd_region))) {
      jobids <- NULL
      count <- 0
      for (ho in 1:num.holdouts) {
        if (start<=5 & end >=5) qsub(paste("m05", rr, ho, sep="_"), "05_fit_second_stage_for_holdouts.r", "m04", list(rr, ho, username), submit=!test)
    ## within region-holdout, loop through country: fit GPR for each country holding for the second stage for the given region and holdout
        for (cc in sort(unique(codes$ihme_loc_id[codes$gbd_region == rr]))) {
           count <- count + 1
           if (start<=6 & end >=6) qsub(paste("m06", cc, ho, sep="_"), "06_fit_gpr_for_holdouts.py", paste("m05", rr, ho, sep="_"), list(username, rr, cc, ho), submit=!test)
           jobids[count] <- paste("m06", cc, ho, sep="_")
        }
      }
    ## generate a hold for each region 
      if (start<=6 & end >=6) qsub(paste("pause", rr, sep="_"), "pause.r", paste(jobids, collapse=","), submit=!test)
    }

############
## Select Parameters
############

    if (start<=7 & end >=7) qsub("m07", "07_select_parameters.r", paste(paste("pause", sort(unique(codes$gbd_region)), sep="_"), collapse=","), submit=!test)
  }

#
##############
#### Run GPR for each country
##############

#GPR seed in 08 is 123456
  jobids <- NULL
  count <- 0
  for (rr in sort(unique(codes$gbd_region))) {
    for (cc in sort(unique(codes$ihme_loc_id[codes$gbd_region == rr]))) {
        count <- count + 1
        if (start<=8 & end >= 8) qsub(paste("m08",rnum, cc, sep="_"), "08_fit_gpr.py", paste("m03_",rnum, sep = ""), list(rr, cc, rnum, hivsims, username), submit=!test)
        jobids[count] <- paste("m08",rnum, cc, sep="_")
    }
  }
  
  if (start<=9 & end >= 9) qsub(paste("m09_",rnum, sep = ""), "09_fit_prediction_model_new_locs.r", paste("m03_",rnum, sep = ""), pass = list(rnum,hivsims,username), submit=!test)
  if (start<=10 & end >= 10) qsub(paste("m10_",rnum, sep = ""), "10_calculate_data_variance_new_locs.do", paste("m09_",rnum, sep = ""), pass = paste(rnum,as.numeric(hivsims),sep = "-"), submit=!test)

#GPR seed in 11 is 123456


  jobids <- NULL
  count <- 0
  for (rr in sort(unique(codes$gbd_region))) {
    for (cc in sort(unique(codes$ihme_loc_id[codes$gbd_region == rr]))) {
        count <- count + 1
        if (start<=11 & end >= 11) qsub(paste("m11",rnum, cc, sep="_"), "11_fit_gpr_new_locs.py", paste("m10_",rnum, sep = ""), list(rr, cc, rnum, hivsims, username), submit=!test)
        jobids[count] <- paste("m11",rnum, cc, sep="_")
    }
  }
  
################
#### Create pause so dependencies are easier for compile code
################

  if (start <= 8.25 & end >= 8.25 & hivsims) qsub(paste("pause", rnum, sep="_"), "pause.r", paste(jobids, collapse=","), submit=!test)
  runids[rnum] <- paste("pause", rnum, sep="_")

} ##END SIMS LOOP
#########################################################################################################

############
## Compile GPR results
############

if(hivsims){
  names <- NULL
  seed <- 1
  for (cc in sort(unique(codes$ihme_loc_id))) {
    if (start<=8.5 & end >=8.5) qsub(paste("m085",cc,sep="_"), "085_compile_final_sims.r", hold=paste(runids, collapse=","),
                                                   pass=list(cc, seed), submit=!test)
    names <- c(names,paste("m085",cc,sep="_"))
    seed <- seed + 1
  }
}

if (start<=12 & end >=12) qsub("m12", "12_compile_gpr_results.R", hold=ifelse(hivsims, paste(names, collapse=","),paste(jobids, collapse = ",")), pass=list(save_prerake,username), submit=!test)

###################
###### Graph results
###################
#
if (start<=13 & end >=13) qsub("m13", "13_graph_5q0_compstage.r", "m12", submit=!test)

