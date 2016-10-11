## Purpose: Create new Lifetables based off of post-ensemble envelope results


###############################################################################################################
## Set up settings
rm(list=ls())

if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  user <- Sys.getenv("USERNAME")
  
  dir_pop <- paste0(root,"/strPath")
  
  country <- "ZAF_482"
  loc_id <- 482
  group <- "1A"
} else {
  root <- "/home/j"
  user <- Sys.getenv("USER")
  
  country <- commandArgs()[3]
  loc_id <- commandArgs()[4]
  group <- paste0(commandArgs()[5]) # Enforce it as string
  spec_name <- commandArgs()[6]
  
  dir_env_hivdel <- "strPath"
  dir_env_whiv <- "strPath"
  dir_scalar <- "strPath"
  dir_lts_hivdel <- "strPath"
  dir_lts_whiv <- "strPath"
  dir_input_hiv <- paste0("strPath",spec_name)
  dir_hiv <- paste0("strPath",spec_name)
  dir_pop <- paste0(root,"strPath")
  
  out_dir_hivdel <- "strPath"
  out_dir_whiv <- "strPath"

}

#############################################################################################
## Prep Libraries and other miscellany
## libraries
  library(haven)
  library(foreign)
  library(data.table)
  library(dplyr)
  library(reshape2)
  
  source(paste0(root,"/strPath/lt_functions.R")) # To calculate lifetables based off of mx/ax
  source(paste0(root,"strPath/calc_qx.R")) # To create 5q0 and 45q15 based off of lifetable results

## Get age map that can apply to Env and LT results
  source(paste0(root,"/strPath/get_age_map.r"))
  age_map <- data.table(get_age_map(type="lifetable"))

## Grab lt_get_pops function to get appropriate populations to pop-weight by for ages 80+ granular both sexes (use the highest age that has male/female pops for each country/year combination)
  source(paste0(root,"/strPath/lt_functions.R"))
  
## Under-1, 5-year age groups through 110, then 110+
  setnames(age_map,"age_group_name_short","age")
  age_map <- age_map[,list(age_group_id,age)]
  age_map[,age:=as.numeric(age)]
  
## Get populations to use for mx and ax sex-weighting to create a both sexes category
  weight_pop <- data.table(fread(paste0(dir_pop,"/population_gbd2015.csv")))
  weight_pop <- weight_pop[location_id == loc_id,]
  hiv_pop <- weight_pop[,list(sex_id,year,age_group_id,pop)]
  
  ## change pop in 100+ to be pop in 100, since the distinction doesn't matter here
  weight_pop[age_group_id==48,age_group_id:=44]
  for (i in unique(weight_pop[,year])) {
    cat(paste0("checking pop in ",i,"\n")); flush.console()
    for (s in unique(weight_pop[,sex_id])) {
      if (nrow(weight_pop[year == i & sex_id == s & age_group_id == 30,])==0 | is.na(weight_pop[year == i & sex_id == s & age_group_id == 30,pop])) {
        new_pop <- unique(weight_pop[year==i & sex_id == s & age_group_id==21,pop])
        weight_pop[year == i & sex_id == s & age_group_id == 30,pop:=new_pop] 
        cat(paste0("filling 80-84 pop for ",i," sex ",s,"\n")); flush.console()
      }
    }
  }
  ## if pop in 80-84 is missing, should replace with pop in 80 + for the given year
  weight_pop <- merge(weight_pop,age_map,by="age_group_id")
  if (nrow(weight_pop[is.na(pop) & age == 80,]) > 0) stop("Missing 80 pop")
  weight_pop <- weight_pop[,list(pop,location_id,year,age,sex_id)]
  setnames(weight_pop,"year","year_id")

