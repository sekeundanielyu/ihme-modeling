## ##########################################################
##  Author:    Grant Nguyen
##  Created:	11 Feb 2015
##  Purpose:	Grab locations given certain parameters
##  How To:		get_age_map or get_age_map(type="mort")
##  Options:  type: mort, lifetable, gbd, all 
##                  mort: Mortality standard age groups (plus all ages)
##                  lifetable: All age groups required for lifetables
##                  gbd: Standard GBD age groups
##                  all: Pulls all age groups in shared.age_group
## ###########################################################



get_age_map <- function(type="mort") {
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
  # Load RMySQL; if no success, install it
  deps <- c("RMySQL") 
  for (d in deps) {
    if(d %in% rownames(installed.packages()) == FALSE) {
      install.packages(d, repo="strPath")
    }    
  }
  require("RMySQL")
  
  myconn <- dbConnect(RMySQL::MySQL(), host="strDB", username="strUser", password="strPass") # Requires connection to shared DB
  
  if(type == "mort") {
    sql_command <- paste0("SELECT age_group_set_id, age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end ",
                          "FROM shared.age_group_set_list ",
                          "JOIN shared.age_group_set using(age_group_set_id) ",
                          "JOIN shared.age_group using(age_group_id) ",
                          "WHERE age_group_set_id = 5")
    age_map <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    all_ages <- data.frame(age_group_set_id = 5,age_group_id = 22,age_group_name="All Ages",age_group_name_short = "All Ages", age_group_alternative_name = "All Ages",is_aggregate=1,age_group_years_start=0,age_group_years_end=125,stringsAsFactors=F)
    age_map <- rbind(age_map,all_ages)
  }
  
  if(type == "lifetable") {
    sql_command <- paste0("SELECT age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end ",
                          "FROM shared.age_group ",
                          "WHERE (age_group_id >= 5 AND age_group_id <= 20) OR age_group_id = 28 ",
                          "OR (age_group_id >= 30 AND age_group_id <= 33) OR (age_group_id >= 44 AND age_group_id <= 45) ",
                          "OR age_group_id = 148")
    age_map <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    age_map$age_group_set_id <- NA # Just to have the same variables as in the other SQL pulls
  }
  
  if(type == "gbd") {
    sql_command <- paste0("SELECT age_group_set_id, age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end ",
                          "FROM shared.age_group_set_list ",
                          "JOIN shared.age_group_set using(age_group_set_id) ",
                          "JOIN shared.age_group using(age_group_id) ",
                          "WHERE age_group_set_id = 1")
    age_map <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
  }
  
  if(type == "all") {
    sql_command <- paste0("SELECT age_group_id, age_group_name, age_group_name_short, age_group_alternative_name, is_aggregate, age_group_years_start, age_group_years_end ",
                          "FROM shared.age_group")
    age_map <- dbGetQuery(myconn, sql_command)
    dbDisconnect(myconn)
    age_map$age_group_set_id <- NA # Just to have the same variables as in the other SQL pulls
  }
    
  age_map$age_group_name_short[age_map$age_group_name == "Early Neonatal"] <- "enn"
  age_map$age_group_name_short[age_map$age_group_name == "Late Neonatal"] <- "lnn"
  age_map$age_group_name_short[age_map$age_group_name == "Post Neonatal"] <- "pnn"
  age_map$age_group_name_short[age_map$age_group_name == "Neonatal"] <- "nn"
  age_map$age_group_name_short[age_map$age_group_name == "<1 year"] <- "0"
  age_map$age_group_name_short[age_map$age_group_name == "100 to 104"] <- "100"
  age_map$age_group_name_short[age_map$age_group_name == "105 to 109"] <- "105"

  return(age_map)
}
