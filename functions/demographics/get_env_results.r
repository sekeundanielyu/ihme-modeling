## ##########################################################
##  Purpose:	Grab HIV-deleted envelope results
##  How To:		get_env_results(type="gbd2015")
##  Arguments:
##            pop_only (T/F): If true, it basically works as a get_populations type of thing. Default is false
##            version_id: Numeric, corresponds to the output_version_id of the envelope (1 is gbd2010, 12 is gbd2013, 46 is gbd2015 (for now?)
##              If version_id is not specified, it defaults to pulling the best version from the database
## ###########################################################


get_env_results <- function(version_id=NULL,pop_only=F) {
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
  # Load RMySQL; if no success, install it
  deps <- c("RMySQL") 
  for (d in deps) {
    if(d %in% rownames(installed.packages()) == FALSE) {
      install.packages(d, repo="strPath")
    }    
  }
  require("RMySQL")
  
  ## If no version_id is specified, pull the best version
  get_best <- ifelse(is.null(version_id),1,0)

  ## Import GBD2013 local_ids to get GBD2013 local_ids to help merges
  ## We don't restrict this to only GBD2015 pulls because we want the file structure to be the same regardless of the year input into it (even if it is redundant)
  myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
  loc_version_id <- dbGetQuery(myconn,paste0("SELECT location_set_version_id FROM shared.location_set_version_active WHERE location_set_id = 21 AND gbd_round_id = 3 ")) ## Note: gbd_round_id must change each time
  loc_version_id <- loc_version_id[[1]]
  
  if(get_best == 1) {
    best_version_query <- "SELECT * FROM mortality.output_version WHERE is_best = 1 "
    best_version <- dbGetQuery(myconn,best_version_query)
    version_id <- unique(best_version$output_version_id)
  }
  
  ## Decide which variables to select
  if(pop_only == F) {
    select_command <- paste0("SELECT output_version_id, year_id, location_id, location.ihme_loc_id, ",
                                "sex_id, sex, age_group_id, ages.age_group_name, ",
                                "mean_pop, mean_env_whiv, upper_env_whiv, lower_env_whiv, ",
                                "mean_env_hivdeleted, upper_env_hivdeleted, lower_env_hivdeleted ")
  } else {
    select_command <- paste0("SELECT output_version_id, year_id, location_id, location.ihme_loc_id, ",
                             "sex_id, sex, age_group_id, ages.age_group_name, ",
                             "mean_pop ")
  }
  
  ## Figure out joins and location set version ID
  join_command <- paste0("FROM (SELECT * FROM mortality.output WHERE output_version_id = ",version_id,") as output ",
                         "LEFT JOIN (SELECT ihme_loc_id, location_set_version_id, location_id FROM shared.location_hierarchy_history ",
                            "WHERE location_set_version_id = ",loc_version_id,") as location using(location_id) ",
                         "LEFT JOIN (SELECT * FROM ",
                            "(SELECT age_group_name, age_group_id from shared.age_group ",
                              "INNER JOIN (SELECT DISTINCT age_group_id FROM shared.age_group_set_list ",
                                "WHERE age_group_set_id = 1 OR age_group_set_id = 2 OR age_group_set_id = 5) as age_ids using(age_group_id)) ",
                            "as age_ids2) ", 
                          "as ages using(age_group_id) ",
                         "LEFT JOIN shared.sex using(sex_id) ")
  
  ## Construct SQL query
  sql_command <- paste0(select_command,
                        join_command)
  env_results <- dbGetQuery(myconn, sql_command)
  dbDisconnect(myconn)

  return(env_results)
}
