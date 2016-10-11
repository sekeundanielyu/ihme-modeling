################################################################################

## Description: Input MI input data, loop through cancer site/sex models, data data and save to ihme/gbd/J Drive, and then submit modeling job.

##################################################################
## Clear workspace
  rm(list=ls())

################################################################################
## SET MI Model Number (MANUAL)
################################################################################
## Model number
if (length(commandArgs()) == 1| commandArgs()[1] == "RStudio")  {
  modnum = 157
} else {modnum <- commandArgs()[3]}

################################################################################
## Set Data Locations and Load the Input Data (AUTORUN)
################################################################################
## Set root directory and working directory
  root <- ifelse(Sys.info()[1]=="Windows", "J:", "/home/j")
  cancer_folder = paste0(root, "/WORK/07_registry/cancer")
  wkdir = paste0(cancer_folder, "/03_models/01_mi_ratio")
  cluster_output <- "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio"

## set shell location
  r_shell = paste0(cancer_folder, "/00_common/code/r_shell.sh")

## set paths
  cause_information_path = paste0(wkdir, "/02_data/data_restrictions.csv")
  model_control_path = paste0(wkdir, "/01_code/_launch/model_control.csv")

## Load the input data
   load(paste0(wkdir, "/03_results/01_data_prep/formatted_model_inputs/mi_input_", modnum, ".RData"))

## Import and set model specifications
  model_control <- read.csv(model_control_path,  stringsAsFactors = FALSE)
  mod_spec <- model_control[model_control$modnum == modnum, ,drop = FALSE]

## Update last run on model_control
  model_control$last_run[model_control$modnum == modnum] <- as.character(Sys.Date())
  write.csv(model_control, model_control_path, col.names = TRUE, row.names = FALSE)

## Set the output directory for the linear model
  output_dir = paste0(cluster_output, "/02_linear_model/model_", modnum)

## Delete plots and data for previous iterations of the same model number
  unlink(output_dir, recursive = TRUE)
  plot_dir = paste0(cluster_output, "/02_linear_model_plots/model_", modnum)
  unlink(plot_dir, recursive = TRUE)

################################################################################
## Iterate through Causes and Run the Model on Each Cause (AUTORUN)
################################################################################
## Create a list to dictate which causes should be modeled and for which genders
  cause_information <- read.csv(cause_information_path)
  
# keep only those data that are modeled
  cause_information <- cause_information[cause_information$model_mi == 1, ]

## Loop through each cause
for(ii in 1:nrow(cause_information)) {
  ## Set cause and sex
  	model <- cause_information[ii, , drop = FALSE]
  	sex <- as.character(model$sex)
  	cause <- as.character(model$acause)

  ## Remove old results and plots, then create new results directory
    dir.create(paste0(output_dir, "/", cause, "/", sex), recursive = TRUE, showWarnings = FALSE)
  
  ## If only one sex is modeled, drop the NULL data associated with the non-modeled gender. 
    if(sex == "both"){data <- mi_input[mi_input$acause == cause, ]} else {data <- mi_input[mi_input$acause == cause & mi_input$sex == sex, ]}
    
    print(unique(data$acause))
    if (!(cause %in% unique(data$acause))){break}
  
  ## Skip submission if no data is not present for the given cause and sex
    if(nrow(data) == 0) {
      print(paste0('No data for ', cause, ' ', sex))
      next
    }

  ## Load the prediction frame for the corresponding cause, sex, and modnum
    load(paste0(wkdir, "/02_data/pred_frame.RData"))
    if(sex != "both") {pred_frame <- pred_frame[pred_frame$sex == sex, ]}
    pred_frame$cause <- cause
    pred_frame$modnum <- modnum

  ## Save the model input    
    save(model, data, pred_frame, mod_spec, file = paste0(cluster_output, "/02_linear_model/model_", modnum, "/", cause, "/", sex, "/model_input.RData"))
    
  ## Submit code to run the model on the cluster
    ## set qsub 
    qsub <- "/usr/local/bin/SGE/bin/lx-amd64/qsub -P proj_cancer_prep -cwd -pe multi_slot 4 -l mem_free=8G"
    
    ## declare the job name, shell script, and submit command, then submit information to the cluster
    job_name <- paste("-N ln", substr(cause, 5, nchar(cause)), sex, modnum, sep="_")
    shell <- paste0(r_shell, " ", wkdir, "/01_code/02_linear_model/02_run_model_master.r")
    sub <- paste(qsub, job_name, shell, modnum, cause, sex, sep=" ")
    system(sub)
 
 }

## check for results
for(ii in 1:nrow(cause_information)) {
  ## Set cause and sex
  model <- cause_information[ii, , drop = FALSE]
  sex <- as.character(model$sex)
  cause <- as.character(model$acause)
  found_file = FALSE
  count = 0
  print(paste("Checking for", cause, sex, "..."))
  output_file = paste0(cluster_output, "/02_linear_model/model_", modnum, "/", cause, "/", sex, "/linear_model_output.RData")
  while (!found_file) {
    if (file.exists(output_file)){found_file = TRUE}
    Sys.sleep(1)
    count = count + 1
    if (count > 300) {stop("ERROR: Could not complete all linear models (within the time allowed)")}
  }
}

