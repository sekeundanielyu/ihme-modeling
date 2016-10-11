# Allen Roberts
# February 2014
# Compartmental model of HIV no ART

# Set up
rm(list=ls())
library(stats)
library(utils)

if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  code_dir <- paste0("strPath")
} else {
  root <- "J:"
  user <- Sys.getenv("USERNAME")
  code_dir <- paste0("strPath")
}


# At the request of Greg
# source("/home/j/WORK/04_epi/01_database/02_data/hiv/01_lit/01_code/no_art/code/04d_call_comp_model.r")

root <- ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
setwd(code_dir)

## ###############################################################
## Set up QSUB function
qsub <- function(jobname, code, hold=NULL, pass=NULL, slots=1, submit=F) { 
  # choose appropriate shell script 
  if(grepl(".r", code, fixed=T)) shell <- "r_shell.sh" else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh" else shell <- "stata_shell.sh" 
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
  sub <- paste("/usr/local/bin/SGE/bin/lx24-amd64/qsub", 
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


##################################################################
## PARALLELIZE OPTIMIZATION FOR EACH STRATUM
##################################################################

ages <- c("15_25", "25_35", "35_45", "45_100")

for(age in unique(ages)) {
  qsub(paste0("hiv_04_",age), paste0(code_dir,"/04b_optimize.r"), pass = age, slots=5,submit=T)
}


# for(age in unique(ages)) {
#       
#     qsub <- "/usr/local/bin/SGE/bin/lx24-amd64/qsub -cwd -pe multi_slot 1 -l mem_free=5G"
#     shell <- "./code/04c_submit_opt.sh"
#     jname <- paste("-N run", age, date, "sample", sep="_")
#     sub <- paste(qsub, jname, shell, age, date, sep=" ")
#         
#     system(sub)
#         
# }