## Get map to re-sort draws of non-HIV deaths
## Use draw maps to scramble draws so that they are not correlated over time
## This is because Spectrum output is semi-ranked due to Ranked Draws into EPP
## This is done here as opposed to raw Spectrum output because we want to preserve the draw-to-draw matching of Spectrum and lifetables, then scramble them after they've been merged together
draw_map <- fread(paste0(root,"/strPath/draw_map.csv"))
draw_map <- draw_map[location_id==loc_id,list(old_draw,new_draw)]
setnames(draw_map,"old_draw","draw")


#############################################################################################
## Bring in appropriate LTs and Envelopes

## Bring in envelopes post-ensemble
  raw_env_del <- data.table(fread(paste0(dir_env_hivdel,"/env_",country,".csv")))
  raw_env_whiv <- data.table(fread(paste0(dir_env_whiv,"/env_",country,".csv")))

## Bring in scalars from HIV-deleted to with-HIV
  env_scalar <- data.table(read_dta(paste0(dir_scalar,"/scalars_",country,".dta")))
  env_scalar <- env_scalar[age_group_id == 21,]

## Bring in lifetables pre-ensemble
  lt_del <- data.table(fread(paste0(dir_lts_hivdel,"/lt_",country,".csv")))
  lt_whiv <- data.table(fread(paste0(dir_lts_whiv,"/lt_",country,".csv")))

## Bring in HIV results and populations to convert HIV deaths to rates
  hiv_results <- data.table(fread(paste0(dir_hiv,"/hiv_death_",country,".csv")))
  setnames(hiv_pop,"year","year_id")
  
## Bring in raw Spectrum HIV results to get non-HIV deaths from Spectrum to apply the ratio of all-cause to HIV-free
## Only used to calculate Group 1 lifetables
  spec_hiv_results <- data.table(fread(paste0(dir_input_hiv,"/",country,"_ART_deaths.csv")))
  spec_hiv_results <- spec_hiv_results[,list(sex_id,year_id,age_group_id,run_num,non_hiv_deaths)]
  setnames(spec_hiv_results,"run_num","draw")
  spec_hiv_results[,draw:=draw-1]
  spec_hiv_results <- merge(spec_hiv_results,draw_map,by=c("draw"))
  spec_hiv_results[,draw:=new_draw]
  spec_hiv_results[,new_draw:=NULL]
  

