
if (Sys.info()[1] == 'Windows') {
  username <- "StrUser"
  root <- "StrPath"
  source("StrPath")
  source("StrPath")
  source("StrPath")
} else {
  username <- Sys.getenv("USER")
  root <- "StrPath"
  source("StrPath")
  source("StrPath")
  source("StrPath")
  output_version_id <- commandArgs()[3]
}

library(data.table)

locs <- get_locations(level="lowest")
loc_id <- locs[, colnames(locs) %in% c("location_id")]

## Compiling shocks numbers files

missing_files <- c()
compiled_shock_numbers <- list()
for (loc in loc_id){
  file <- paste0("StrPath", output_version_id ,"StrPath/shocks_", loc, ".csv")
  if(file.exists(file)){ 
    shocks <- fread(file)
    shocks <- shocks[cause_id==294]
    shocks <- shocks[,cause_id:=NULL]
    compiled_shock_numbers[[paste0(file)]] <- shocks
    cat(paste0(file, "\n")); flush.console()
  } else {
    missing_files <- c(missing_files, file)
  }
}

if(length(missing_files)>0) stop("Files are missing.")


## Creating one shocks file with all lowest level locations
compiled_shock_numbers <- rbindlist(compiled_shock_numbers)
row.names(compiled_shock_numbers) <- 1:nrow(compiled_shock_numbers)

draws <- grep("draw", names(compiled_shock_numbers), value=T)

## Using aggregation function to create file with all aggregated locations
compiled_shock_numbers <- agg_results(data=compiled_shock_numbers, id_vars=c("location_id", "year_id", "sex_id", "age_group_id"), value_vars=draws, loc_scalars = F, agg_sdi=T)
compiled_shock_numbers <- compiled_shock_numbers[!location_id %in% loc_id]


for(locs in unique(compiled_shock_numbers$location_id)){
  write.csv(compiled_shock_numbers[location_id==locs], paste0("StrPath" , output_version_id, "StrPath/shocks_", locs, ".csv"), row.names=F)
}




