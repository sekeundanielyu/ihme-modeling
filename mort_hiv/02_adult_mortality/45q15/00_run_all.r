################################################################################
## Description: Submit shells scripts to run all code necessary to produce 
##              estimates of adult mortality. This code must be run on the 
##              cluster and assumes that you have already done everything up
##              through compiling the data (i.e. producing 'raw.45q15.txt')
################################################################################

############
## Settings
############
  
  rm(list=ls()); library(foreign)

  test <- F             # if T, no files are deleted and no jobs are submitted

  start <- 1           # code piece to start at (1 to run whole thing; note that 3-6 will always be skipped if param.selection is F) 
  end <- 9              # piece of code to end at

  
  param.selection <- F  ## if T, parameter selection (steps 3-6) are run, otherwise these are skipped and old parameters are used 
  hiv.uncert <- 1       ## 1 or 0 logical for whether we're running with draws of HIV
  hiv.update <- 1       ## Do you need to update the values of the hiv sims? Affects 01b
  num.holdouts <- 100
  hivdraws <- 250         ## How many draws to run, must be a multiple of 25 (for job submission)
  if (hiv.uncert == 0) hivdraws <- 1
  hivscalars <- 1  # use scalars for HIV
  #these options are for the HIV sims - but the code isn't set up to do parameter selection and HIV sims at the same time, which would be way too many jobs

  if (Sys.info()[1] == "Linux") root <- "/home/j" else root <- "J:"
  user <- Sys.getenv("USER") # Default for linux user grab. "USERNAME" for Windows
  code_dir <- paste0("strPath")
  data_dir_uncert <- paste0("strPath")
  data_dir <- paste0("strPath")
  source(paste0("strPath/get_locations.r"))

  ## get countries we want to produce estimates for
  codes <- get_locations(level = "estimate")
  codes <- codes[codes$level_all == 1,] # Eliminate those that are estimates but that are handled uniquely (ex: IND six minor territories)
  codes$region_name <- gsub(" ", "_", gsub(" / ", "_", gsub(", ", "_", gsub("-", "_" , codes$region_name))))
  codes <- merge(codes, data.frame(sex=c("male", "female")))
  codes <- codes[order(codes$region_name, codes$ihme_loc_id, codes$sex),]

