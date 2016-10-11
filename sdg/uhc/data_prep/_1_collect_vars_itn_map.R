## 
## sdg 2015
## concatinate MAP ITN draws
## last updated: July 27, 2016

rm(list=ls())

library('data.table')
library('parallel')
library('plyr')


#folders
draw_folder = "/home/j/temp/X/sdg/data/itn_access_map/"
cov_files = list.files(path = draw_folder)


#functions
load_draws = function(folder_path,file_path){
    #extract country name
    loc_name <- strsplit(file_path, "\\.")[[1]][1]
    
    #load data
    data = fread(paste0(folder_path,file_path))
    data[,V1:= NULL]
    long_cols <- names(data)
    data$draw_num <- 1:nrow(data)
    
    # reshape the dat to long
    data_long <- reshape(data, varying=long_cols, v.names="coverage", 
                         timevar="year_str", direction="long", times=long_cols)
    data_long$year_id <- sapply(data_long$year_str, function(x) 
        paste0(strsplit(x, "")[[1]][1:4], collapse = ""))
    data_long <- data_long[,list(coverage=mean(coverage)),by=list(draw_num, year_id)]
    
    data_wide <- reshape(data_long, timevar="draw_num", direction="wide", 
                         idvar=c("year_id"))
    names(data_wide) <- c("year_id", paste0("itn_map_draw_", 0:(max(data_long$draw_num) - 1)))
    
    data_wide$location_name <- loc_name
    
    data_wide[,year_id:=as.numeric(year_id)]
    
    data_wide[,paste0("itn_map_draw_", 500:999) := data_wide[,paste0("itn_map_draw_", 0:499), with=F]]
    
    return(data_wide)
}

#Load MAP draws
draws = rbindlist(mclapply(cov_files,function(x) load_draws(draw_folder, x), mc.cores=40))

#fix names 
#draws[location_name == 'gfhg', location_name:= 'Sao Tome and Principe']


write.csv(draws,file="/home/j/temp/X/sdg/data/_itn_maps_all_locs.csv", row.names=FALSE)
