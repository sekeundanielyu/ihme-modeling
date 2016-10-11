###############################################################################
## Description: Compile results of all holdouts and select parameters
################################################################################

# source("strPath/06_select_parameters.r")


  rm(list=ls())
  library(foreign); library(data.table); library(arm)

  if (Sys.info()[1] == "Linux") root <- "/home/j" else root <- "J:"

  cc <- commandArgs()[3]
  #cc <- "DEU"
  in_dir <- "strPath"
  user <- Sys.getenv("USER") # Default for linux user grab. "USERNAME" for Windows
  code_dir <- paste0("strPath")

  setwd(paste(root, "strPath", sep=""))
  
  gen_new <- 1

## compile all loss files for countries in each data country
  
  countries <- as.data.frame(read.csv("strPath/first_stage_results1.csv"))

  #countries <- unique(countries[,c("ihme_loc_id","sex","type","mse")])
  countries <- unique(countries[,c("ihme_loc_id","sex","type")])#temp
  countries$iso3_sex <- paste(countries$ihme_loc_id,countries$sex,sep = "_")
  countries <- data.table(countries)
  setkey(countries,iso3_sex)
 
  ## This will combine all files within the directory with the .txt post-fix
  ## NOTE: not all 05 jobs will generate results, because if the test dataset is empty it won't compute
  ## So this is a "greedy" but not specific command
  ## If files don't produce because of some other reason besides the empty test dataset issue, this code WILL NOT CATCH IT


  if(gen_new == 1) {
    command <- paste0("sh ",paste0(code_dir,"/combine_txt.sh "),in_dir," ", cc)
    system(command)
  }


  
  Sys.sleep(5) # Wait for file to resolve itself
  
  
  loss <- read.csv(paste0(in_dir,"/result/combined_", cc ,".txt"))
  loss$iso3_sex <- paste(loss$ihme_loc_id,loss$sex,sep = "_")
  loss$are <- abs(as.numeric(loss$re))
  loss <- data.table(loss)
  setkey(loss,iso3_sex)
  
  # Merge type descriptions onto the loss results
  loss <- countries[loss]


  
  ###########################################################
  # exclude combinations that we don't want to consider
  ###########################################################
  
  rr = unique(loss$region_name)

  pop20mill <- read.csv(paste0(root, "strPath/pop_over_20_million.csv"))
  large_pops <- unique(pop20mill$ihme_loc_id)
  
  # wait until first stage finishes running so we can look at what kinds of data each location has
#   while(!file.exists(paste0(root, "strPath/input_data.txt"))){
#     Sys.sleep(30)
#   }
  
  inputs <- read.csv(paste0(root, "strPath/input_data.txt"), stringsAsFactors=F)
  
  # get list of countries with both vr and sibling data 
  vrsibs <- list()
  count=0
  for(x in unique(inputs$ihme_loc_id)){
    types <- unique(inputs[inputs$ihme_loc_id==x,]$source_type)
    if(("VR" %in% types) & ("SIBLING_HISTORIES" %in% types)){
      count = count +1
      vrsibs[[count]] <- x
      
    }
  }
  
  srslist <- list()
  count=0
  for(x in unique(inputs$ihme_loc_id)){
    types <- unique(inputs[inputs$ihme_loc_id==x,]$source_type)
    if(("DSP" %in% types) | ("SRS" %in% types)){
      count = count +1
      srslist[[count]] <- x
      
    }
  }

  incompVR <- list()
  count=0
  for(x in unique(inputs$ihme_loc_id)){
    temp <- inputs[inputs$ihme_loc_id==x &
                     inputs$source_type=="VR" &
                     inputs$category != "complete" &
                     !is.na(inputs$source_type) &
                     !is.na(inputs$category),]
    if(nrow(temp)>0){
      count = count +1
      incompVR[[count]] <- x
      
    }
  }

  sibs_small <- unique(inputs[inputs$type=="sibs_small",]$ihme_loc_id)
  type <- unique(inputs[inputs$ihme_loc_id==cc,]$type)
  special_types <- c("sibs_small",
                     "sparse_data_complete VR only",
                     "sparse_data_other",
                     "sparse_data_VR only",
                     "sparse_data_VR plus")

  # get a list of countries with complete VR

  vr <- list()
  count=0
  for(x in unique(inputs$ihme_loc_id)){
    types <- unique(inputs[inputs$ihme_loc_id==x,]$source_type)
    categories <- unique(inputs[inputs$ihme_loc_id==x,]$category)
    if(("VR" %in% types) & ("complete" %in% categories)){
      count = count +1
      vr[[count]] <- x
      
    }
  }


  # these parameters must also be set in 04 step (in 04 step it must cover all possibilities but doesn't have to be restricted to just the ones we are testing in this stage)
  get_start_lambda <- function(cc){
    if(cc %in% large_pops){
      start <- .1
    } else { # set to 0.6 if small pop - these can then be modified with later conditions
      start <- .6
    }
    
    # set parameters if location has both VR and sibs
    if(cc %in% vrsibs){
      start <- .6
    }
    
    # set parameters if location has SRS or DSP
    if(cc %in% srslist){
      start <- .6
    }
    
    # set parameters if location has incomplete VR
    if(cc %in% incompVR){
      start <- .6
    }
    
    # set parameters in Western Europe to start at .1
    if(rr %in% c("Western_Europe", "Western_Europe2")){
      start <- .1
    }
    
    # set parameters in Central Asia to start at .6
    if(rr=="Central_Asia"){
      start <- .6
    }
    
    # set parameters in North Africa and the Middle East to start at .6
    if(rr=="North_Africa_and_Middle_East"){
      start <- .6
    }
    
    # set parameters in Southeast Asia to start at .6
    if(rr=="Southeast_Asia"){
      start <- .6
    }
    
    # set parameters in Eastern Europe to start at .1 if they have complete VR

    if((rr=="Eastern_Europe") & (cc %in% vr)){
      start <- .1
    }
    
    if(rr=="North_Africa_and_Middle_East"){
      start <- .1
    }
   
    if(type %in% special_types){
      start <- .6
    }
    
    if(cc %in% c("IRN", "QAT", "ISL", "GRL",
                 "AND", "CYP", "DNK", "FIN",
                 "LUX", "MLT", "PAL", "OMN",
                 "KWT" )){
      start <- .6
    }
    
    if(grepl("GBR_", cc)){
      start <- .6
    }
      
    if(type == "sibs_small"){
      start <- .6
    }
    
    return(start)
  }



