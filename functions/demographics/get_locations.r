## ##########################################################
##  Purpose:	Grab locations given certain parameters
##  How To:		locations <- get_locations() # Will get you 2015 results at the lowest level
##            locations <- get_locations(gbd_year=2015, level="lowest", gbd_type="gbd", reporting="no")
##            locations <- get_locations(subnat_only="KEN")
##  Options (all are optional):
##    gbd_year (2010, 2013, 2015): 
##      Specify year of GBD that you want locations for. 
##      Default: 2015 
##    level (lowest, country, countryplus, region, super, global, all)
##      Do you want all of the levels, or just the lowest-level possible, countries, regions, super-regions, or global 
##                          countryplus will grab all of the countries AND all of the subnationals (estimates and non-estimates together)
##                          estimate will grab all of the countries AND all of the subnationals WHERE is_estimate == 1 (so excludes the reporting aggregates like England, China total, etc.)

##      Default: countryplus (country plus all subnationals, e.g. USA and USA_####, REGARDLESS of is_estimate status)
##    gbd_type: 
##      What type of GBD computation do you want locations for? (mortality, gbd, sdi)
##      Default: gbd
##    reporting (yes/no):
##      Do you want the reporting or computation versions of the locations (if available)?
##      Default: no (aka use computation version)
##      Note: Reporting only available with gbd_type = "gbd" -- mortality and SDI don't have separate computation/reporting versions
##    subnat_only(iso3):
##      Do you want only the subnational locations for one specific country?
##      If so, write the iso3 of the country 
##      Default: nothing
## ###########################################################

