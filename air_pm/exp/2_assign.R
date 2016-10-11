#----HEADER----------------------------------------------------------------------------------------------------------------------
# Project: RF -> air_pm
# Purpose: Moved the assign prep section to a new file in order to make easier control flow in master
# source("/homes/jfrostad/_code/risks/air_pm/exp/2_assign.R", echo=T)
#********************************************************************************************************************************
 
#----FUNCTIONS----------------------------------------------------------------------------------------------------------  
##function lib##
#Air EXP functions#
exp.function.dir <- file.path(h_root, '_code/risks/air_pm/exp/_lib')  
file.path(exp.function.dir, "assign_tools.R") %>% source  

#general functions#
central.function.dir <- file.path(h_root, "_code/_lib/functions/")
# this pulls the general misc helper functions
file.path(central.function.dir, "misc.R") %>% source
# this pulls the current locations list
file.path(central.function.dir, "get_locations.R") %>% source
#********************************************************************************************************************************
 
#----PREP GRID-------------------------------------------------------------------------------------------------------------------		
# Pull in the global shapefile
shapefile.dir <- file.path(j_root, "DATA/SHAPE_FILES/IHME_OFFICIAL/GLOBAL/GBD_v3/MASTER/shapefile")
shapefile.version <- "GBD_2015_full"
borders <- readOGR(shapefile.dir, layer = shapefile.version)
borders$location_id <- borders$loc_id # this variable is misnamed in the current official global shape, create it here

# import object "newdata" from the file Mike sent
getwd() %>% file.path("data/exp/raw/GBD2015_PRED_20160706_merged.RData") %>% load(envir = globalenv())
#getwd() %>% file.path("data/exp/incoming/GBD2015_PRED_merged2.RData") %>% load(envir = globalenv())

# Set up pollution file
pollution <- as.data.table(GBD2015_PRED_20160706_merged) #convert to DT
rm(GBD2015_PRED_20160706_merged) #cleanup
names(pollution) <- tolower(names(pollution))

# Not interested in all columns
legacy.variables <- c('id', 'idgridcell', 'iso3', 'pop2020v4', 'dust', 'dust_frac', 'region')
pollution <- pollution[, -legacy.variables, with=F]
setnames(pollution, 
         c('pop_1990v3', 'pop_1995v3', 'pop2000v4', 'pop2005v4', 'pop2010v4', 'pop2011v4', 'pop2012v4', 'pop2013v4', 'pop2014v4', 'pop2015v4'),
         c('pop_1990', 'pop_1995', 'pop_2000', 'pop_2005', 'pop_2010', 'pop_2011', 'pop_2012', 'pop_2013', 'pop_2014', 'pop_2015'))	

#define years of interest
years <- c(1990, 1995, 2000, 2005, 2010, 2011, 2012, 2013, 2014, 2015)

#Create an id column
pollution[, id := .GRP, by = c('lat', 'long')]

# Make a raster of the id column
pollution.sp <- pollution[, c("lat", "long", "id"), with=F]
coordinates(pollution.sp) = ~long+lat
proj4string(pollution.sp)=CRS("+init=epsg:4326")
gridded(pollution.sp) = TRUE

pollution.sp <- raster(pollution.sp[, c("id")])
#********************************************************************************************************************************
 
#----EXTRACT---------------------------------------------------------------------------------------------------------------------		
# Use raster's extract to get a list of the raster ids that are in a given country
# The output is a list with one item per country in the borders file
beginCluster(n=max.cores) #extract function can multicore, this initializes cluster (must specify n or it will take all cores)
raster.ids <- extract(pollution.sp, borders)
endCluster()

# Convert to dataframe with two columns
temp <- NULL
for (iii in 1:length(raster.ids)) {
  if (!is.null(raster.ids[[iii]])) {
    
    temp <- rbind(temp, data.frame(location_id=borders$location_id[iii],
                                   location_name=borders$loc_nm_sh[iii],
                                   id=raster.ids[[iii]]))
  }
}

#Some are missing ids
temp <- temp[!is.na(temp$id), ]
# Some ids are in multiple countries. Create an indicator
temp$num_countries <- ave(temp$id, temp$id, FUN=length)
# Merge back on
pollution <- merge(temp, pollution, by="id")

# Reduce population by 1/(number of countries grid is in). 
pollution <- data.table(pollution)
pollution[, paste0("pop_", years) := lapply(years, 
                                            function(year) get(paste0("pop_", year)) / num_countries), 
          with=F]
#********************************************************************************************************************************
 
#----MISSING COUNTRIES-----------------------------------------------------------------------------------------------------------	
# Some countries are too small of islands to pick up any grids. To correct for this,
# we will take the average values for the rectangular area around islands + 1 (or more if necessary) degrees in any direction
# Find out which ones
missing.countries <- unique(borders$location_id)[!(unique(borders$location_id) %in% unique(pollution$location_id))]

missing.countries.vals <- mclapply(missing.countries,
                                   estimateIslands,
                                   borders=borders,
                                   location_id.list=location_id.list,
                                   mc.cores=max.cores)

pollution <- rbind(pollution, rbindlist(missing.countries.vals))
pollution <- merge(pollution, 
                   location_id.list[, c("ihme_loc_id", "location_id"), with=F], 
                   by="location_id", 
                   all.x=T)

pollution$num_countries <- pollution$id <- NULL
#********************************************************************************************************************************
 
#----RESHAPE---------------------------------------------------------------------------------------------------------------------	
# Reshape long
setkey(pollution, "location_id") 
pollution <- melt(pollution, id.vars=c("location_id", "location_name", "ihme_loc_id", "long", "lat", "elevation"))

#setkey for speed
setkey(pollution, "variable")

pollution[, c("var", "year") := tstrsplit(variable, "_", fixed=TRUE)]
pollution[, variable := NULL]

#reshape the different variables out wide (mean/ci and pop)	
pollution	<- dcast(pollution, location_id + location_name + ihme_loc_id + long + lat + elevation + year ~ var)	%>% as.data.table #note for some reason when i dcast it reverts to df, look into this (TODO)

#save the reshaped all grid file
#write.csv(pollution, file.path(out.dir, "all_grids.csv"))

#now output the global gridded file as an Rdata for parallelized saving
save(pollution, 
     file=file.path(out.dir, "all_grids.Rdata"))
#********************************************************************************************************************************