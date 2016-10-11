
## Given a data.table and a range of ages, this function calculates qx values for the aggregated qx values from the granular age groups
## For example, if you want to calculate 5q0, run:
##    calc_qx(data,age_start=0,age_end=5)
## The dataset must include all the ID variables that you want to preserve in this instance
## Note that you cannot have any ID variables that are age-specific (e.g. other lifetable values, etc.).
## The dataset does need to have age_group_id, but do NOT specify it within the id_vars option

## Will return a dataset with id_vars and a variable called qx_#q#, where the first is age_end - age_start, and the second is age_start

## NOTE: For aggregating any q0 values, you need to have the 1q0 value NOT the ENN/LNN/PNN values in the dataset

## Essentially, this code is doing, for example, 5q0 = 1 - (1-1q0) * (1-4q1)

calc_qx <- function(data,age_start,age_end,id_vars="") {
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"
  require(data.table)
  source(paste0(root,"/strPath/get_age_map.r"))  

  ## Get age group IDs that you need
  age_map <- data.table(get_age_map(type="lifetable"))
  age_map <- age_map[age_group_years_start >= age_start & age_group_years_end <= age_end] # Subset the ages to the ones we actually want
  if(age_start>age_end) stop("Age start can't be larger than age end")
  if(!age_start %in% unique(age_map[,age_group_years_start])) stop(paste0("Your range needs to include a valid age_start rather than ",age_start))
  if(!age_end %in% unique(age_map[,age_group_years_end])) stop(paste0("Your range needs to include a valid age_end rather than ",age_end))
  age_map <- age_map[,list(age_group_id)]
  req_ages <- unique(age_map[,age_group_id])
  
  age_span <- age_end - age_start
  
  ## Check that it is a data.table
  if(!is.data.table(data)) stop("The input dataset must be in data.table format")
  
  ## Check that id_vars don't include any obvious variables
  if ("qx" %in% id_vars) stop("qx cannot be an id_var")
  if ("px" %in% id_vars) stop("px cannot be an id_var")
  
  ## Subset to appropriate columns
  if(!"qx" %in% names(data)) stop("qx needs to be present in the dataset")
  data <- data[,.SD,.SDcols=c(id_vars,"qx","age_group_id")]
  
  ## Only keep the needed ages
  data <- merge(data,age_map,by="age_group_id")
  
  ## Check that age_group_id exists in the data and is not listed as an ID variable and contains all age groups you need
  if(!"age_group_id" %in% names(data)) stop("age_group_id needs to be present in the dataset")
  if("age_group_id" %in% id_vars) stop("age_group_id should not be in the id_vars list")
  age_err_count <- 0
  age_list <- ""
  for(age in req_ages) {
    if(!age %in% unique(data[,age_group_id])) {
      age_err_count <- age_err_count + 1
      age_list <- c(age_list,age)
    }
  }
  if(age_err_count > 0) stop("Need a full set of age groups, missing these age_group_ids: ",paste(age_list,collapse=" "))
    
  data[,px:=1-qx]
  data[,qx:=NULL]
  
  ## Collapse on the product of the transformed qx values
  nrow_master <- nrow(data)
  data <- data[,lapply(.SD,prod),.SDcols="px",by=id_vars]
  
  ## Check that we have lost the correct number of rows 
  ## Basically, if there are 5 age groups within, the resulting dataset should be 1/5th the size of the original
  nrow_collapse <- nrow(data)
  if(nrow_collapse == nrow_master) stop("You have specified an id variable that is unique within age_group_id -- re-check your variables")
  if(nrow_collapse * length(req_ages) != nrow_master) stop("The input dataset is not square (e.g. not all required age groups are present for all combinations of id_vars)")
  
  ## Generate new qx based on the product of the collapsed px values
  data[,paste0("qx_",age_span,"q",age_start) := 1 - px]
  data[,px:=NULL]
  return(data)
}
