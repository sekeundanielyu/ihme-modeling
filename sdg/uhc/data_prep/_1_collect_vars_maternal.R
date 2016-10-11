
## sdg 2015 paper
## get maternal draws from files and put them in the SDG scratch space for use in UHC variable
## last updated: July 18, 2016


###################################################################################
###################################################################################
#### From flat files ####
## Get ANC, IFD, SBA, vaccine numbers ##
###################################################################################
###################################################################################

## ANC1
anc1_dir <- "/share/covariates/ubcov/model/output/2/draws_temp/"

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

anc1_df <- read_folder(anc1_dir)


write.csv(anc1_df,file="/share/scratch/projects/sdg/input_data/uhc/anc/anc1_draws.csv")
write.csv(anc1_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/anc1/anc1_draws.csv")
write.csv(anc1_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/maternal/anc1_draws.csv")

###################################################################################
###################################################################################
## ANC4 <- still need to compute ratio
anc4_dir <- "/share/covariates/ubcov/model/output/3/draws_temp/"

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

anc4_df <- read_folder(anc4_dir)


write.csv(anc4_df,file="/snfs2/HOME/X/SDG_paper/anc4_draws.csv")
# note: then moved to new file for processing

###################################################################################
###################################################################################
## SBA
sba_dir <- "/share/covariates/ubcov/model/output/4/draws_temp/"

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

sba_df <- read_folder(sba_dir)


write.csv(sba_df,file="/share/scratch/projects/sdg/input_data/uhc/maternal/sba_draws.csv")
write.csv(sba_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/sba/sba_draws.csv")
write.csv(sba_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/maternal/sba_draws.csv")
###################################################################################
###################################################################################
## IFD
ifd_dir <- "/share/covariates/ubcov/model/output/5/draws_temp/"

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

ifd_df <- read_folder(ifd_dir)


write.csv(ifd_df,file="/share/scratch/projects/sdg/input_data/uhc/maternal/ifd_draws.csv")
write.csv(ifd_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/ifd/ifd_draws.csv")
write.csv(ifd_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/maternal/ifd_draws.csv")
