## MASTER CODE TO SWAP IN NEW PREVALENCE ESTIMATES FOR ALCOHOL (PRE-CAPPING)

rm(list=ls()); library(foreign)

if (Sys.info()[1] == 'Windows') {
  root <- "J:/"
} else {
  root <- "/home/j/"
}

test <- F
setwd(paste0(root,"WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models"))
version <- "v_3-16_nobingere2"

## get geographic units
countries <- read.csv(paste0(root,"WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/intermediate/alc_data_1990.csv"),stringsAsFactors=F)
countries <- unique(countries$REGION)
## get years
years <- c(1990,1995,2000,2005,2010,2013)


## define qsub stuff
qsub <- function(jobname, code, hold=NULL, pass=NULL, slots=1, submit=F) {
  # choose appropriate shell script
  if(grepl(".R", code, fixed=T)) shell <- "r_shell.sh" else if(grepl(".py", code, fixed=T)) shell <- "python_shell.sh" else shell <- "stata_shell.sh"
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
  sub <- paste("/usr/local/bin/SGE/bin/lx24-amd64/qsub -cwd",
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

for (i in years) {
  qsub(paste("sub_prev_", i, sep=""), "new_prev_parallel.R", "fake_none" ,list(paste0(i," ",version)),slots=4, submit=!test)
}


