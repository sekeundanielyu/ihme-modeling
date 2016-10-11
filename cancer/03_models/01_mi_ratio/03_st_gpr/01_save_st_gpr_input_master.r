################################################################################
## Description: Sets up input data and directories for space-time GPR

################################################################################
## Clear workspace
rm(list=ls())

## Import Libraries
library(boot)
library(plyr)

################################################################################
## SET MI Model Number (MANUAL)
################################################################################
## Model number
modnum <- commandArgs()[3]

################################################################################
## Set Data Locations (AUTORUN)
################################################################################
## Set root directory and working directory
root <- ifelse(Sys.info()[1]=='Windows', 'J:/', '/home/j/')
wkdir <- paste0(root, 'WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/')
setwd(wkdir)

## Set shell and qsub
qsub <- "/usr/local/bin/SGE/bin/lx-amd64/qsub -P proj_cancer_prep -cwd -pe multi_slot 4 -l mem_free=8G"
shell <- paste0(root, "/WORK/07_registry/cancer/00_common/code/r_shell.sh ",  wkdir, "/03_st_gpr/subroutines/01_save_st_gpr_input_worker.r")

## Import model specifications to get the upper_cap and method
model_control <- read.csv('./_launch/model_control.csv', stringsAsFactors = FALSE)
mi_formula <- model_control$formula[model_control$modnum == modnum]
upper_cap <- as.numeric(model_control$upper_cap[model_control$modnum == modnum])

## Set the model method
mi_model_method = ifelse(grepl('logit', deparse(mi_formula)), 'logit', 'log')

## Import list of super regions
location_data = paste0(root, "/WORK/07_registry/cancer/00_common/data/modeled_locations.csv")
super_regions <- read.csv(location_data, stringsAsFactors = FALSE)[, "super_region_id"]
super_regions <- unique(super_regions[!is.na(super_regions)])

## Set the output_directory and delete old outputs from previous iterations of the same model
output_dir = paste0('/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr/model_', modnum)
remove_old_outputs = FALSE
if (remove_old_outputs){
  print("Removing old outputs and plots...")
  unlink(output_dir, recursive = TRUE)
  unlink(paste0('/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr_plots/model_', modnum), recursive = TRUE)
}

################################################################################
## COMPILE LINEAR MODEL OUTPUT
################################################################################
## Create a list of files from which to obtain the model results
files <- list.files(paste0('/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/02_linear_model/model_', modnum), pattern = 'linear_model_output.RData', recursive = TRUE)

## Loop through the model result files. Create one ST_GPR input for each cause-sex-super_region
for(ff in unique(files)) {
  print(ff)
  cause <- substr(ff, start = 1, stop = regexpr('/', ff[1]) - 1)
  sexes <- substr(ff, start = regexpr('/', ff[1]) + 1, stop = gregexpr('/', ff[1])[[1]][2] - 1)
  if (sexes == "both") {sexes = c("female", "male")}
  for (sex in unique(sexes)){
    ## Create results directory
    dir.create(paste0(output_dir, '/', cause, '/', sex, '/_temp'), recursive = TRUE)
    
    ## Submit code to run the model on the cluster
    job_name <- paste("-N sg_prep", substr(cause, 5, nchar(cause)), sex, modnum, sep="_")
    sub <- paste(qsub, job_name, shell, modnum, ff, cause, sex, mi_model_method, upper_cap)
    system(sub)
  }
}

## check for results
print("Checking for completed scripts...")
for(ff in unique(files)) {
  cause <- substr(ff, start = 1, stop = regexpr('/', ff[1]) - 1)
  sexes <- substr(ff, start = regexpr('/', ff[1]) + 1, stop = gregexpr('/', ff[1])[[1]][2] - 1)
  if (sexes == "both") {sexes = c("female", "male")}
  for(sex in unique(sexes)){
    for(sr in super_regions) {
      print(paste(cause, sex, sr))
      found_file = FALSE
      count = 0
      output_file = paste0(output_dir, "/", cause, "/", sex, "/", sr, "_st_input.csv")
      while (!found_file) {
        if (file.exists(output_file)){found_file = TRUE}
        Sys.sleep(.005)
        count = count + 1
        if (count > 60000) {stop("ERROR: Could not complete all linear models (within the time allowed)")}
      }
    }
  }
}

## ##################
## END
## ##################
