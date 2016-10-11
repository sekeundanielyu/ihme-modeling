
## sdg 2015 paper
## Get DPT, measles, and polio numbers from files
## last updated: July 18, 2016


###################################################################################
###################################################################################
## DPT3
dpt3_dir <- "/share/covariates/ubcov/model/output/6/draws_temp/"

read_unit <- function(unit_name, folder){
    loc_id <- strsplit(unit_name, "\\.")[[1]][1]
    f <- paste0(folder, unit_name)
    data <- read.csv(f)
    data
}

read_folder <- function(folder){
    csvs <- list.files(folder)#[endsWith(list.files(folder), ".csv")]
    data <- lapply(csvs, function(x) read_unit(x, folder))
    do.call(rbind, data)   
}

dpt3_df <- read_folder(dpt3_dir)


write.csv(dpt3_df,file="/share/scratch/projects/sdg/input_data/uhc/vaccines/dpt3_draws.csv")
write.csv(dpt3_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/dpt/dpt3_draws.csv")
write.csv(dpt3_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/vaccines/dpt3_draws.csv")
###################################################################################
###################################################################################
## measles
measles_dir <- "/share/covariates/ubcov/model/output/8/draws_temp/"

read_unit <- function(unit_name, folder){
    loc_id <- strsplit(unit_name, "\\.")[[1]][1]
    f <- paste0(folder, unit_name)
    data <- read.csv(f)
    data
}

read_folder <- function(folder){
    csvs <- list.files(folder)#[endsWith(list.files(folder), ".csv")]
    data <- lapply(csvs, function(x) read_unit(x, folder))
    do.call(rbind, data)   
}

measles_df <- read_folder(measles_dir)


write.csv(measles_df,file="/share/scratch/projects/sdg/input_data/uhc/vaccines/measles_draws.csv")
write.csv(measles_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/measles/measles_draws.csv")
write.csv(measles_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/vaccines/measles_draws.csv")
###################################################################################
###################################################################################
## polio3
polio_dir <- "/share/covariates/ubcov/model/output/9/draws_temp/"

read_unit <- function(unit_name, folder){
    loc_id <- strsplit(unit_name, "\\.")[[1]][1]
    f <- paste0(folder, unit_name)
    data <- read.csv(f)
    data
}

read_folder <- function(folder){
    csvs <- list.files(folder)#[endsWith(list.files(folder), ".csv")]
    data <- lapply(csvs, function(x) read_unit(x, folder))
    do.call(rbind, data)   
}

polio_df <- read_folder(polio_dir)


write.csv(polio_df,file="/share/scratch/projects/sdg/input_data/uhc/vaccines/polio_draws.csv")
write.csv(polio_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/polio/polio_draws.csv")
write.csv(polio_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/vaccines/polio_draws.csv")
