
############
## Settings
############

  rm(list=ls()); library(foreign)
  if (Sys.info()[1] == 'Windows') {
    username <- "StrUser"
    root <- "StrPath"
    workdir <-  paste("StrPath",username,"/StrPath/",sep="")
    source("StrPath/get_locations.r")
  } else {
    username <- Sys.getenv("USER")
    root <- "StrPath"
    workdir <- paste("StrPath",username,"/StrPath/",sep="")
    source("StrPath/get_locations.r")
  }
  
  print(paste0(workdir))
  test <- F         
  start <- 3         
  fin <- 3
  use_ctemp <- 1
  err_out <- T

  ## get locations
  codes <- get_locations(level="estimate")
  ihme_loc_id <- codes$ihme_loc_id[codes$level_all == 1]

############
## Define qsub function
############

  qsub <- function(jobname, code, hold=NULL, pass=NULL, slots=1, submit=F) {
    if(grepl(".r", code, fixed=T)) shell <- "r_shell.sh" else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh" else shell <- "stata_shell.sh"
    if (slots > 1) {
      slot.string = paste(" -pe multi_slot ", slots, sep="")
      mem.string = paste0(" -l mem_free=",slots*2)
    }
    if (!is.null(hold)) {
      hold.string <- paste(" -hold_jid \"", hold, "\"", sep="")
    }
    if (!is.null(pass)) {
      pass.string <- ""
      for (ii in pass) pass.string <- paste0(pass.string, "\"", ii, "\"")
    }
    sub <- paste("qsub -cwd",
                 " -N ", jobname,
                 if (slots>1) slot.string,
                 if (slots>1) mem.string,
                 if (!is.null(hold)) hold.string,
                 " ",shell, " ",
                 code, " ",
                 if (!is.null(pass)) pass.string,
                 sep="")
    if (submit) {
      system(sub)
    } else {
      cat(paste("\n", sub, "\n\n "))
      flush.console()
    }
  }

############
## Delete all current output files (this is force the code to break if any individual piece breaks)
############

  if (!test) {
    setwd("StrPath")
    if (start<=1 & fin >=1) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=2 & fin >=2) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=3 & fin >=3) for (ff in dir("results")) if(ff!="archive") file.remove(paste("results/", ff, sep=""))
    if (start<=4 & fin >=4) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=5 & fin >=5) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    
    setwd("StrPath")
    if (start<=2 & fin >=2) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=3 & fin >=3) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=3 & fin >=3) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
    if (start<=4 & fin >=4) for (ff in dir("StrPath")) if(ff!="archive") file.remove(paste("StrPath/", ff, sep=""))
  }

  setwd(workdir)

############
## Submit jobs
############

errout <- paste0("-o /share/temp/sgeoutput/",username,
                 "/output -e /share/temp/sgeoutput/",username,"/errors")

  if (start<=1 & fin >=1) {
    jname <- "as01"
    slots <- 2
    mem <- slots*2
    holds <- "m10"
    sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
    args <- paste0(username)
    shell <- "stata_shell.sh"
    script <- "01_compile_data.do"
    print(paste(sys.sub, shell, script, "\"", args, "\""))
    system(paste(sys.sub, shell, script, "\"", args, "\""))
  } 

  if (start<=2 & fin >=2) {
    slots <- 3
    mem <- slots*2
      jname <- paste0("as02_fit")
      holds <- "as01"
      sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
      args <- paste(workdir,use_ctemp,sep=" ")
      shell <- "stata_shell.sh"
      script <- "02_fit_models.do"
      print(paste(sys.sub, shell, script, "\"", args, "\""))
      system(paste(sys.sub, shell, script, "\"", args, "\""))
    }
  
  if (start<=3 & fin >=3) {
    slots <- 2
    mem <- slots*2
    holds <- paste("-hold_jid \"",paste(c("as02_fit"),collapse=","),"\"",sep="")
    jobids <- NULL
    
    library(RMySQL)
		myconn <- dbConnect(RMySQL::MySQL(), host="StrDb", username="StrUser", password="StrPassword") 
		sql_command <- paste0("SELECT output_version_id FROM cod.output_version WHERE best_end IS NULL AND best_start IS NOT NULL;")
		output_version_id <- dbGetQuery(myconn, sql_command)
		dbDisconnect(myconn)
    
    for (i in 1:length(ihme_loc_id)) {
      loc <- ihme_loc_id[i]
      jname <- paste0("as03_",loc)
      sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G ",holds," ")
      args <- paste0(workdir," ",loc," ",use_ctemp," ",codes$location_id[codes$ihme_loc_id == loc]," ",output_version_id)
      shell <- "stata_shell.sh"
      script <- "03_apply_shocks_and_model_coefficients.do"
      system(paste(sys.sub, shell, script, "\"", args, "\""))  
      jobids <- c(jobids,jname)
    }
  }

  if (start<=4 & fin >=4) {
    if (start > 3) jobids <- "03fakejob"
    jname <- "as04_compile"
    slots <- 3
    mem <- slots*2
    holds <- paste("-hold_jid \"",paste(jobids,collapse=","),"\"",sep="")
    sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G ",holds," ")
    args <- paste0(workdir," ",use_ctemp)
    shell <- "stata_shell.sh"
    script <- "04_compile_estimates.do"
    system(paste(sys.sub, shell, script, "\"", args, "\""))
  }
    
  if (start <=5 & fin >=5) {  
    jname <- "as05_plot"
    slots <- 2
    mem <- slots*2
    holds <- "as04_compile"
    args <- "NONE"
    sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
    shell <- "r_shell.sh"
    script <- "05_plot_data_estimates_compare.r"
    system(paste(sys.sub, shell, script, "\"", args, "\""))
    
    jname <- "as05_plot_rats"
    slots <- 2
    mem <- slots*2
    holds <- "as04_compile"
    args <- "NONE"
    sys.sub <- paste0("qsub ",ifelse(err_out,paste0(errout),paste0(""))," -P proj_mortenvelope -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
    shell <- "r_shell.sh"
    script <- "05_plot_data_estimates_ratio.R"
    system(paste(sys.sub, shell, script, "\"", args, "\""))
    
  }

