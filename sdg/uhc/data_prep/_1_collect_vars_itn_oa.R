
## sdg 2015 paper
## Get ITN numbers from flat files
## last updated: July 25, 2016

rm(list=ls())

library('data.table')
library('parallel')

#versions
gver = 1
abie_ver = '2014_01_22'

#folders
draw_folder = paste0('/home/j/Project/Models/bednets/',abie_ver,'/traces/')
cov_files = list.files(path = draw_folder,pattern='itn_coverage')

#functions
load_draws = function(folder_path,file_path){
    #extract country name
    loc_name <- substr(file_path,14,gregexpr(file_path, pattern='_')[[1]][3]-1)
    
    #load data
    data = fread(paste0(folder_path,file_path))
    long_cols <- names(data)
    data$draw_num <- 1:nrow(data)
    
    # reshape the dat to long
    data_long <- reshape(data, varying=long_cols, v.names="coverage", 
                         timevar="year_str", direction="long", times=long_cols)
    data_long$year_id <- sapply(strsplit(data_long$year_str, "_"), function(x) as.integer(x[3]))
    data_long <- data_long[,c("year_id", "coverage", "draw_num"),with=F]
    
    data_wide <- reshape(data_long, timevar="draw_num", direction="wide", 
                         idvar=c("year_id"))
    names(data_wide) <- c("year_id", paste0("itn_coverage_draw_", 0:999))
    
    data_wide$location_name <- loc_name
    
    return(data_wide)
}

#Load draws
draws = rbindlist(mclapply(cov_files,function(x) load_draws(draw_folder, x), mc.cores=40))

#fix names Sao Tome
# draws[location_name == 'Dem. Rep. of Congo', location_name:= 'Democratic Republic of the Congo']
draws[location_name == 'SaoTome & Principe', location_name:= 'Sao Tome and Principe']

write.csv(draws, file=paste("/home/j/temp/X/sdg/data/itn_outsideafrica_draws.csv"), row.names=FALSE)