
## Choose draws to keep for all the 45q15 GPR locations

rm(list=ls())
if (Sys.info()[1]=="Windows"){
  root <- "J:"
  source("strPath/get_locations.r")
} else {
  root <- "/home/j"
  source(paste0("strPath/get_locations.r"))
}
set.seed(1515839)
codes <- get_locations(level = "estimate")
codes <- codes[codes$level_all == 1,]

draw_file <- do.call("rbind",lapply(as.list(codes$ihme_loc_id),FUN = function(x) {
                                              nums <- sample(1:250000, 1000,replace=F)
                                              output <- data.frame(ihme_loc_id = x,sim=nums,newdraw=0:999)
                                              return(output) 
                                              }))

for (loc in unique(draw_file$ihme_loc_id)) {
  write.csv(draw_file[draw_file$ihme_loc_id == loc,],paste0("strPath/",loc,"_chosen_draws.csv"),row.names=F)
}