#############################################################################################
## Define functions for formatting data appropriately for append/merging

  ## Format lifetables to be GBD-ized
    format_lts <- function(data) {
      data <- data[,list(sex,year,age,draw,ax,mx,qx)]
      setnames(data,c("sex","year"),c("sex_id","year_id"))
      data[sex_id==1,sex:="male"]
      data[sex_id==2,sex:="female"]
      data[sex_id==3,sex:="both"]
      data <- merge(data,age_map,by="age")
      return(data)
    }

  ## Extract ax values to merge onto the final dataset
    get_lt_ax <- function(data) {
      data <- data[,list(sex_id,year_id,age_group_id,draw,ax)]
      return(data)
    }
    
  ## Extract under-5 values from pre-reckoning lifetables
    get_u5_lt <- function(data) {
      data <- data[age_group_id == 5 | age_group_id == 28,list(sex_id,year_id,age_group_id,draw,mx)]
      return(data)
    }
    
  ## Extract HIV estimates for under-5 to add or subtract from pre-reckoning lifetables
    get_u5_hiv <- function(data) {
      data <- data[age_group_id <= 5,]
      setnames(data,"sim","draw")
      
      ## Collapse NN granular to under-1 
      data[age_group_id <=4, age_group_id := 28]
      data <- data.table(data)[,lapply(.SD,sum),.SDcols="hiv_deaths",
                               by=c("age_group_id","sex_id","year_id","draw")] 
      
      ## Convert from deaths to rate
      data <- merge(data,hiv_pop,by=c("sex_id","year_id","age_group_id"))
      data[,mx_hiv:=hiv_deaths/pop]
      data <- data[,list(age_group_id,sex_id,year_id,draw,mx_hiv)]
      return(data)
    }

  
  ## Pull out under-5 values from LTs, apply HIV, and output mx values for both, using get_u5_lt and get_u5_hiv functions
  ## This is because we want to preserve U5 results from MLT as opposed to using U5 mx values derived from age-sex results, which are inconsistent
    create_u5_mx <- function(data) {
      ## Input is lifetable from get_u5_lt, either with-HIV or HIV-free depending on the group
      ## For all groups, we want to preserve the mx values from the with-HIV lifetable, then subtract out HIV
      ## Otherwise, we want to preserve the mx from the HIV-free lifetable and add HIV to it to create with-HIV
      
      hiv_u5 <- get_u5_hiv(hiv_results)
      data <- merge(data,hiv_u5,by=c("age_group_id","sex_id","year_id","draw"))
      
      ## Here, data is whiv and we subtract HIV to get hiv_deleted
      data[mx_hiv > (.9*mx), mx_hiv := .9*mx] # Impose a cap on HIV so that it doesn't exceed 90% of the lifetable mx (similar to what is done in the ensemble model for envelope)
      data[,mx := mx - mx_hiv]
      data[,mx_hiv := NULL]

      return(data)
    }
    
  ## GROUP 1 COUNTRIES: Pull out under-5 values from LTs
  ## Use this instead of get_u5_lt and create_u5_mx only in the case of Group 1 countries
    ## Extract under-5 values from pre-reckoning lifetables
    
    get_u5_g1_hiv <- function(data) {
      data <- data[age_group_id <= 5,]
      setnames(data,"sim","draw")
      
      ## Collapse NN granular to under-1 
      data[age_group_id <=4, age_group_id := 28]
      data <- data.table(data)[,lapply(.SD,sum),.SDcols="hiv_deaths",
                               by=c("age_group_id","sex_id","year_id","draw")] 
      
      ## Convert from deaths to rate
      data <- merge(data,hiv_pop,by=c("sex_id","year_id","age_group_id"))
      data[,mx_hiv:=hiv_deaths/pop]
      data <- data[,list(age_group_id,sex_id,year_id,draw,mx_hiv)]
      return(data)
    }
    
    ## Extract non-HIV death estimates for under-5 to add or subtract from pre-reckoning lifetables
    get_u5_g1_hiv_free <- function(data) {
      data <- data[age_group_id <= 5,]
      
      ## Collapse NN granular to under-1 
      data[age_group_id <=4, age_group_id := 28]
      data <- merge(data,hiv_pop,by=c("sex_id","year_id","age_group_id"))
      data[,non_hiv_deaths:=non_hiv_deaths*pop]
      
      data <- data.table(data)[,lapply(.SD,sum),.SDcols=c("non_hiv_deaths","pop"),
                               by=c("age_group_id","sex_id","year_id","draw")] 
      
      ## Convert from deaths to rate
      data[,mx_spectrum_free:=non_hiv_deaths/pop]
      data <- data[,list(age_group_id,sex_id,year_id,draw,mx_spectrum_free)]
      return(data)
    }
    
    create_u5_mx_group1 <- function(data) {
      ## We want to use the ratio of Spectrum HIV-deleted to with-HIV to convert lifetable with-HIV to lifetable HIV-free
      ## data is with-HIV dataset from get_u5_lt, already under-1 non-granular
      ## We want to take in the spectrum NN results, collapse to under-1, merge on with the u5 HIV, calculate the 
      hiv_u5 <- get_u5_g1_hiv(hiv_results)
      spec_free <- get_u5_g1_hiv_free(spec_hiv_results)
      
      lt_u5 <- merge(data,hiv_u5,by=c("age_group_id","sex_id","year_id","draw"))
      
      ## First, convert the non-HIV Spectrum deaths and Envelope HIV-free from the rate space to numbers (no need since they're in the same space and we're just dividing?)
      lt_u5 <- merge(lt_u5,spec_free,by=c("age_group_id","sex_id","year_id","draw"))

      ## Add Spectrum HIV-free and HIV together to get Spectrum all-cause
      lt_u5[,spec_whiv := mx_hiv+mx_spectrum_free]
      
      ## Create ratio to Spectrum HIV-free from Spectrum with-HIV
      ## Note: This ratio is really low sometime (e.g. in ZWE age_group_id = .7, the lowest ratio is .03 which means that 97% of all deaths are going to HIV)
      lt_u5[,ratio_free_whiv := mx_spectrum_free/spec_whiv]
      
      ## Apply this ratio to lifetable with-HIV to generate lifetable HIV-free
      lt_u5[,mx := mx * ratio_free_whiv]

      ## Bring it back onto the primary dataset
      lt_u5 <- lt_u5[,list(age_group_id,sex_id,year_id,draw,mx)]
      return(lt_u5)
    } 

  ## Extract lifetable over-80 granular results to be scaled using envelope scalars
    get_lt_mx <- function(data) {
      data <- data[as.numeric(age) >= 80,] # Only need 80 and over granular age groups
      data <- data[,list(age_group_id,sex_id,year_id,draw,mx)]
      return(data)
    }
    
  ## Create scaled LT over-80 results
  ## Depending on the group, we want to either go from all-cause to HIV-free or HIV-free to all-cause (Group 1A)
    scale_lt_over80 <- function(lt_data,scalar_data) {
      scalar_data <- scalar_data[,list(sex_id,year_id,sim,scalar_del_to_all)] # Drop age_group_id because we apply 80+ scalar equally to all over-80 granular groups
      setnames(scalar_data,c("sim","scalar_del_to_all"),c("draw","scalar"))
      lt_data <- merge(lt_data,scalar_data,by=c("sex_id","year_id","draw"))
      
      ## If group is anything except 1A, convert to HIV-free by all-cause/scalar
      ## Otherwise, convert to all-cause by HIV-free * scalar
      if(group != "1A") {
        lt_data[,mx:=mx/scalar]
      } else {
        lt_data[,mx:=mx*scalar]
      }
      lt_data <- lt_data[,list(sex_id,year_id,draw,age_group_id,mx)]
      return(lt_data)
    }

  ## Format the envelope to rbind appropriately
    format_env <- function(data) {
      data <- melt(data,id.vars=c("location_id","sex_id","year_id","age_group_id","pop"),variable.name="draw",variable.factor=F)
      data[,draw:=as.numeric(gsub("env_","",draw))]
      data <- data[age_group_id > 5 & age_group_id != 21,]
      data[,mx := value/pop]
      data <- data[,list(sex_id,year_id,age_group_id,mx,draw)]
      return(data)
    }

  ## Add both sexes to the dataset
  prep_both_sexes <- function(data,type) {
    data <- merge(data,age_map,by="age_group_id")
    data <- merge(data,weight_pop,by=c("age","sex_id","year_id"),all.x=T)
    data[,location_id:=loc_id]
    setnames(data,"year_id","year")
    data_pops <- data.table(lt_get_pops(as.data.frame(data[,list(age,sex_id,location_id,year,draw,pop)]),agg_var="sex_id",draws=T,idvars=c("location_id","year")))
    setnames(data,"year","year_id")
    data[,pop:=NULL]
    data <- merge(data,data_pops,by=c("age","sex_id","location_id","year_id","draw"),all.x=T)
    if (nrow(data[is.na(pop),]) > 0) stop("missing pops")
    data[,age:=NULL]
    
    ## Here, pop-weight mx and death-weight ax to collapse to both sexes, then unweight and add back onto the original dataset
    both <- copy(data)
    both[,mx:=mx*pop]
    both[,ax:=ax*mx]
    setkey(both,age_group_id,location_id,year_id,draw)
    both <- both[,list(mx=sum(mx),ax=sum(ax),pop=sum(pop)),by=key(both)]
    both[,ax:=ax/mx]
    both[,mx:=mx/pop]
    both[,sex_id:=3]
    
    data <- rbindlist(list(data,both),use.names=T)
    data[,c("pop","location_id"):=NULL]

    ## We want to preserve the U5 results for with-HIV for both sexes from the original prematch file
    if(type == "whiv") {
      data <- data[(age_group_id != 5 & age_group_id != 28) | sex_id != 3,]
      data <- rbindlist(list(data,whiv_both_u5),use.names=T)
    }
     
    return(data)
  }

  ## Save MX and AX output as 10 separate files for ease of computation
    save_mx_ax <- function(data,type) {
      data <- data[,list(age_group_id,sex_id,year_id,draw,mx,ax)]
      data[,location_id:=loc_id]
      for(i in 1:10) {
        iminus <- i - 1
        save_file <- data[draw < (i*100) & draw >= (iminus * 100),]
        if(type=="whiv") write.csv(save_file,paste0(out_dir_whiv,"/mx_ax/mx_ax_",iminus,"_",country,".csv"),row.names=F)
        if(type=="hiv_free") write.csv(save_file,paste0(out_dir_hivdel,"/mx_ax/mx_ax_",iminus,"_",country,".csv"),row.names=F)
      }
    }

  ## Format combined file for LT function
    format_for_lt <- function(data) {
      data$qx <- 0
      data[sex_id==1,sex:="male"]
      data[sex_id==2,sex:="female"] 
      data[sex_id==3,sex:="both"]
      data <- merge(data,age_map,by="age_group_id")
      data[,id:=draw]
      setnames(data,"year_id","year")
      
      return(data)
    }
    
  ## Generate ENN/LNN/PNN qx values by converting mx to qx and rescaling to under-1 qx
    extract_nn_qx <- function(env_data,lt_data) {
      lt_data <- data.table(lt_data)
      
      env_data <- melt(env_data,id.vars=c("location_id","sex_id","year_id","age_group_id","pop"),variable.name="draw",variable.factor=F)
      env_data[,draw:=as.numeric(gsub("env_","",draw))]
      env_data[,mx := value/pop]
      
      ## Convert envelope mx values to qx
      env_data <- env_data[age_group_id <= 4,]
      env_data[age_group_id==2,time:=7/365]
      env_data[age_group_id==3,time:=21/365]
      env_data[age_group_id==4,time:=(365-21-7)/365]

      env_data[,qx:= 1 - exp(-1 * time * mx)]
      env_data[,c("time","mx","pop"):=NULL]
      
      ## Scale qx values to under-1 qx from the LT
      env_data[,age_group_id:=paste0("qx_",age_group_id)]
      qx_nn <- data.table(dcast(env_data,sex_id+year_id+draw~age_group_id,value.var="qx"))
      
      ## Merge on under-1 qx from LT process
      lt_data <- lt_data[age==0,list(age,sex_id,year,qx,draw)]
      setnames(lt_data,"qx","qx_under1")
      setnames(lt_data,"year","year_id")
      lt_data[,age:=NULL]
      
      ## Generate proportions of under-1 deaths that happened in each specific NN age group
      qx_nn <- merge(qx_nn,lt_data,by=c("sex_id","year_id","draw"))
      qx_nn[,prob_2:=qx_2/qx_under1]
      qx_nn[,prob_3:=(1-qx_2) * qx_3/qx_under1]
      qx_nn[,prob_4:=(1-qx_3) * (1-qx_2) * qx_4/qx_under1]
      
      qx_nn[,scale:=1/(prob_2+prob_3+prob_4)]
      qx_nn[,prob_2:=prob_2*scale]
      qx_nn[,prob_3:=prob_3*scale]
      qx_nn[,prob_4:=prob_4*scale]
      
      qx_nn[,qx_2:=qx_under1 * prob_2]
      qx_nn[,qx_3:=(qx_under1 * prob_3)/(1-qx_2)]
      qx_nn[,qx_4:=(qx_under1 * prob_4)/((1-qx_2)*(1-qx_3))]
      
      qx_nn <- qx_nn[,list(sex_id,year_id,draw,qx_2,qx_3,qx_4)]
      
      ## Output Results
      qx_nn <- melt(qx_nn,id=c("sex_id","year_id","draw"))
      qx_nn[,age_group_id:=as.numeric(gsub("qx_","",variable))]
      qx_nn[,variable:=NULL]
      setnames(qx_nn,"value","qx")
      return(qx_nn)
    }


