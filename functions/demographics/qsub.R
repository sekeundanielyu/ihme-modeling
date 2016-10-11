############
## Define qsub function
############

## jobname: Name for job, must start with a letter
## code:    Filepath to code file
## hold:    Comma-separated list of jobnames to hold the job on
## pass:    List of arguments to pass on to receiving script
## slots:   Number of slots to use in job
## submit:  Should we actually submit this job?
## log:     Should this job create a log in /share/temp/sgeoutput/user/   output and errors?
## proj:    What is the project flag to be used?


qsub <- function(jobname, code, hold=NULL, pass=NULL, slots=1, submit=F, log=T, intel=F, proj = "proj_mortenvelope") { 
  user <- Sys.getenv("USER") # Default for linux user grab. "USERNAME" for Windows
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
               if(intel==T) paste0(" -l hosttype=intel "),
               if(proj != "") paste0(" -P ",proj," "),
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
