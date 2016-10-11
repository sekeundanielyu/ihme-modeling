##
## sdg 2015 paper
## get ART draws and put them in the SDG scratch space for use in UHC variable
## last updated: July 18, 2016
################################################################################

art_dir <- "/share/gbd/WORK/02_mortality/03_models/hiv/requests/SDG_paper/art_coverage/"

read_unit <- function(unit_name, folder){
    loc_name <- strsplit(unit_name, "\\.")[[1]][1]
    #year <- as.integer(strsplit(strsplit(unit_name, "_")[[1]][2], "\\.")[[1]][1])
    f <- paste0(folder, unit_name)
    data <- read.csv(f)
    data$iso3 <- loc_name
    #data$year_id <- year
    data
}

read_folder <- function(folder){
    csvs <- list.files(folder)#[endsWith(list.files(folder), ".csv")]
    data <- lapply(csvs, function(x) read_unit(x, folder))
    art_df <- do.call(rbind, data)   
}

art_df <- read_folder(art_dir)


write.csv(art_df,file="/share/scratch/projects/sdg/input_data/uhc/art_coverage/art_draws.csv")
write.csv(art_df,file="/share/scratch/projects/sdg/input_data/uhc_expanded/art_coverage/art_draws.csv")
write.csv(art_df,file="/share/scratch/projects/sdg/input_data/uhc_collapsed/art_coverage/art_draws.csv")