#############################################################################################
## Format data appropriately for append/merging

## Format lifetables
  lt_del <- format_lts(lt_del)
  lt_del <- lt_del[sex_id != 3,] 
  lt_whiv <- format_lts(lt_whiv)
  # Steal both sexes under-5 from here so that this will be guaranteed to preserve with-HIV 5q0 for both sexes
  whiv_both_u5 <- lt_whiv[sex_id == 3 & (age_group_id == 5 | age_group_id == 28),list(sex_id,year_id,age_group_id,draw,mx,ax)]
  lt_whiv <- lt_whiv[sex_id != 3,]

## Get ax values
  del_ax <- get_lt_ax(lt_del)
  whiv_ax <- get_lt_ax(lt_whiv)
  
## Get u5 mx values for all lifetables using pre-reckoning lifetables of those we want to stay the same, combined with HIV values from ensemble
if(group %in% c("1A","1B")) {
  whiv_u5 <- get_u5_lt(lt_whiv)
  del_u5 <- create_u5_mx_group1(whiv_u5)
} else {
  whiv_u5 <- get_u5_lt(lt_whiv)
  del_u5 <- create_u5_mx(whiv_u5)
}

## Also pull out over-80 mx
if(group == "1A") {
  del_80plus <- get_lt_mx(lt_del)
  whiv_80plus <- scale_lt_over80(del_80plus,env_scalar)
} else {
  whiv_80plus <- get_lt_mx(lt_whiv)
  del_80plus <- scale_lt_over80(whiv_80plus,env_scalar)
}