get_locations <- function(gbd_year = 2015, gbd_type = "mortality", level = "countryplus", reporting = "no", subnat_only = NULL) {
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
  # Load RMySQL; if no success, install it
  deps <- c("RMySQL") 
  for (d in deps) {
    if(d %in% rownames(installed.packages()) == FALSE) {
      install.packages(d, repo="strRepo")
    }    
  }
  require("RMySQL")
  
  ## Recode options (naming conventions etc.)
    if(reporting == "yes" & gbd_type != "gbd") {
      print("Reporting-specific versions are available only for gbd_type gbd")
      print(paste0("Will pull locations for ",gbd_type, " Computation version for ", gbd_year))
    }

  ## Import GBD2013 local_ids to get GBD2013 local_ids to help merges
  ## We don't restrict this to only GBD2015 pulls because we want the file structure to be the same regardless of the year input into it (even if it is redundant)
    myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
    sql_command <- paste0("SELECT location_id, local_id as local_id_2013 ",
                          "FROM shared.location_hierarchy_history ",
                          "WHERE location_set_version_id = 11")
    tempmap_2013 <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    
  
  ## Import GBD 2015 data using version_id as the index
    if(gbd_year == 2016) gbd_round <- 4
    if(gbd_year == 2015) gbd_round <- 3
    if(gbd_year == 2013) gbd_round <- 2
    if(gbd_year == 2010) gbd_round <- 1
    
    if(gbd_type == "gbd" & reporting == "yes") best_set <- 1
    if(gbd_type == "gbd" & reporting == "no" & gbd_year >= 2015) best_set <- 35
    if(gbd_type == "gbd" & reporting == "no" & gbd_year < 2015) best_set <- 2
    if(gbd_type == "mortality") best_set <- 21
    if(gbd_type == "sdi") best_set <- 40
    
    if(reporting=="yes") report_string <- "Reporting"
    if(reporting=="no") report_string <- "Computation"
    
    myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
    sql_command <- paste0("SELECT location_set_version_id, gbd_round_id, location_set_id ",
                          "FROM shared.location_set_version_active ",
                          "WHERE location_set_id = ",best_set,
                          " AND gbd_round_id = ",gbd_round)
    loc_versions <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    if(nrow(loc_versions)==0) {
      stop(paste0("No location_set_version_id exists for this combination of gbd_type ",gbd_type," and gbd_year ",gbd_year))
    }
    version_id <- unique(loc_versions$location_set_version_id)

    print(paste0("Pulling locations for GBD",gbd_year," ", report_string,", gbd_type ",gbd_type, ", at ", level, " level (version ", version_id,")"))

    myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
    if(gbd_type != "sdi") {
      sql_command <- paste0("SELECT location_id, location.location_name as location_name_accent, location.location_ascii_name as location_name, location_type, level, super_region_id, super_region_name, ",
                          "region_id, region_name, ihme_loc_id, local_id, parent_id, location_set_version_id, is_estimate, location.path_to_top_parent ",
                          "FROM shared.location_hierarchy_history ",
                          "JOIN shared.location using(location_id) ",
                          "WHERE location_set_version_id = ",version_id)
     
    } else { 
      ## For SDI, the SDI table does not include ihme_loc_id for subnational units, so we merge on the mortality ihme_loc_ids from the mortality hierarchy
      sql_command <- paste0("SELECT master.location_id, location.location_name as location_name_accent, location.location_ascii_name as location_name, location_type, level, super_region_id, super_region_name, ",
                            "region_id, region_name, mort.ihme_loc_id, local_id, parent_id, location_set_version_id, is_estimate, location.path_to_top_parent ",
                            "FROM shared.location_hierarchy_history as master ",
                            "JOIN shared.location using(location_id) ",
                            "LEFT JOIN (SELECT location_id,ihme_loc_id from shared.location_hierarchy_history ",
                              "WHERE location_set_version_id = shared.active_location_set_version(21,",gbd_round,") ",
                              ") mort ON mort.location_id=master.location_id ",
                            "WHERE location_set_version_id = ",version_id) 

    }
    locations <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    
    locations$location_set_version_id <- NULL # Drop version ID indicators
    locations$location_name[locations$location_name_accent == "Global"] <- "Global" # Changing ascii version of Global to Global
    
  ## If level is specified, only keep geographies at that level
  ## NOTE: We don't use level 6, which is deprivation levels, because Mortality doesn't need that level of detail for Uk
  ## Instead, for subnational/lowest, we use level 5, which is the standard GBR non-split levels
    if(level == "country") level_target <- 3
    if(level == "region") level_target <- 2
    if(level == "super") level_target <- 1
    if(level == "global") level_target <- 0
    if(level != "all" & level != "lowest" & level != "countryplus" & level != "subnational" & level != "estimate") locations <- locations[locations$level == level_target,]
    
    if(level == "subnational") locations <- locations[locations$level == 4 | locations$level == 5,]
  
  ## In the default option, we take the lowest available geography (subnational if available, country if not)
    if(level == "lowest" | (level == "countryplus" & gbd_type != "sdi") | level == "estimate") {
      # Grab only country or subnational locations
        locations <- locations[locations$level == 3 | locations$level == 4 | locations$level == 5,]
        if(level == "lowest") {
          # Drop all of the parent country observations if subnational is present
          parent_drop <- unique(locations$parent_id[locations$level == 4 | locations$level == 5])
          locations <- locations[!locations$location_id %in% parent_drop,] 
        }
    }
  
    if(level == "estimate") locations <- locations[locations$is_estimate == 1,]
    
  ## If the subnat_only option is specified, only keep subnationals for the specified country
  if(!is.null(subnat_only)) {
    if(level != "lowest" & level != "subnational" & level != "countryplus" & level != "estimate") {
      print("Cannot specify a non-subnational level and expect a subnational-restricted list. Specify lowest level option.")
      BREAK
    }
    else {
      print(paste0("Keeping only country level and subnational units from ",subnat_only))
      locations <- locations[grepl(subnat_only, locations$ihme_loc_id),]
    }
  }
  
  ## Bring back the GBD2013 location ids to use to merge onto other datasets
  locations <- merge(locations, tempmap_2013, by = "location_id", all.x = TRUE)
  locations$local_id_2013[locations$location_name == "England"] <- "XEN"
  locations <- locations[,c("location_name","ihme_loc_id","local_id","local_id_2013","location_id","level","parent_id","region_id","region_name","super_region_id","super_region_name","location_type","location_name_accent","is_estimate","path_to_top_parent")]
  
  ## Merge on modeling_ids used for 45q15 and 5q0 
  locs_temp <- read.csv(paste0(root,"/strPath/modeling_hierarchy.csv"))
  locs_temp <- locs_temp[,c("location_id","level_1","level_2","level_3","level_all")]
  locations <- merge(locations,locs_temp, all.x=TRUE)
  locations$level_1[is.na(locations$level_1)] <- 0
  locations$level_2[is.na(locations$level_2)] <- 0
  locations$level_3[is.na(locations$level_3)] <- 0
  locations$level_all[is.na(locations$level_all)] <- 0
  
  return(locations)
}

