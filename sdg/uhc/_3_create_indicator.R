
## sdg 2015 paper
## last updated: July 22, 2016

###################################################################################
###################################################################################
## Purpose: Generate a Universal Health Coverage indicator to be used for SDG goal 
## 3.1.1. This indicator will be the geometric mean of: ANC1, ANC4, ART coverage, 
## contraception coverage, DPT3, IFD, ITN coverage, measles vacc, polio 3
## vacc, SBA, and TB case-detection rate. 

## Final version used for the collaborator version is: /uhc_expanded/ which has 
    ## each individual component addedinto the final geometric mean separately
## Note: SBA, IFD, and ANC1 numbers were all the same for the collab version and 
    ## this has now been updated

###################################################################################
###################################################################################

rm(list=ls())
library(plyr)
library(dplyr)
library(plyr)
library(RMySQL)
library(data.table)

home <- "/share/scratch/projects/sdg/input_data/uhc_expanded/"

parent_folders <- paste(home, list.files(home), sep="/")


get_var_name <- function(f){
    # extracts a variable name from a file path
    strsplit(strsplit(f, "/")[[1]][length(strsplit(f, "/")[[1]])], "_draws")[[1]][1] 
}


get_draw_col_names <- function(df){
    # given a data frame returns the columns that should correspond to the draws
    draw_cols <- names(df)[grepl("draw", names(df))]
    #draw_cols <- c(draw_cols, names(df)[grepl("coverage_", names(df))])
    unique(draw_cols)
}


location_table <- function(){
    call <- 'SELECT ihme_loc_id, location_id FROM 
    shared.location_hierarchy_history
    WHERE location_set_version_id=90; # gbd reporting 2015'
    con <- dbConnect(strConnection)
    res <- dbSendQuery(con, call)
    df <- fetch(res, n=-1)
    dbDisconnect(dbListConnections(MySQL())[[1]])
    df
}


add_loc_id <- function(df){
    if("iso3" %in% names(df)){
        df$ihme_loc_id <- df$iso3
    }
    df <- left_join(df, location_table(), by = "ihme_loc_id")
    df
}


check_demographics <- function(df){
    # checks to see if the correct demograhics are there or can be created
    # need sex_id = 3, age_group_id = 27 and location_id all year_id all!!!
    # first check sexes
    if ("sex_id" %in% names(df)){
        df <- subset(df, sex_id == 3)
    }
    else{
        df$sex_id <- 3
    }
    # then check age groups
    if ("age_group_id" %in% names(df)){
        if(!(27 %in% unique(df$age_group_id))){
            df <- subset(df, age_group_id == 22)
            df$age_group_id <- 27
        }
        else{
            df <- subset(df, age_group_id == 27)
        }
    }
    else{
        df$age_group_id <- 27
    }
    # then check year
    if ("year" %in% names(df)){
        df$year_id <- df$year 
    }
    # then check iso. 
    if (!("location_id" %in% names(df))){
        df <- add_loc_id(df)
    }
    df
}


get_loc_col <- function(df){
    # takes a data frame and returns the loc id column
    loc_id <- NULL
    for (l in c("iso3", "ihme_loc_id", "location_id")){
        if (l %in% names(df)){
            loc_id <- l
        }
    }
    return(l)
}


subset_locs <- function(df){
    # subsets data frame so that it is only the
    # locations needed for the uhc analysis
    df_loc <- read.csv("/share/scratch/projects/sdg/input_data/locs_needed.csv")
    df_loc <- df_loc[,c("location_id", "ihme_loc_id")]
    # check that each individual data set has the required locations
    if (!(all(unique(df_loc$location_id) %in% unique(df$location_id)))){
        print("Not all locations are in this file!!!!!!!!!!!!!!!!!!!!!")
    }
    df_loc$iso3 <- df_loc$ihme_loc_id
    loc_col <- get_loc_col(df)
    new_df <- left_join(df_loc, df, by=loc_col)
    return(new_df)
}


