## Aggregate from location-specific, granular ages to all-location, age- and sex-aggregated results
rm(list=ls())
library(data.table); library(foreign); library(reshape2); library(haven)

## Setup filepaths
if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  user <- Sys.getenv("USERNAME")
  
  type <- "hiv_free"
  count <- 0
} else {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  
  type <- commandArgs()[3]
  count <- as.numeric(commandArgs()[4])
  print(count)
  count_plus <- count + 1
  
  if(type == "hiv_free") {
    master_dir <- paste0("strPath")
  } else if(type == "with_hiv") {
    master_dir <- paste0("strPath")
  }
  pre_reckon_dir <- "strPath"
}

## Grab functions to aggregate from lowest-level countries to parents, regions, etc.
source(paste0(root,"/strPath/agg_results.R"))
source(paste0(root,"/strPath/get_locations.r"))
source(paste0(root,"/strPath/get_age_map.r"))
locations <- data.table(get_locations(level="lowest"))
est_locations <- data.table(get_locations(level="estimate"))
est_locations <- est_locations[is_estimate == 1,]

## For these locations, we want to use the parent locations from the input lifetables because the subnational lifetables, when aggregated, do not have 5q0 that matches 5q0 from national-level when it should be (theoretically)
## Only do this for the with-HIV process
parent_locs <- est_locations[location_id %in% unique(locations[,parent_id]),ihme_loc_id] # Get all parent locations but not non-estimate countries (England, China national)
parent_locs <- c(parent_locs,"IND") ## Add India National here
parent_locs <- parent_locs[!(parent_locs %in% c("ZAF"))] # Take out ZAF (ZAF not re-agg'ed)
locations <- locations[,list(location_id)]

aggs <- data.table(get_locations(level="all"))
region_locs <- unique(aggs[level<=2,location_id])
aggs <- unique(aggs[!location_id %in% unique(locations[,location_id]),location_id])

sdi_map <- data.table(get_locations(gbd_type="sdi"))
sdi_locs <- unique(sdi_map[level==0,location_id])

age_map <- data.table(get_age_map())
age_map <- age_map[age_group_id %in% c(5,28),list(age_group_id)]
age_map[age_group_id==5,age:=1]
age_map[age_group_id==28,age:=0]

## Bring in population for all of the locations of interest
population <- data.table(fread(paste0(root,"/strPath/population_gbd2015.csv")))
population <- population[year >= 1970 ,list(location_id,year,sex_id,age_group_id,pop)]

## For all population groups, fill it in with 80+ population
lt_granular_80_groups <- c(30,31,32,33,44,45,148)

over_80_pops <- population[age_group_id==21,]
over_80_pops[,age_group_id:=NULL]
map <- data.table(expand.grid(age_group_id=lt_granular_80_groups,sex_id=unique(over_80_pops[,sex_id]),
                              location_id=unique(over_80_pops[,location_id]),year=unique(over_80_pops[,year])))
over_80_pops <- merge(over_80_pops,map,by=c("sex_id","year","location_id"))
population <- population[!age_group_id %in% c(21,lt_granular_80_groups),]
population <- rbindlist(list(population,over_80_pops),use.names=T)
setnames(population,"year","year_id")

## Bring in data, convert mx to deaths, weight ax by deaths
data <- data.table(fread(paste0(master_dir,"/combined_mx_ax_",count,".csv")))
data[,location_id:=as.integer(location_id)]

## Bring in national-level data for national age-sex under-5 (pre-reckoning) data where we want to use national-level instead of aggregated
## This is because subnational 5q0 scales to national 5q0, but subnational 1q0 and 4q1 do not scale to national 1q0 and 4q1
## and if we aggregated subnational 1m0 and 4m1 along with ax values, national 5q0 would be different from pre-reckoning when it shouldn't have changed
## This will mean that HIV-free LT for under-5 is not necessarily below with-HIV LT (since HIV-free is not subbed in)
if(type == "with_hiv") {
  print("Bringing in national-level u5 mx/ax draws")
  natl_locs <- data.table(get_locations(level="all"))
  natl_locs <- natl_locs[ihme_loc_id %in% parent_locs,list(location_id,ihme_loc_id)]

  get_mx_ax <- function(country) {
    data <- data.table(fread(paste0(pre_reckon_dir,"/lt_",country,".csv")))
    data <- data[(age %in% c(0,1)) & (draw < (count_plus*100)) & (draw >= (count * 100)),list(age,sex,draw,year,mx,ax)]
    data[,location_id:=unique(natl_locs[ihme_loc_id==country,location_id])]
  }
  
  gen_natl_mx_ax <- function() {
    natl_mx_ax <- data.table(rbindlist(lapply(parent_locs,function(x) get_mx_ax(x))))
    natl_mx_ax <- merge(natl_mx_ax,age_map,by=c("age"))
    natl_mx_ax[,age:=NULL]
    setnames(natl_mx_ax,"year","year_id")
    setnames(natl_mx_ax,"sex","sex_id")
  } 
  
  u5_mx_ax <- gen_natl_mx_ax()
  data <- rbindlist(list(data,u5_mx_ax),use.names=T)
}

data <- merge(data,population,by=c("year_id","sex_id","location_id","age_group_id"))
data[,mx:=mx*pop]
data[,ax:=ax*mx]

## Provide ID variables and value variables, then aggregate
## Aggregation skips locations if they already exist in the dataset, so if it's with-HIV,
## we run under-5 separately to retain the national-level mx/ax
## And then run 5+ age group separately to avoid this issue
value_vars <- c("mx","ax","pop")
id_vars <- c("location_id","year_id","sex_id","age_group_id","draw")
if(type == "with_hiv") {
  data_u5 <- agg_results(data[age_group_id %in% c(5,28),],id_vars = id_vars, value_vars = value_vars, agg_sex = F, loc_scalars=T, agg_sdi=T)
  data_o5 <- agg_results(data[!(age_group_id %in% c(5,28)),],id_vars = id_vars, value_vars = value_vars, agg_sex = F, loc_scalars=T, agg_sdi=T)
  data <- rbindlist(list(data_u5,data_o5),use.names=T)
} else {
    data <- agg_results(data,id_vars = id_vars, value_vars = value_vars, agg_sex = F, loc_scalars=T, agg_sdi=T)
}

## Only need this for aggregate locations
data <- data[location_id %in% c(aggs,sdi_locs),]

## For locations without both sexes (e.g. regions and above where we don't produce scalars), we need to agg again because they are missing 
region_data <- data[location_id %in% c(region_locs),]
setkey(region_data,location_id,year_id,age_group_id,draw)
region_data <- region_data[,list(ax=sum(ax),mx=sum(mx),pop=sum(pop)),by=key(region_data)]
region_data[,sex_id:=3]
data <- rbindlist(list(data,region_data),use.names=T)

data[,ax:=ax/mx]
data[,mx:=mx/pop]
data[,pop:=NULL]

## Write out aggregated mx/ax only for region-level and above
write.csv(data,paste0(master_dir,"/region_",count,".csv"),row.names=F)