get_end_lambda <- function(cc){
  
  # set default
  end <- .9 
  
  if(rr=="Eastern_Europe"){
  end <- .3
  }
  
  # set highest possible value of cc's in Caribbean to .3
  if(rr=="Caribbean"){
    end <= .3
  }
  
  # set highest possible value of cc's in Caribbean to .3
  if(rr=="Cental_Asia"){
    end <= .3
  }
  
  if(rr=="North_Africa_and_Middle_East"){
    end <- .4
  }
  
  if(grepl("USA_", cc)){
    end <- .3
  }
  
  # set highest possible value of BGR to .3
  if(cc=="BGR"){
    end <- .3 
  }
  
  # set highest possible value of SVK to .3
  if(cc=="SVK"){
    end <- .3 
  } 
  
  if(type %in% special_types){
    end <- .9
  }
  
#   if(type == "sibs_small"){
#     end <- .3
#   }

  return(end)
}



get_start_scale <- function(cc){
  
  start <- 5
  if(rr=="Caribbean"){
    start <- 15
  }
  
  if(rr %in% c("Central_Sub_Saharan_Africa",
               "Eastern_Sub_Saharan_Africa",
               "Southern_Sub_Saharan_Africa",
               "Western_Sub_Saharan_Africa ")){
    start <- 10
  }
  
  if(rr=="Southeast_Asia"){
    start <- 10
  }
  
  
  if(grepl("IND_", cc)){
    start <-15 
  }
  
  if(cc=="COD"){
    start <- 15
  }
  
  if(cc %in% sibs_small){
    start <- 15
  }
  
  if(type=="sparse_data_other"){
    start <- 10
  }
  if(rr=="Central_Europe"){
    start <- 10
  }
  if(cc=="BLR"){
    start <- 10
  }
  
  return(start)
}


get_end_scale <- function(cc){
  end <- 20
  
  return(end)
}
  
  start_lambda <- get_start_lambda(cc)
  end_lambda <- get_end_lambda(cc)

  start_scale <- get_start_scale(cc)
  end_scale <- get_end_scale(cc)

# set values for specific countries 
# 
#  if(cc=="BDI"){
#    start_lambda=.3
#    end_lambda=.3
#  }

  if(cc=="BHR"){
    start_lambda=.4
    end_lambda=.4
  }

  if(cc=="CYP"){
    start_lambda=.2
    end_lambda=.2
  }

  if(cc=="DNK"){
    start_lambda =.1
    end_lambda = .1
  }

  if(cc=="ARM"){
    start_lambda =.2
    end_lambda = .2
  }

  if(cc=="AZE"){
    start_lambda =.2
    end_lambda = .2
  }

  if(cc=="SVN"){
    start_lambda =.2
    end_lambda = .2
  }
  
  
  if(cc=="RWA"){
    start_lambda =.3
    end_lambda = .3
  }
  
  

######################################
## Deal with incompatible params
  if(start_lambda > end_lambda){
    start_lambda <- end_lambda - .1
  }
######################################

# amp changes
  loss <- loss[!(loss$type =="sparse_data_VR plus") | (loss$type=="sparse_data_VR plus" & loss$amp2x ==2),] 
# set sibs small locations amp to 2

  loss <- loss[!(loss$type =="sibs_small") | (loss$type=="sibs_small" & loss$amp2x ==2),] 
  loss <- loss[!(loss$type =="sparse_data_other") | (loss$type=="sparse_data_other" & loss$amp2x ==2),] 


  print(start_lambda)
  loss <- loss[loss$lambda >= start_lambda & loss$lambda <=end_lambda,]
  loss <- loss[loss$scale >= start_scale,]
  print(table(loss$lambda))              
  
    
  # Get mean of ARE and coverage across sims, and apply loss function
  setkey(loss,type,scale,amp2x, lambda, zeta)
  loss <- loss[,list(are = mean(are), coverage = mean(coverage)),by=key(loss)]

  write.csv(loss, paste0(in_dir,"/means/loss_means_", cc ,".txt"))
  
  
  