read_file <- function(f){
    print(paste0("FILE IS:", f))
    # reads in a csv and makes sure it has the right columns
    df <- as.data.frame(fread(f))
    # get the var name from the string
    var_name <- get_var_name(f)
    # get the draw column names
    draw_cols <- get_draw_col_names(df)
    new_draw_cols <- paste(var_name, 0:999, sep="_draw_")
    names(new_draw_cols) <- draw_cols
    # rename the draw cols
    df <- plyr::rename(df, new_draw_cols)
    # check demographics
    df <- check_demographics(df)
    # only use the locations that we need
    df <- subset_locs(df)
    # replace zeros with small number because zeros do strange things
        # to geometric means
    for(d in new_draw_cols){
        df[!is.na(df[,d]) & df[,d] <= 10**-2, d] <- 10**-2
    }
    # replace 100% with 99.9% because if we can't have 0 we just can't have 100
    for(d in new_draw_cols){
        df[!is.na(df[,d]) & df[,d] == 100, d] <- 99.9
    }
    df
}


gm_mean <- function(x, na.rm=TRUE){
    # compute the geometric mean of a vector
    exp(sum(log(x[x > 0]), na.rm=na.rm) / length(x))
}


gmm_draws <- function(df, stub, draws=1000){
    
    # calculate the geometric mean across draws
    old_draws <- get_draw_col_names(df)
    # old_draws[, grepl(paste0("_draw_", i, "$"), old_draws)][grepl(paste0("_draw_", i, "$"), old_draws)==0] <- .001
    new_draws <- c()
    
    for(i in 0:(draws-1)){
        geo_mean_cols <- old_draws[grepl(paste0("_draw_", i, "$"), old_draws)]
        new_col <- paste(stub, "draw", i, sep="_")
        df[new_col] <- apply(df[geo_mean_cols], 1, function(x) gm_mean(x))
        new_draws <- c(new_draws, new_col)
    } 
    df[, c("location_id", "age_group_id", "sex_id", "year_id", new_draws)]
}


read_folder <-  function(dir, draws=1000){
    # read a directory and compute the geo mean for that dir
    count <- 0
    files <- list.files(dir)
    ind_name <- strsplit(dir, "/")[[1]][length(strsplit(dir, "/")[[1]])]
    
    # loop through and load in each data file
    for(ext in files){
        f <- paste(dir, ext, sep="/")
        count <- count + 1
        if(count == 1){
            df <- read_file(f)
        }
        else{
            df <- inner_join(df, read_file(f), 
                             by=c("location_id", "age_group_id", "year_id", "sex_id"))
        }
    }
    
    print(paste0("Calculating geometric mean for ", ind_name))
    gmm_draws(df, ind_name, draws)
}


parent_folders <- list.dirs(home)
# don't compute the folders we have eliminated (see top for reasoning)
parent_folders <- setdiff(parent_folders, 
                          c('/share/scratch/projects/sdg/input_data/uhc_expanded/', 
                          '/share/scratch/projects/sdg/input_data/uhc_expanded//pcv',
                          '/share/scratch/projects/sdg/input_data/uhc_expanded//rota'))
count <- 0
ind_name <- 'uhc_ind_var'
df_list <- list()

# loop through and load in each data folder
for(dir in parent_folders){
    count <- count + 1
    df_list[[dir]] <- read_folder(dir)
}

# joing each category of indicator
df <- df_list[[1]]
for(i in 2:length(df_list)){
    df <- inner_join(df, df_list[[i]])
}

# calculate the geometric mean of each category
ind_name <- 'uhc_ind_var'
df2 <- gmm_draws(df, ind_name)
df2$uhc_ind_var_mean <- rowMeans(df2[,get_draw_col_names(df2)])

# merge on the ihme_loc_id 
df_loc <- read.csv("/share/scratch/projects/sdg/input_data/locs_needed.csv")
df_loc <- df_loc[,c("location_id", "ihme_loc_id", "location_name")]
df3 <- left_join(df2, df_loc)
 write.csv(df3, file=paste("/share/scratch/projects/sdg/indicators", "uhc_ind_var_post_collab.csv", sep="/"),
          row.names=FALSE)

write.csv(df, file=paste("/share/scratch/projects/sdg/indicators", "sub_category_uhc_ind_var_post_collab.csv", sep="/"),
         row.names=FALSE)