############
## Define qsub function
############

  qsub <- function(jobname, code, hold=NULL, pass=NULL, slots=1, submit=F, log=T) { 
    # choose appropriate shell script 
    if(grepl(".r", code, fixed=T) | grepl(".R", code, fixed=T)) shell <- "r_shell.sh" else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh" else shell <- "stata_shell.sh" 
    # set up number of slots
    if (slots > 1) { 
      slot.string = paste(" -pe multi_slot ", slots, sep="")
    } 
    # set up jobs to hold for 
    if (!is.null(hold)) { 
      hold.string <- paste(" -hold_jid \"", hold, "\"", sep="")
    } 
    # set up arguments to pass in 
    if (!is.null(pass)) { 
      pass.string <- ""
      for (ii in pass) pass.string <- paste(pass.string, " \"", ii, "\"", sep="")
    }  
    # construct the command 
    sub <- paste("qsub",
                 if(log==F) " -e /dev/null -o /dev/null ",  # don't log (if there will be many log files)
                 if(log==T) paste0(" -e /share/temp/sgeoutput/",user,"/errors -o /share/temp/sgeoutput/",user,"/output "),
                 ifelse(param.selection,paste0(" -P proj_param_select "), paste0(" -P proj_hiv ")),
                 if (slots>1) slot.string, 
                 if (!is.null(hold)) hold.string, 
                 " -N ", jobname, " ",
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
  
############
## Delete all current output files (this forces the code to break if any individual piece breaks) 
############

  if (!test) { 
    setwd(data_dir)
    
    if (start<=1 & end >=1) {
      file.remove("raw.45q15.txt")
      file.remove("input_data.txt")
    }

    if (hiv.uncert != 1) {
      if (start<=2 & end >=2 ) file.remove("strPath/first_stage_regressions.rdata")
      if (param.selection == T) {
        if (start<=3 &  end >=3) system("rm strPath/*.txt")
        if (start<=4 & end >=4) system("rm strPath/*.txt")
      }
      if (start<=7 & end >=7 ) system("rm strPath/prediction_model_results_all_stages.txt")   
      if (start<=7.5 & end >=7.5) system("rm strPath/*.txt")
    } ## END CONDITIONAL FOR IF NOT DOING HIV SIMS
    
    if (hiv.uncert == 1) {
      setwd(data_dir_uncert)
      if (start<=1 & end >=1) system("rm strPath/sim*.csv")
      if (start<=2 & end >=2) system("rm strPath/first_stage_regressions*.rdata")
      if (start<=2 & end >=2) system("rm strPath/first_stage_results*.csv")
      if (start<=2 & end >=2) system("rm strPath/45q15_HIV_coeff.csv")
      if (hiv.uncert & param.selection) print("You've asked to do parameter selection and hiv sims...does not compute")
      stopifnot(!(hiv.uncert == 1 & param.selection == T))
      if (start<=7 & end >=7 ) system("rm strPath/prediction_model_results_all_stages*.txt")   
      if (start<=7.5 & end >=7.5) system("rm strPath/*.txt")
      if (start <= 7.75 & end >=7.75) system("rm strPath/*.txt")
    }

    setwd(paste0(data_dir,"/../results/"))
    if (start<=6 & end >=6  & param.selection) file.remove("selected_parameters.txt")
    if (start<=8 & end >=8 ) {
      file.remove("estimated_45q15_noshocks.txt")
      file.remove("estimated_45q15_noshocks_wcovariate.txt")
    }
    
  }
  
   setwd(code_dir)

############
## Format the data; Run the prediction model; Define the holdouts 
############
  if (start<=1 & end >=1) {
    qsub("am01a", paste0(code_dir,"/01a_compile_all_adult_sources.do"), slots=5,submit=!test)
    qsub("am01b", paste0(code_dir,"/01b_format_data.r"), "am01a",pass=list(hiv.uncert,hiv.update,hivscalars), slots=5,submit=!test)
  }
  
  if (start<=2 & end >=2) {
    for (i in 1:(hivdraws)) {
      qsub(paste("am02",i,sep="_"), paste0(code_dir,"/02_fit_prediction_model.r"), "am01b",pass=list(i,hiv.uncert), slots=5, submit=!test)
    }
  }
  if (param.selection) { 
    if (start<=3 & end >=3) qsub("am03", paste0(code_dir,"/03_define_holdouts.r"), paste0("am02_",hivdraws), list(num.holdouts), submit=!test)
  
    # ############
    # ## Run second stage prediction model for each region-holdout
    # ## Run GPR for each country-sex-holdout
    # ############
    if ((start <= 4 & end >=4) | (start<=5 & end >= 5)) {
    
    ## loop through regions, loop through holdouts: fit the second stage regression for each region-holdout
      for (ho in 1:num.holdouts) {     # First forloop for hos so that it spaces out the bulk submissions from big regions (S Asia)
      #for (ho in 1:1) {  # test line
        ## give cluster a 30 second rest between submitting the jobs for each holdout set
  
        for (rr in sort(unique(codes$region_name))){
          jobids <- NULL 
          count <- 0 
          if (start<=4 & end >=4) qsub(paste("am04", rr, ho, sep="_"), paste0(code_dir,"/04_fit_second_stage_for_holdouts.r"), hold = "am03", pass = list(rr, ho), slots=4, submit=!test)
        }
            
        for (rr in sort(unique(codes$region_name))){
          ## within region-holdout, loop through country and sex: fit GPR for each country-sex holding for the second stage for the given region and holdout
          for (cc in sort(unique(codes$ihme_loc_id[codes$region_name == rr]))) {
           
            # these parameters must also be set in 04 step (in 04 step it must cover all possibilities but doesn't have to be restricted to just the ones we are testing in this stage)
            zetas <- c(.7, .8, .9, .99)
            lambdas <- seq(.1, .9, .1)

            for(zeta in zetas){
              for(lambda in lambdas){
                count <- count + 1
                # only log the first holdout so we can look at errors
                if (start<=5 & end >=5) qsub(paste("am05", cc, ho, lambda, zeta, sep="_"), paste0(code_dir,"/05_fit_gpr_for_holdouts.py"), hold = paste("am04", rr, ho, sep="_"), pass = list(rr, cc, ho, lambda, zeta), slots=4, submit=!test, log=ifelse(ho==1,T,F))
                jobids[count] <- paste("am05", cc, ho, lambda, zeta, sep="_")
                
                ## to deal with errors that may arise by overloading the job scheduler, we let it breathe for 10 seconds every 500 jobs
                if (count %% 2000 == 0) Sys.sleep(10)  
              }
            }
           }
          ## generate a hold for each region-holdout (these jobs don't really do anything, they just split up the holds so that there aren't tens of thousands of holds the next job) 
          if (start<=5 & end >=5) qsub(paste("am_pause", rr,ho, sep="_"), paste0(code_dir,"/pause.r"), hold = paste(jobids, collapse=","), submit=!test)
        }
      } 
    } # End step 4 submission

    ############
    ## Select Parameters
    ############
    if (start <= 5 & end >=5) {
      pause_names <- paste("am_pause", sort(unique(codes$region_name)), sep="_")
      pn <- NULL
      for (hn in 1:num.holdouts) pn <- c(pn,paste(pause_names,hn,sep="_")) 
    } else pn <- "nothing"
    
    count <- 0
    jobids <- NULL
    #countries <-  unique(codes$ihme_loc_id)
   # countries = c("ARE", "BGD", "BOL", "CPV", "DNK", "HND", "IND_43875", "IND_43877", "IND_43880", "IND_43886", "IND_43890", "IND_43911", "IND_43913", "IND_43916", "IND_43922", "IND_43926", "IND_4844", "IND_4846", "IND_4849", "IND_4855", "IND_4859", "IRQ", "JOR", "KIR", "LBY", "MDG", "MNE", "OMN", "PSE", "SAU_44543", "SRB", "STP", "SYR", "TON", "WSM", "ZAF", "ZAF_482", "ZAF_483", "ZAF_484", "ZAF_485", "ZAF_486", "ZAF_487", "ZAF_488", "ZAF_489", "ZAF_490", "ZWE")
    #countries <- grep("ZAF", countries, value=T )
    countries <- c("BDI", "BEN", "BFA", "BTN", "CAF", "CIV","CMR", "COD", "COG",      
    "COM", "ERI","ETH","GAB","GHA","GIN", "GMB", "HTI", "IDN",      
    "KEN","KHM","LAO","LBN","LBR", "LSO","MAR", "MLI", "MOZ",      
    "MRT", "MWI", "NAM","NER", "NGA", "NPL", "RWA", "SDN", "SEN",      
    "SLE", "SWZ", "TCD","TGO","TLS","TZA","UGA", "ZMB","KEN_35617",
    "KEN_35618", "KEN_35619", "KEN_35621", "KEN_35623", "KEN_35624", "KEN_35625", "KEN_35626", "KEN_35627", "KEN_35628",
    "KEN_35629", "KEN_35630", "KEN_35631", "KEN_35632", "KEN_35633", "KEN_35634", "KEN_35635", "KEN_35636", "KEN_35637",
    "KEN_35638", "KEN_35639", "KEN_35640", "KEN_35641", "KEN_35642", "KEN_35643", "KEN_35644", "KEN_35645", "KEN_35646",
    "KEN_35647", "KEN_35648", "KEN_35649", "KEN_35650", "KEN_35651", "KEN_35652", "KEN_35653", "KEN_35654", "KEN_35655",
    "KEN_35656", "KEN_35657", "KEN_35658", "KEN_35659", "KEN_35660", "KEN_35661", "KEN_35663")
     for (cc in countries){
      count <- count + 1
      if (start<=6 & end >=6) qsub(paste("am06", cc, sep="_"), paste0(code_dir,"/06_select_parameters.r"), hold = paste(pn, collapse=","), pass=list(cc), slots=4, submit=!test)
      jobids[count] <- paste("am06", cc, sep="_")
    }

    if (start<=6 & end >=6) qsub("am06b", paste0(code_dir,"/06b_combine_selected_parameters.R"),  hold=paste(jobids, collapse=","), submit =!test)
  } # End parameter selection steps (3-6)

###########
## Run the second stage
###########
count <- 0
if (start<=7 & end >=7) {
  holdgpr <- NULL
  ## first launch step that saves first stage coefficients, doing here so holds present
  qsub(paste0("hivcoeff"), paste0(code_dir,"/save_coeffs_for_MLT.R"), hold=ifelse(param.selection, "am06b", paste("am02",c(1:250),sep="_",collapse=",")),slots = 1, submit=!test)
  
  
  for (i in 1:(hivdraws)) {
    count <- count + 1
    qsub(paste("am07a",i, sep="_"), paste0(code_dir,"/07a_fit_second_stage.R"), hold=ifelse(param.selection, "am06b", paste("am02",i,sep="_")),pass=list(i,hiv.uncert),slots = 2, submit=!test)
    holdgpr[count] <- paste("am07a",i,sep="_")
  }
}  


############
## Run GPR for each country-sex
############
  
  jobids <- NULL
  count <- 0 
  if(hivdraws == 1) {
    hhh <- 1
  } else {
    hhh <- hivdraws/25
  }
if (start<=7.5 & end >=7.5) {
  for (cc in sort(unique(codes$ihme_loc_id))) {
#  for (cc in sort(unique(c("USA_563")))) {
    for (i in 1:(hhh)) {
      count <- count + 1
      qsub(paste("am07b", cc,i, sep="_"), paste0(code_dir,"/07b_fit_gpr.py"), hold=ifelse(start < 7.5,paste(holdgpr,collapse=","),"fakejob"), list(cc,hiv.uncert,i),slots=3, 
           submit=!test,log=ifelse(hiv.uncert==1,ifelse(cc == "USA_563",T,F),T)) 
      jobids[count] <- paste("am07b", cc,i, sep="_")
      
    }
  }
}
 
############
## Compile GPR results
############

## if doing HIV sims, compile those gpr files first
if (hiv.uncert == 1) {
  jobidsh <- NULL
  count <- 0 
  if (start<=7.75 & end >=7.75) {
    for (cc in sort(unique(codes$ihme_loc_id))) {
    #for (cc in sort(unique(c("KEN")))) {
        count <- count + 1
        qsub(paste("am07c", cc, sep="_"), paste0(code_dir,"/07c_hivsim_gpr_compile.R"), hold=ifelse(start > 7.5,"fake_jobs",paste(jobids[grepl(cc,jobids)],collapse=",")), 
             list(cc,hivdraws/25), slots=6,submit=!test) 
        jobidsh[count] <- paste("am07c", cc, sep="_")
    }
  }
}

  
  if (start<=8 & end >=8) {
    count <- 0
    jobids2 <- NULL
    for(rr in unique(codes$region_id)) {
    # for(rr in 192) {
      count <- count + 1
      qsub(paste0("am08_",rr), paste0(code_dir,"/08_compile_gpr_results.r"), ifelse(start > 7.9,"no_holds",ifelse(hiv.uncert==1,paste(jobidsh,collapse=","),paste(jobids, collapse=","))), 
           slots=4, pass = list(rr,hiv.uncert), submit=!test)
      jobids2[count] <- paste0("am08_", rr)
    }
    qsub("am08b", paste0(code_dir,"/08b_compile_all.r"), paste(jobids2, collapse=","), slots=2, pass=list(hiv.uncert),submit=!test)
  }
##############                                  
## Make graphs
##############

  if (start<=9 & end >=9) qsub("am09", paste0(code_dir,"/09_graph_all_stages.r"), "am08b", pass = list(param.selection), submit=!test)

