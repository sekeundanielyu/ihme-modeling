
library(data.table)
if (Sys.info()[1] == 'Windows') {
  username <- "StrUser"
  root <- "StrPath"
  source("StrPath")
  source("StrPath")
} else {
  username <- Sys.getenv("USER")
  root <- "StrPath"
  source("StrPath")
  source("StrPath")
}

locs <- get_locations(level="all")
locs2 <- get_locations(level="all", gbd_type = "sdi") 
locs <- rbind(locs,locs2[!locs2$location_id %in% unique(locs$location_id),])

loc_id <- locs[, colnames(locs) %in% c("location_id")]

## pulling and versioning the mean lt
library(RMySQL)
myconn <- dbConnect(RMySQL::MySQL(), host="StrDB", username="StrUser", password="StrPassword")
sql_command <- paste0("SELECT MAX(output_version_id) ",
                      "FROM mortality.output_version ")
max_version <- dbGetQuery(myconn, sql_command)
dbDisconnect(myconn)
version <- max_version[1][[1]] 

## Compiling evelope summary files

missing_files <- c()
compiled_env <- list()
  for (loc in loc_id){
    cat(paste0(loc,";")); flush.console()
    file <- paste0("StrPath/sumary_env_", loc, ".csv")
    if(file.exists(file)){ 
      compiled_env[[paste0(file)]] <- fread(file)
    } else {
      missing_files <- c(missing_files, file)
    }
  }

if(length(missing_files)>0) stop(paste("Files are missing.",missing_files))

compiled_env <- as.data.frame(rbindlist(compiled_env))
  
row.names(compiled_env) <- 1:nrow(compiled_env)

write.csv(compiled_env, paste0("StrPath/compiled_summary_env_v" ,version, ".csv"), row.names=F)
write.csv(compiled_env, "StrPath/compiled_summary_env.csv", row.names=F)
write.csv(compiled_env, paste0(root, "StrPath/compiled_summary_env_v", version, ".csv"), row.names=F)
write.csv(compiled_env, paste0(root, "StrPath/compiled_summary_env.csv"), row.names=F)

# Compiling lifetable summary files

missing_files <- c()
compiled_lt <- list()
for (loc in loc_id){
  cat(paste0(loc,";")); flush.console()
  file <- paste0("StrPath/summary_lt_", loc, ".csv")
  if(file.exists(file)){ 
    compiled_lt[[paste0(file)]] <- fread(file)
  } else {
    missing_files <- c(missing_files, file)
  }
}

if(length(missing_files)>0) stop(paste("Files are missing.",missing_files))

compiled_lt <- as.data.frame(rbindlist(compiled_lt))
row.names(compiled_lt) <- 1:nrow(compiled_lt)

 
write.csv(compiled_lt, paste0("StrPath/compiled_summary_lt_v" ,version, ".csv"), row.names=F)
write.csv(compiled_lt, "StrPath/compiled_summary_lt.csv", row.names=F)
write.csv(compiled_lt, paste0(root, "StrPath/compiled_summary_lt_v", version, ".csv"), row.names=F)
write.csv(compiled_lt, paste0(root, "StrPath/compiled_summary_lt.csv"), row.names=F)


## Compiling 5q0

missing_files <- c()
u5m <- list()
for (loc in loc_id){
  file <- paste0(paste0("StrPath/as_",loc,"_summary.csv"))
  if(file.exists(file)){ 
    u5m[[paste0(file)]] <- read.csv(file)
  } else {
    missing_files <- c(missing_files, file)
  }
}

if(length(missing_files)>0) stop("Files are missing.")

u5m <- do.call("rbind", u5m)
row.names(u5m) <- 1:nrow(u5m)

write.csv(u5m, paste0("StrPath/as_withshock.csv"), row.names=F)
write.csv(u5m, paste0("StrPath/as_withshock_v", version, ".csv"), row.names=F)
write.csv(u5m, paste0(root, "StrPath/as_withshock.csv"), row.names=F)
write.csv(u5m, paste0(root, "StrPath/as_withshock_v", version, ".csv"), row.names=F)


## Compiling 45q15


missing_files <- c()
adult <- list()
for (loc in loc_id){
  file <- paste0("StrPath/45q15_", loc, ".csv")
  if(file.exists(file)){ 
    adult[[paste0(file)]] <- read.csv(file)
  } else {
    missing_files <- c(missing_files, file)
  }
}

if(length(missing_files)>0) stop("Files are missing.")

adult <- do.call("rbind", adult)
row.names(adult) <- 1:nrow(adult)

write.csv(adult, paste0("StrPath/compiled_45q15.csv"), row.names=F)
write.csv(adult, paste0("StrPath/compiled_45q15_v", version, ".csv"), row.names=F)
write.csv(adult, paste0(root, "StrPath/compiled_45q15.csv"), row.names=F)
write.csv(adult, paste0(root, "StrPath/compiled_45q15_v", version, ".csv"), row.names=F)


## Compiling life expectancy
missing_files <- c()
le <- list()
for (loc in loc_id){
  file <- paste0("/StrPath/le_", loc, ".csv")
  if(file.exists(file)){ 
    le[[paste0(file)]] <- read.csv(file)
  } else {
    missing_files <- c(missing_files, file)
  }
}

if(length(missing_files)>0) stop("Files are missing.")

le <- do.call("rbind", le)
row.names(le) <- 1:nrow(le)

write.csv(le, paste0("StrPath/compiled_le.csv"), row.names=F)
write.csv(le, paste0("StrPath/compiled_le_v", version, ".csv"), row.names=F)
write.csv(le, paste0(root, "StrPath/compiled_le.csv"), row.names=F)
write.csv(le, paste0(root, "StrPath/compiled_le_v", version, ".csv"), row.names=F)