## Format envelopes for rbinding
  env_del <- format_env(raw_env_del)
  env_whiv <- format_env(raw_env_whiv)

## Combine envelope and over-80 mx results
  env_del <- rbind(env_del,del_80plus,del_u5)
  env_del <- merge(env_del,del_ax,by=c("age_group_id","sex_id","year_id","draw"))
  env_del <- prep_both_sexes(env_del,"hiv_del") ## Create both-sexes aggregates of mx and ax

  save_mx_ax(env_del,"hiv_free")
  env_del <- data.frame(format_for_lt(env_del))

## Create both-sexes aggregates
  env_whiv <- rbind(env_whiv,whiv_80plus,whiv_u5)
  env_whiv <- merge(env_whiv,whiv_ax,by=c("age_group_id","sex_id","year_id","draw"))
  env_whiv <- prep_both_sexes(env_whiv,"whiv") ## Create both-sexes aggregates of mx and ax

  save_mx_ax(env_whiv,"whiv")
  env_whiv <- data.frame(format_for_lt(env_whiv))
  

#############################################################################################
## Run LT function
  lt_new_del <- lifetable(env_del,cap_qx=1)
  lt_new_del$id <- lt_new_del$location_id <- NULL
  lt_new_whiv <- lifetable(env_whiv,cap_qx=1)
  lt_new_whiv$id <- lt_new_del$location_id <- NULL

