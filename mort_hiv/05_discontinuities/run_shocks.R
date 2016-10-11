
############
## Settings
############

rm(list=ls()); library(foreign)

if (Sys.info()[1] == 'Windows') {
  username <- "StrUser"
  root <- "StrPath"
  source("StrPath/get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- "StrPath"
  code_dir <- paste("StrPath", username, "StrPath", sep="")  
  setwd(code_dir)
  source("/StrPath/get_locations.r")
}

test <- F             
start <-  1         
end <- 2 
errout <- T


r_shell <- "r_shell.sh"
stata_shell <- "stata_shell.sh"
stata_shell_mp <- "stata_shell_mp.sh"
errout_paths <- paste0("-o StrPath",username,
                       "StrPath",username,"/StrPath ")
proj <- "-P proj_mortenvelope "



locations <- get_locations(level="all")
locations2 <- get_locations(level="all", gbd_type = "sdi") 
locations <- rbind(locations,locations2[!locations2$location_id %in% unique(locations$location_id),])


                         
library(RMySQL)
myconn <- dbConnect(RMySQL::MySQL(), host="Strdb", username="StrUser", password="StrPwd") 
sql_command <- paste0("SELECT shock_version_id FROM cod.shock_version WHERE gbd_round_id = 3 AND shock_version_status_id = 1;")
output_version_id <- dbGetQuery(myconn, sql_command)
dbDisconnect(myconn)


myconn <- dbConnect(RMySQL::MySQL(), host="Strdb", username="StrUser", password="StrPwd") 
sql_command <- paste0("SELECT MAX(output_version_id) ",
                      "FROM mortality.output_version ")
max_version <- dbGetQuery(myconn, sql_command)
dbDisconnect(myconn)
version <- max_version[1][[1]] 





env_dir <- "StrPath"
setwd(env_dir)
if (start <= 1 & test==F) for (ff in dir(env_dir)) file.remove(paste0(ff)) 

lt_dir <- "StrPath"
setwd(lt_dir)
if (start <= 1 & test==F) for (ff in dir(lt_dir)) file.remove(paste0(ff))

qx_dir <- "StrPath"
dir.create(qx_dir)
setwd(qx_dir)
if (start <= 1 & test==F) for (ff in dir(qx_dir)) file.remove(paste0(ff))

mx_ax_dir <- "StrPath"
dir.create(mx_ax_dir)
setwd(mx_ax_dir)
if (start <= 1 & test==F) for (ff in dir(mx_ax_dir)) file.remove(paste0(ff))


######################
# AGGREGATING SHOCKS
######################
# 
# 

dir.create(paste0("StrPath", output_version_id))

if(!file.exists(paste0("/StrPath", output_version_id, "/shocks_1.csv"))){
  jname <- "aggregate_shocks"
  mycores <- 10
  sys.sub <- paste0("qsub ",ifelse(errout,errout_paths,""),"-cwd ", proj, "-N ", jname, " -pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G")
  script <- "/StrPath/aggregate_shocks.R"
  args <- paste(output_version_id, sep=" ")
  if (test) print(paste(sys.sub, "StrPath/r_shell.sh", script, args))
  if (!test) system(paste(sys.sub, "StrPath/r_shell.sh", script, args))
}

# 
# 
# ######################################
# # RUN SHOCKS ############
# ######################################
# 
# ####################
setwd(code_dir)
if (start <= 1 & end >= 1) {
  jlist1 <- c()
  mycores <- 4
  for (loc in locations$location_id) { 
    ihme_loc_id <- locations$ihme_loc_id[locations$location_id==loc]
    if (loc %in% c(44634,44635,44636,44637,44639)) ihme_loc_id <- locations$location_id[locations$location_id == loc]
    jname <- paste("add_shocks",ihme_loc_id, sep="")
    hold <- paste(" -hold_jid \"",paste("aggregate_shocks",collapse=","),"\"",sep="")
    sys.sub <- paste0("qsub ",ifelse(errout,errout_paths,""),"-cwd ", proj, "-N ", jname, " ", "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ", hold)
    script <- "add_shocks_env.R"
    args <- paste(ihme_loc_id, loc, output_version_id, sep=" ")
    
    if (test) print(paste(sys.sub, r_shell, script, args))
    if (!test) system(paste(sys.sub, r_shell, script, args))
    jlist1 <- c(jlist1, jname)
  }
}
# 
# #########################
# ## COMPILE SHOCKS########
# #########################

if(start <= 2 & end >= 2){
  jname <- "compile_shocks"
  mycores <- 2
  if(start<2) hold <- paste(" -hold_jid \"",paste(jlist1,collapse=","),"\"",sep="")
  sys.sub <- paste0("qsub ",ifelse(errout,errout_paths,""),"-cwd ", proj, "-N ", jname, ifelse(start < 2,hold,""), " -pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ")
  script <- "compile_shocks.R"
  if (test) print(paste(sys.sub, r_shell, script))
  if (!test) system(paste(sys.sub, r_shell, script))
}


