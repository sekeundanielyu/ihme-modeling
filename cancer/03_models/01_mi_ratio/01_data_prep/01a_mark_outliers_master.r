################################################################################

## Description: Schedule script to mark outliers by cause for MI Input

################################################################################

## Manually set modnum
  if (length(commandArgs()) == 1| commandArgs()[1] == "RStudio")  {
    mi_input_version = readline(prompt = "Enter date suffix of the input file (mi input version):")
    modnum = 157
  } else {
    mi_input_version <- commandArgs()[3]
    modnum <- commandArgs()[4]
  }
  username = "cmaga"

## Set root directory and working directory
  root <- ifelse(Sys.info()[1]=="Windows", "J:", "/home/j")
  cancer_folder = paste0(root, "/WORK/07_registry/cancer")
  wkdir = paste0(cancer_folder, "/03_models/01_mi_ratio")
  cluster_output = "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio"

## set shell location
  r_shell = paste0(cancer_folder, "/00_common/code/r_shell.sh")
  marked_outliers_folder = paste0( wkdir, "/03_results/01_data_prep/raw_inputs_with_outliers_marked")

## set location of worker script
	script =  paste0(wkdir, "/01_code/01_data_prep/01a_mark_outliers_worker.r")
  
## set temp folder, remove old outputs
  temp_folder = paste0(cluster_output, "/05_outliers")
  unlink(temp_folder, recursive = TRUE)
  dir.create(temp_folder)

## create temp folder for this modnum
  dir.create(paste0(temp_folder, "/model_", modnum))

## ##################
## Submit Jobs
## ##################
## run python script that converts outlier_selection excel file to csv
  system('python /home/j/WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/05_outliers/convert_outlier_selection.py')

## import outliers as marked by faculty and keep only data with correctly entered causes
  outlier_marks = read.csv(paste0(cluster_output, "/05_outliers/outlier_selection.csv"))

## keep only marks that have acause beginning with "neo_"
  outlier_marks$acause <- as.character(outlier_marks$acause)
  outlier_marks <- outlier_marks[grep("neo_", outlier_marks$acause), ]

## remove duplicates
  outlier_marks$ihme_loc_id <- as.character(outlier_marks$ihme_loc_id)
  outlier_marks$ihme_loc_id[outlier_marks$ihme_loc_id == "" | (outlier_marks$ihme_loc_id %in% c("all", "any"))] <- "any"
  outlier_marks <- outlier_marks[!duplicated(outlier_marks),]

# create sorted list of causes
  causes <- sort(unique(outlier_marks$acause))

# for each cause, delete old outputs and submit a script to mark outliers
  for (c in causes) {    
    if (root == "Windows") {
      commandArgs <- function() c("runR", "runR", c, temp_folder, mi_input_version, modnum)
      source(script)
    }
    else {
      job_name = paste0("cOutlr_", c) 
      shell = paste(r_shell, script) 
      qsub = "/usr/local/bin/SGE/bin/lx-amd64/qsub -cwd -P proj_cancer_prep -pe multi_slot 6 -l mem_free=12G -N"
      sub = paste(qsub, job_name, shell, c, temp_folder, mi_input_version, modnum)
      system(sub)
    }
  }

## ##################
## Compile results
## ##################
  outliers_marked <- data.frame()

  for (c in causes){
    output_file = paste0(temp_folder, "/model_", modnum, "/", c ,"_outliers.csv")
    while (!file.exists(output_file)){
      print(paste(c, "not yet found. Checking again in 30 seconds..."))
      Sys.sleep(30)
    }
    print(paste("found", c))
    Sys.sleep(5)
    output <- read.csv(output_file)
    outliers_marked <- rbind(outliers_marked, output)
  }

## #################
## Finalize and save 
## #################
  outliers_marked <- outliers_marked[,names(outliers_marked) %in% c("ihme_loc_id", "year", "sex", "age", "acause", "cases", "deaths", "mi_ratio", "manual_outlier", "excludeFromNational")]
  write.csv(outliers_marked, paste0(marked_outliers_folder, "/04_MI_ratio_model_input_", mi_input_version, ".csv"), row.names =FALSE)

## #######
## END
## #######
                                                                          