## Create and output with-HIV neonatal granular qx values based on the lifetables above
  nn_qx_del <- extract_nn_qx(raw_env_del,lt_new_del)
  write.csv(nn_qx_del,paste0(out_dir_hivdel,"/qx/qx","_",country,".csv"),row.names=F)
  
  nn_qx_whiv <- extract_nn_qx(raw_env_whiv,lt_new_whiv)
  write.csv(nn_qx_whiv,paste0(out_dir_whiv,"/qx/qx","_",country,".csv"),row.names=F)
  

#############################################################################################
## Write LT files
  write.csv(lt_new_del,paste0(out_dir_hivdel,"/lt_",country,".csv"),row.names=F)
  write.csv(lt_new_whiv,paste0(out_dir_whiv,"/lt_",country,".csv"),row.names=F)
  

#############################################################################################
## Calculate mean 5q0 and mean 45q15 values
  ## HIV-free
  mean_5q0 <- calc_qx(data.table(lt_new_del),age_start=0,age_end=5,id_vars=c("sex_id","year","draw"))
  setnames(mean_5q0,"qx_5q0","mean_5q0")
  mean_5q0 <- mean_5q0[,lapply(.SD,mean),.SDcols="mean_5q0", by=c("sex_id","year")]
  mean_5q0[,location_id:=loc_id]
  
  mean_45q15 <- calc_qx(data.table(lt_new_del),age_start=15,age_end=60,id_vars=c("sex_id","year","draw"))
  setnames(mean_45q15,"qx_45q15","mean_45q15")
  mean_45q15 <- mean_45q15[,lapply(.SD,mean),.SDcols="mean_45q15",by=c("sex_id","year")]
  mean_45q15[,location_id:=loc_id]
  
  write.csv(mean_5q0,paste0(out_dir_hivdel,"/mean_qx/mean_5q0_",country,".csv"),row.names=F)
  write.csv(mean_45q15,paste0(out_dir_hivdel,"/mean_qx/mean_45q15_",country,".csv"),row.names=F)
  
  ## With-HIV
  mean_5q0 <- calc_qx(data.table(lt_new_whiv),age_start=0,age_end=5,id_vars=c("sex_id","year","draw"))
  setnames(mean_5q0,"qx_5q0","mean_5q0")
  mean_5q0 <- mean_5q0[,lapply(.SD,mean),.SDcols="mean_5q0", by=c("sex_id","year")]
  mean_5q0[,location_id:=loc_id]
  
  mean_45q15 <- calc_qx(data.table(lt_new_whiv),age_start=15,age_end=60,id_vars=c("sex_id","year","draw"))
  setnames(mean_45q15,"qx_45q15","mean_45q15")
  mean_45q15 <- mean_45q15[,lapply(.SD,mean),.SDcols="mean_45q15",by=c("sex_id","year")]
  mean_45q15[,location_id:=loc_id]
  
  write.csv(mean_5q0,paste0(out_dir_whiv,"/mean_qx/mean_5q0_",country,".csv"),row.names=F)
  write.csv(mean_45q15,paste0(out_dir_whiv,"/mean_qx/mean_45q15_",country,".csv"),row.names=F)
  

#############################################################################################
## Summarize the LT files
  summarize_lt <- function(data) {
    varnames <- c("ax","mx","qx")
    data <- data.table(data)[,lapply(.SD,mean),.SDcols=varnames,
                                         by=c("age","age_group_id","sex_id","sex","year","n")]
    data[,id:=1]

    # Rerun lifetable function to recalculate life expectancy and other values based on the mean lifetable
    data <- lifetable(data.frame(data),cap_qx=1)
    data$id <- NULL
    return(data)
  }
  
  gen_lt_ci <- function(data) {
    varnames <- c("ax","mx","qx","px","lx","dx","nLx","Tx")
    data_lower <- data.table(data)[,lapply(.SD,quantile())]
  }
  
  
  lt_new_del <- summarize_lt(lt_new_del)
  lt_new_del$location_id <- loc_id
  lt_new_whiv <- summarize_lt(lt_new_whiv)
  lt_new_whiv$location_id <- loc_id
  
  write.csv(lt_new_del,paste0(out_dir_hivdel,"/summary_",country,".csv"),row.names=F)
  write.csv(lt_new_whiv,paste0(out_dir_whiv,"/summary_",country,".csv"),row.names=F)

  