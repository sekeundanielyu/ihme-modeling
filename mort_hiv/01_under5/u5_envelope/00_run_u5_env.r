## Launch under-5 envelope jobs

rm(list=ls()); library(foreign)
if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- ""
  workdir <-  paste("",username,"",sep="")
  source("get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- ""
  workdir <- paste("",username,"",sep="")
  source("get_locations.r")
}
 

locs <- get_locations(level="estimate")
locs <- locs[locs$level_all == 1,c("ihme_loc_id")]

start <- 1
fin <- 5
dopop <- 0 
test <- F
err_out <- T

errout_dir <- paste0("-o ",username," -e ",username,"/errors")

# 
if (!test) {
  

  setwd("")
  if (start<=1 & fin >=1) for (ff in dir("")) {
    if(ff!="archive") file.remove(paste("", ff, sep=""))  
  } 
  
  if (start<=4 & fin >=4) for (ff in dir("")) {
    if(ff!="archive" & grepl("allnonshocks",ff)) file.remove(paste("", ff, sep=""))  
  } 
  if (start<=5 & fin >=5) for (ff in dir("")) {
    if(ff!="archive" & grepl("deaths_sim_",ff)) file.remove(paste("", ff, sep=""))  
  } 
  
}

setwd(workdir)

## Launch u5 envelope files by geography
if (start <= 1 & fin >= 1) {
  slots <- 5
  mem <- slots*2
  holds <- "as04"
  jobids <- c()
  
  for (i in locs) {
    jname <- paste0("u5e_",i)
    sys.sub <- paste0("qsub ",ifelse(err_out,errout_dir,"")," -P [project_name] -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
    args <- paste0(i," ",workdir)
    shell <- "stata_shell.sh"
    script <- "01_u5envelope_loc.do"
    system(paste(sys.sub, shell, script, "\"", args, "\""))
    jobids <- c(jobids,jname)
  }
}

#####################################################################################################################
## 04_compile_sims.do 
#####################################################################################################################
if (start <=4 & fin >=4) {
  slots <- 10
  mem <- slots*2
  
  if (start < 4) {
    holds <- paste("-hold_jid \"",paste(jobids,collapse=","),"\"",sep="")
  } else {
    holds <- "-hold_jid \"nothing\""
  }

  jname <- paste0("u5e_compile")
  sys.sub <- paste0("qsub ",ifelse(err_out,errout_dir,"")," -P [project_name] -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G ",holds," ")
  args <- paste0(workdir)
  shell <- "stata_shell.sh"
  script <- "04_compile_sims.do"
  print(paste(sys.sub, shell, script, "\"", args, "\""))
  system(paste(sys.sub, shell, script, "\"", args, "\""))

}

######################################################################################################################
## 05_save_simfiles.do 
######################################################################################################################
if (start <=5 & fin >=5) {
  slots <- 9
  mem <- slots*2
  holds <- "u5e_compile"

for (i in 0:9) {  
  jname <- paste0("u5e_resave_",i)
  sys.sub <- paste0("qsub ",ifelse(err_out,errout_dir,"")," -P [project_name] -cwd -N ",jname," -pe multi_slot ",slots," -l mem_free=",mem,"G -hold_jid ",holds," ")
  args <- paste0(i," ",workdir)
  shell <- "stata_shell.sh"
  script <- "05_save_simfiles.do"
  print(paste(sys.sub, shell, script, "\"", args, "\""))
  system(paste(sys.sub, shell, script, "\"", args, "\""))
}
}

