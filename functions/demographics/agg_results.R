## Purpose: Aggregate results from lowest levels to highest levels of locations, to create a complete set of locations
## 
## Required Input: a data.table containing only id_vars and value_vars
##            This data.table must include at least ALL lowest-level locations (as found by get_locations(level="lowest"))
##            This data.table NEEDS to be completely square (e.g. no missing rows for certain id_var combinations) -- the code DOES NOT check for a completely square dataset
## Variables: location_id, value_vars (note: please list location_id as one of the id_vars)
##            If age_aggs option is specified, age_group_id must be present
##            If agg_sex option is specified, sex_id must be present
##            Note: CANNOT include variables parent_id, level, or scaling_factor -- these are merged on 
## All variables in the dataset must be specified as either id_vars or value_vars
## Returns a data.table with id_vars and value_vars, along with new observations for location, age, and sex aggregates


################################################################################################################
## 

agg_results <- function(data,id_vars,value_vars,age_aggs="",agg_sex = F,loc_scalars=T,agg_hierarchy=T,end_agg_level=0,agg_sdi=F) {
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
  require(data.table); require(haven); require(reshape2)
  source(paste0(root,"/strPath/get_locations.r")) 

  ## Enforce data as a data.table, and all variables are present that should be there
  data <- data.table(data)
  
  if(length(colnames(data)[!colnames(data) %in% c(value_vars,id_vars)]) != 0) {
    stop(paste0("These variables are not specified in either id_vars or value_vars: ",colnames(data)[!colnames(data) %in% c(value_vars,id_vars)]))
  }
  
  if(!"location_id" %in% colnames(data)) {
    stop("Need to have location_id to aggregate locations")
  }
  
  if(("ihme_loc_id" %in% colnames(data)) | length(colnames(data)[grepl("country",colnames(data))]) >0 ) {
    stop("Cannot have location identifiers other than location_id (e.g. ihme_loc_id or country*)")
  }
  
  ## Bring in regional scalars if we want to use them
  if(loc_scalars == T) {
    if(!("sex_id" %in% colnames(data)) | !("age_group_id" %in% colnames(data))) {
      stop("Missing age_group_id or sex_id: needed for scaling")
    }
    pop_scalars <- data.table(read_dta(paste0(root,"/strPath/gbd_scalars.dta")))
    
    ## Apply regional scalars for 80+ group to all 80+ granular groups if they exist
    ## The list of age group IDs here is a manual list of age_group_ids corresponding to 80+ granular groups
    ## We take over-80, create unique observations for each granular age group, then rbind it onto the main dataset
    granular_80_groups <- c(30,31,32,33,44,45,46,48,148,160)
    if(length(granular_80_groups[granular_80_groups %in% unique(data[,age_group_id])]) > 0) {
      expand_groups <- granular_80_groups[granular_80_groups %in% unique(data[,age_group_id])]
      print(paste0("Applying 80+ aggregated scalars to the following 80+ granular groups: ",expand_groups))

      over_80_scalars <- pop_scalars[age_group_id==21,]
      over_80_scalars[,age_group_id:=NULL]
      map <- data.table(expand.grid(age_group_id=expand_groups,sex_id=unique(pop_scalars[,sex_id]),
                         location_id=unique(pop_scalars[,location_id]),year_id=unique(pop_scalars[,year_id])))
      over_80_scalars <- merge(over_80_scalars,map,by=c("sex_id","year_id","location_id"))
      pop_scalars <- rbindlist(list(pop_scalars,over_80_scalars),use.names=T)
    }
    
    ## Aggregate and apply under-1 scalars if they exist in the dataset
    if(28 %in% unique(data[,age_group_id])) {
      print(paste0("Applying Under-1 aggregated scalars"))
      
      under_1_scalars <- pop_scalars[age_group_id ==2,] ## The under-5 scalars are the same for enn/lnn/pnn -- if this changes later on in life THIS MUST CHANGE
      under_1_scalars[,age_group_id:=28]
      pop_scalars <- rbindlist(list(pop_scalars,under_1_scalars),use.names=T)
    }
  }
  
  ## Specify variables to collapse by for the age, sex, and location aggregates
  age_collapse_vars <- id_vars[!id_vars %in% "age_group_id"]
  sex_collapse_vars <- id_vars[!id_vars %in% "sex_id"]
  loc_collapse_vars <- c(id_vars[!id_vars %in% "location_id"],"parent_id")

  
  ## Aggregate from level 5 locations to level 4 (India state/urbanicity to India state), etc. etc. up to Global
  if(agg_hierarchy==T) {
    ## Merge on parent_id and level to the dataset
    locations <- data.table(get_locations(level="all"))
    locations <- locations[,list(location_id,parent_id,level)]
    data <- merge(data,locations,by="location_id")

    ## Apply aggregations, rolling from bottom-up, skipping locations that already exist, and applying regional scalars
    for(agg_level in 4:end_agg_level) {
      loc_list <- locations[level == agg_level & !(location_id %in% unique(data[,location_id])),location_id] # Aggregate to parent only if the parent doesn't already exist in the datset
      
      ## Check that all the children actually exist in the source dataset, to prevent a parent location being an incomplete sum of all of its children
      child_list <- locations[level==(agg_level + 1) & parent_id %in% loc_list,location_id]

      child_exist <- unique(data[parent_id %in% loc_list,location_id])
      missing_list <- child_list[!(child_list %in% child_exist)]
      if(length(missing_list) != 0) {
        print(missing_list)
        stop(paste0("The above child locations are missing, cannot aggregate"))
      }
      
      agg <- data[parent_id %in% loc_list,lapply(.SD,sum),.SDcols=value_vars,by=loc_collapse_vars]
      setnames(agg,"parent_id","location_id")
      
      ## If we want to apply regional scalars to the data, do so here when the agg_level = 2 (region-level). Will then be carried on to levels 1 and 0
      if(loc_scalars == T & agg_level == 2) {
        mult_scalars <- function(x) return(x*agg[['scaling_factor']])
        agg <- merge(agg,pop_scalars,by=c("location_id","year_id","age_group_id","sex_id"))
        agg[,(value_vars) := lapply(.SD,mult_scalars),.SDcols=value_vars]
        agg[,scaling_factor:=NULL]
      }
      
      agg <- merge(agg,locations,by="location_id") # Get parent_id for next aggregation
  
      data <- rbindlist(list(data,agg),use.names=T)
    }
    data[,c("parent_id","level"):=NULL]
  }
  
  if(agg_sdi==T) { ## This will aggregate lowest-level locations to SDI locations (hierarchy based on 2015 SDI bins)
    locations <- data.table(get_locations(gbd_type="sdi"))
    locations <- locations[,list(location_id,parent_id,level)]
    data <- merge(data,locations,by="location_id",all.x=T)
    
    loc_list <- locations[level == 0,location_id] # Aggregate to parent SDI categories
    
    ## Check that all the children actually exist in the source dataset, to prevent a parent location being an incomplete sum of all of its children
    child_list <- locations[level==1,location_id]
    child_exist <- unique(data[parent_id %in% loc_list,location_id])
    missing_list <- child_list[!(child_list %in% child_exist)]
    if(length(missing_list) != 0) {
      print(missing_list)
      stop(paste0("The above child locations are missing, cannot aggregate"))
    }
    
    agg <- data[parent_id %in% loc_list,lapply(.SD,sum),.SDcols=value_vars,by=loc_collapse_vars]
    setnames(agg,"parent_id","location_id")
    data[,c("parent_id","level"):=NULL]
    data <- rbindlist(list(data,agg),use.names=T)
  }
  
  ## Add age aggregates for gbd compare tool and for under-1/all ages if needed 
  if(age_aggs == "gbd_compare") { 
    stopifnot("age_group_id" %in% id_vars)
    req_ages <- c(2:21)
    if(length(req_ages[!req_ages %in% unique(data[,age_group_id])]) != 0) {
      stop(paste0("These age_group_ids are not present in the dataset: ",req_ages[!req_ages %in% unique(data[,age_group_id])]))
    }
    
    ## Under-1
      under_1 <- data[age_group_id >= 2 & age_group_id <= 4,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      under_1[,age_group_id:=28]
    
    ## All Ages
      all_ages <- data[,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      all_ages[,age_group_id:=22]
    
    ## GBD Compare: Under-5, 5-14, 15-49, 50-69, 70+
      under_5 <- data[age_group_id >= 2 & age_group_id <= 5,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      under_5[,age_group_id:=1]
    
      d_5_14 <- data[age_group_id >= 6 & age_group_id <= 7,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      d_5_14[,age_group_id:=23]
    
      d_15_49 <- data[age_group_id >= 8 & age_group_id <= 14,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      d_15_49[,age_group_id:=24]
    
      d_50_69 <- data[age_group_id >= 15 & age_group_id <= 18,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      d_50_69[,age_group_id:=25]
    
      d_70plus <- data[age_group_id >= 19 & age_group_id <= 21,lapply(.SD,sum),.SDcols=value_vars,by=age_collapse_vars]
      d_70plus[,age_group_id:=26]
    
    ## Append all together
      data <- rbindlist(list(data,under_1,all_ages,under_5,d_5_14,d_15_49,d_50_69,d_70plus),use.names=T)
  }
  
  ## Aggregate to both sexes if needed
  if(agg_sex == T) {
    stopifnot("sex_id" %in% id_vars)
    req_sexes <- c(1:2)
    if(length(req_sexes[!req_sexes %in% unique(data[,sex_id])]) != 0) {
      stop(paste0("These sex_ids are not present in the dataset: ",req_sexes[!req_sexes %in% unique(data[,sex_id])]))
    }
    
    both_sexes <- data[,lapply(.SD,sum),.SDcols=value_vars,by=sex_collapse_vars]
    both_sexes[,sex_id:=3]
    data <- rbindlist(list(data,both_sexes),use.names=T)
  }
  
  return(data)
}
