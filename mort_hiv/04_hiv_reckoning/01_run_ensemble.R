## Purpose: Create new Lifetables based off of post-ensemble envelope results


###############################################################################################################
## Set up settings
rm(list=ls())
library(data.table); library(foreign); library(plyr); library(reshape2)

## Setup filepaths
  if (Sys.info()[1]=="Windows") {
    root <- "J:" 
    user <- Sys.getenv("USERNAME")
    
    country <- "USA_573"
    group <- "2A"
    spec_name <- ""
  
  } else {
    root <- "/home/j"
    user <- Sys.getenv("USER")
    
    country <- commandArgs()[3]
    group <- paste0(commandArgs()[4]) # Enforce it as string
    spec_name <- commandArgs()[5]
    
    spec_sim_dir <- paste0("/strPath/",spec_name)
    
    pop_dir <- paste0(root,"/strPath")
    lt_sim_dir <- "/strPath"
    env_dir <- "/strPath"
    stgpr_dir <- "/strPath"
    whiv_dir <- "/strPath"
    hiv_free_dir <- "/strPath"
    out_dir_hiv <- paste0("/strPath/",spec_name)
  }

## Grab functions etc.
  locations <- data.table(fread(paste0(root,"/strPath/locations.csv")))
  loc_id <- locations[ihme_loc_id==country,location_id]
  loc_name <- locations[ihme_loc_id==country,location_name]
  
  age_map <- data.table(fread(paste0(whiv_dir,"/age_map.csv")))
  age_map <- age_map[age_group_id <=28,list(age_group_name_short,age_group_id)] # Don't want 80 to 84
  setnames(age_map,"age_group_name_short","age_group_name")
  
  ## Use draw maps to scramble draws so that they are not correlated over time
  ## This is because Spectrum output is semi-ranked due to Ranked Draws into EPP
  ## Then, it propogates into here
  ## This is done here as opposed to raw Spectrum output because we want to preserve the draw-to-draw matching of Spectrum and lifetables, then scramble them after they've been merged together
  draw_map <- fread(paste0(root,"/strPath/draw_map.csv"))
  draw_map <- draw_map[location_id==loc_id,list(old_draw,new_draw)]
  setnames(draw_map,"old_draw","sim")

  
###############################################################################################################
## Bring in required input files

## Population
  pop <- data.table(fread(paste0(pop_dir,"/population_gbd2015.csv")))
  pop <- pop[location_id == loc_id & sex_id != 3 & (age_group_id <= 21 | age_group_id == 28), list(year,sex_id,age_group_id,pop)]
  
  setnames(pop,"pop","pop_gbd")

  
## HIV-Free and With-HIV Lifetables
  format_lts <- function(data,lt_type) {
    data <- data[age<=80 & sex !=3,list(sex,year,age,draw,mx,lx,Tx)]
    data[age==80, mx:=lx/Tx] # Approximate 80+ mx by taking lx/tx
    data <- data[,list(sex,year,age,draw,mx)]
    setnames(data,c("draw","mx","sex"),c("sim",paste0("mx_env_",lt_type),"sex_id"))
  }
  
  lt_hiv_free <- data.table(fread(paste0(lt_sim_dir,"/hiv_free/lt_",country,".csv")))
  lt_hiv_free <- format_lts(lt_hiv_free,"hiv_free")
  
  lt_whiv <- data.table(fread(paste0(lt_sim_dir,"/prematch/lt_",country,".csv")))
  lt_whiv <- format_lts(lt_whiv,"whiv")
  
  lt_combined <- merge(lt_hiv_free,lt_whiv,by=c("sex_id","year","age","sim"))
  # If a decimal point issue, enforce 0
  lt_combined[(mx_env_whiv - mx_env_hiv_free) < 0 & (mx_env_whiv - mx_env_hiv_free) > -.0000000001, mx_env_whiv := mx_env_hiv_free]
  lt_combined[,mx_env_hiv:=mx_env_whiv - mx_env_hiv_free]
  lt_combined[mx_env_hiv < 0 & age == 80,mx_env_hiv:=0] # For now, do it if there's any magnitude of difference at all
  lt_combined[,age:=as.character(age)]
  lt_combined <- merge(lt_combined,age_map,by.x="age",by.y="age_group_name")
  
  lt_u1 <- lt_combined[age==0,list(sex_id,year,sim,mx_env_hiv)]
  lt_1to4 <- lt_combined[age==1,list(sex_id,year,sim,mx_env_whiv,mx_env_hiv_free)]
  lt_80plus <- lt_combined[age==80,list(sex_id,year,sim,mx_env_whiv,mx_env_hiv_free)]
  
  
## With-HIV Envelope (to get NN breakdowns of envelope HIV and 1-4 breakdowns of envelope HIV, and to replace with-HIV over-80 with envelope over-80)
  env <- data.table(read.dta(paste0(env_dir,"/env_",country,".dta")))
  drop_cols <- colnames(env)[grepl("unscaled",colnames(env))]
  drop_cols <- c(drop_cols,"sex","age","age_group_name","location_id","ihme_loc_id","location_name","level","pop")
  env[,paste0(drop_cols):=NULL]
  setnames(env,"year_id","year")
  env <- merge(env,pop,by=c("sex_id","year","age_group_id")) 
  setnames(env,"pop_gbd","pop")
  
  env_80plus <- env[sex_id != 3 & age_group_id == 21,]
  env_nn <- env[sex_id != 3 & age_group_id <= 5,]

  env_1to4 <- env_nn[age_group_id == 5,]
  env_nn <- env_nn[age_group_id %in% c(2,3,4),]

  format_env <- function(data) {
    data <- melt(data,id.vars=c("sex_id","year","age_group_id","pop"),variable.name="sim",value.name="mx_env_whiv")
    data[,sim:=as.numeric(gsub("env_","",sim))]
    data[,mx_env_whiv:=mx_env_whiv / pop] # Convert env to a rate
    data[,pop:=NULL]
  }
  env_nn <- format_env(env_nn)
  env_1to4 <- format_env(env_1to4)
  env_80plus <- format_env(env_80plus)
  
## Rescale LT over-80 approximated mx with envelope real 80+ mx
## This is because we always want the 80+ envelope to be consistent, so we basically rescale hiv-free envelope and implied HIV to make it all mix
  setnames(env_80plus,"mx_env_whiv","env_mx")
  lt_80plus <- merge(lt_80plus,env_80plus, by=c("sex_id","year","sim"))
  lt_80plus[,scalar:=env_mx/mx_env_whiv]
  lt_80plus[,mx_env_whiv:=scalar*mx_env_whiv]
  lt_80plus[,mx_env_hiv_free:=scalar*mx_env_hiv_free]
  lt_80plus[,mx_env_hiv:=mx_env_whiv - mx_env_hiv_free]
  lt_80plus[mx_env_hiv < 0,mx_env_hiv:=0] # For now, do it if there's any magnitude of difference at all
  
  lt_80plus[,c("scalar","env_mx"):=NULL]
  lt_80plus[,age:="80"]
  
  lt_combined <- lt_combined[age_group_id != 21,]
  lt_combined <- rbindlist(list(lt_combined,lt_80plus),use.names=T)
  
## Spectrum Results (if Group 1 [GEN], Group 2B [CON incomplete VR], or Group 2C [CON no data])
## Note that non-HIV deaths are only used for Group 1 and need to be split by envelope for ENN/LNN/PNN
  if(group %in% c("1A","1B","2B","2C")) {
    spec_draws <- data.table(fread(paste0(spec_sim_dir,"/",country,"_ART_deaths.csv")))
    setnames(spec_draws,c("year_id","run_num","hiv_deaths"),c("year","sim","mx_spec_hiv"))
    spec_draws[,sim:=sim-1] # Format sims to be in the same number-space
  }
  
  
## ST-GPR Results (if Group 2A [CON complete VR])
## For these, we trust their VR systems so we take straight GPR results
  if(group=="2A") {
    spec_draws <- fread(paste0(stgpr_dir,"/gpr_results.csv"))
    spec_draws <- spec_draws[location_id == loc_id,list(year_id,age_group_id,sex_id,gpr_mean,gpr_var)]  
    
    na_count <- nrow(spec_draws[is.na(gpr_var) | is.na(gpr_mean),])
    if(na_count > 0) {
      print("GPR Variance or Mean is N/A. Why??")
      BREAK
    }
    
    ## Generate 1000 draws by location/year/age/sex
    ## Need to use Delta Method to transform into real space before making draws
    spec_draws[gpr_mean==0,zero:=1]
    spec_draws[gpr_mean != 0,gpr_var:=((1/gpr_mean)^2)*gpr_var]
    spec_draws[gpr_mean != 0,gpr_sd:=sqrt(gpr_var)]
    spec_draws[gpr_mean != 0,gpr_mean:=log(gpr_mean)]
    
    ## Create 1000 normal sims around the logged mean/sd
    sims <- spec_draws[,list(gpr_mean,gpr_sd)]
    setnames(sims,c("mean","sd"))
    sims <- data.table(mdply(sims,rnorm,n=1000))
    
    ## Combine and reshape the results, then back-transform
    spec_draws <- cbind(spec_draws,sims)
    spec_draws[,c("mean","sd","gpr_mean","gpr_var","gpr_sd"):=NULL]
    spec_draws <- melt(spec_draws,id.vars=c("year_id","age_group_id","sex_id","zero"),variable.name="sim")
    spec_draws[,sim:=as.numeric(gsub("V","",sim))-1]
    spec_draws[,mx_spec_hiv:=exp(value)/100] # Convert to real numbers then divide by 100 since the death rate is in rate per capita * 100
    spec_draws[zero==1,mx_spec_hiv:=0]
    
    spec_draws <- spec_draws[,list(year_id,age_group_id,sex_id,sim,mx_spec_hiv)]
    setnames(spec_draws,"year_id","year")
  }
  
  
###############################################################################################################
## Split NN and under-1 envelope/LT into with-HIV and HIV-free proportional to the populations in those age groups 
  env_nn <- merge(env_nn,lt_u1,by=c("sex_id","year","sim"))
  env_nn[age_group_id %in% c(2,3),mx_env_hiv:=0] # We assume no HIV deaths to ENN and LNN age groups
  
  # Because the PNN envelope with HIV is not necessarily higher than all HIV under-1 deaths due to different estimation processes,
  # We need to constrain under-1 HIV to 90% of the PNN hiv-deleted envelope
  env_nn[mx_env_hiv > (.9*mx_env_whiv),mx_env_hiv:=.9 * mx_env_whiv]
  env_nn[,mx_env_hiv_free := mx_env_whiv - mx_env_hiv]

  
###############################################################################################################
## Use the all-cause 1-4 envelope as the standard
## We will take the ratio of HIV-free to with-HIV from the LT results, then use all-cause mortality from envelope times the ratio to get HIV-free mx
  setnames(env_1to4,"mx_env_whiv","all_cause_envelope")
  env_1to4 <- merge(env_1to4,lt_1to4,by=c("sex_id","year","sim"))
  env_1to4[,scalar:=mx_env_hiv_free/mx_env_whiv]
  env_1to4[,mx_env_hiv_free:=all_cause_envelope * scalar]
  
  env_1to4[,c("mx_env_whiv","scalar"):=NULL]
  setnames(env_1to4,"all_cause_envelope","mx_env_whiv")
  
  env_1to4[,mx_env_hiv:=mx_env_whiv - mx_env_hiv_free]
  
###############################################################################################################
## Group 1 countries: Use the non-HIV death to all-cause ratio from Spectrum, and multiply it by all-cause envelope to get the HIV-free envelope
  
  ## GROUP 1 COUNTRIES: Pull out under-15 values from LTs
  convert_num <- function(conv_data,convert_vars) {
    ## Convert from rate to number space before collapsing
    conv_data <- merge(conv_data,pop,by=c("sex_id","year","age_group_id"))
    mult_pop <- function(x) return(x*conv_data[['pop_gbd']])
    conv_data[,(convert_vars) := lapply(.SD,mult_pop),.SDcols=convert_vars] 
    conv_data[,pop_gbd:=NULL]
    return(conv_data)
  }
  
  convert_rate <- function(conv_data,convert_vars) {
    ## Convert from rate to number space before collapsing
    conv_data <- merge(conv_data,pop,by=c("sex_id","year","age_group_id"))
    mult_pop <- function(x) return(x/conv_data[['pop_gbd']])
    conv_data[,(convert_vars) := lapply(.SD,mult_pop),.SDcols=convert_vars] 
    conv_data[,pop_gbd:=NULL]
    return(conv_data)
  }
  
  get_u5_hiv <- function(data) {
    data <- data[age_group_id <= 5,]
    data <- convert_num(data,c("mx_spec_hiv","non_hiv_deaths"))
   
    data[non_hiv_deaths == 0 ,non_hiv_deaths:=1] # For gap-filled results from 1970-198?

    ## Collapse NN granular to under-1 
    data[age_group_id <=4, age_group_id := 28]
    data <- data.table(data)[,lapply(.SD,sum),.SDcols=c("mx_spec_hiv","non_hiv_deaths"),
                             by=c("age_group_id","sex_id","year","sim")] 
    
    ## Get ratio of HIV-free to with-HIV (doesn't matter that it's in number vs. rate space since denominator is the same)
    data[,hiv_free_ratio := non_hiv_deaths/(mx_spec_hiv + non_hiv_deaths)]
    data <- data[,list(age_group_id,sex_id,year,sim,hiv_free_ratio)]
    return(data)
  }
  
  get_u1_env <- function(data) {
    data <- convert_num(data,c("mx_env_whiv"))
    data <- data.table(data)[,lapply(.SD,sum),.SDcols=c("mx_env_whiv"),
                                 by=c("sex_id","year","sim")] 
    return(data)
  }
  
  create_u5_mx_group1 <- function() {
    ## We want to use the ratio of Spectrum HIV-deleted to with-HIV to convert lifetable with-HIV to lifetable HIV-free
    ## data is with-HIV dataset from get_u15_lt, already under-1 non-granular
    ## We want to take in the spectrum NN results, collapse to under-1, merge on with the u5 HIV
    
    env_convert_vars <- c("mx_env_whiv","mx_env_hiv","mx_env_hiv_free")
    
    hiv_u5 <- get_u5_hiv(spec_draws)
    
    ## Calculate post-neonatal deaths
    env_u1 <- get_u1_env(env_nn)
    pnn_calc <- merge(env_u1,hiv_u5[age_group_id==28,],by=c("sex_id","year","sim"))
    pnn_calc[,mx_avg_hiv:= mx_env_whiv - (mx_env_whiv * hiv_free_ratio)]
    pnn_calc[,age_group_id:=4]
    pnn_calc <- pnn_calc[,list(age_group_id,sex_id,year,sim,mx_avg_hiv)]
    
    ## Merge back on PNN deaths
    final_nn <- convert_num(env_nn,env_convert_vars)
    final_nn <- merge(final_nn,pnn_calc,all.x=T,by=c("age_group_id","sex_id","year","sim"))
    final_nn[age_group_id %in% c(2,3),mx_avg_hiv := 0] # Still no deaths in enn/lnn
    
    # First, constrain HIV to at most be 90% of the all-cause total (some draws in ZAF violate this in PNN due to the ratio being applied at U-1 level, not PNN)
    final_nn[mx_avg_hiv > (.9 * mx_env_whiv), mx_avg_hiv := (.9 * mx_env_whiv)]

    final_nn[,mx_hiv_free:=mx_env_whiv - mx_avg_hiv]
    final_nn <- convert_rate(final_nn,c(env_convert_vars,"mx_avg_hiv","mx_hiv_free"))
    
    final_1to4 <- merge(env_1to4,hiv_u5[age_group_id != 28,],by=c("sex_id","year","sim","age_group_id"))
    
    final_1to4[,mx_hiv_free := mx_env_whiv * hiv_free_ratio]
    final_1to4[,mx_avg_hiv := mx_env_whiv - mx_hiv_free]
    final_1to4[,hiv_free_ratio:=NULL]

    env_u5 <- rbind(final_nn,final_1to4)
    env_u5 <- merge(env_u5,spec_draws,by=c("sex_id","year","age_group_id","sim")) # Bring in mx_spec_hiv
    env_u5[,non_hiv_deaths:= NULL]
    
    return(env_u5)
  } 
  
###############################################################################################################
## Merge results together, apply ensemble processes
  lt_combined <- lt_combined[age != "0" & age != "1"]
  lt_combined[,age:=NULL]
  lt_combined <- rbind(lt_combined,env_nn,env_1to4)
    
  lt_combined <- merge(lt_combined,pop,by=c("year","sex_id","age_group_id"))

  if(group == "2A") {
    ## We only have ST-GPR draws from 1981 onwards, so we assume 0 HIV deaths beforehand
    lt_combined <- merge(lt_combined,spec_draws,by=c("sex_id","year","sim","age_group_id"),all.x=T)
    lt_combined[,non_hiv_deaths:=NULL] # If it exists, no need to use after the 
    lt_combined[is.na(mx_spec_hiv) & year < 1981,mx_spec_hiv:=0]
  } else {
    lt_combined <- merge(lt_combined,spec_draws,by=c("sex_id","year","sim","age_group_id"))
  }
  
  lt_combined[,mx_hiv_free:=mx_env_hiv_free]
  
  ## If Group 1, average the HIV from Envelope and Spectrum
  ## For under-15 and over-5, use spectrum HIV instead of averaged
  ## For under-5 ages in Group 1, use envelope with-HIV scaled using Spectrum ratios to get HIV-free and rescaled Spectrum HIV
  if(group %in% c("1A","1B")) {
    lt_combined[age_group_id > 7,mx_avg_hiv:=(mx_spec_hiv+mx_env_hiv)/2]
    lt_combined[age_group_id > 5 & age_group_id <= 7,mx_avg_hiv:=mx_spec_hiv]
    
    env_u5 <- create_u5_mx_group1()
    env_u5 <- merge(env_u5,pop,by=c("year","sex_id","age_group_id"))
    lt_combined[,non_hiv_deaths:=NULL]
    
    lt_combined <- rbind(lt_combined[age_group_id > 5],env_u5)
  }
  
  ## Otherwise, consider HIV straight from Spectrum or ST-GPR
  if(group %in% c("2A","2B","2C")) lt_combined[,mx_avg_hiv:=mx_spec_hiv]
  
  ## For all groups except Group 1A, we believe the all-cause and want to preserve it instead of HIV-free
  ## So we recalculate HIV-deleted based on the averaged HIV and the with-HIV
  if(group %in% c("1B","2A","2B","2C")) {
    # First, constrain HIV to at most be 90% of the all-cause total
    lt_combined[mx_avg_hiv > (.9 * mx_env_whiv), mx_avg_hiv := (.9 * mx_env_whiv)]
    lt_combined[,mx_hiv_free:=mx_env_whiv - mx_avg_hiv]
  }
  
  ## Now, the with-HIV envelope is the sum of the HIV-free envelope and HIV (either averaged or direct from Spectrum/ST-GPR)
  ## Or it is with-HIV envelope minus HIV -- because we modify the mx_hiv_free variable in those cases above, it should all compute appropriately.
  lt_combined[,mx_avg_whiv := mx_hiv_free + mx_avg_hiv]
  
  
###############################################################################################################
## Output all results
  ## Create convert_mx function to go from rate to number space
  convert_mx <- function(x) return(x*lt_combined[['pop_gbd']])
  c_vars <- colnames(lt_combined)[grepl("mx",colnames(lt_combined))]
  lt_combined[,(c_vars) := lapply(.SD,convert_mx),.SDcols=c_vars] 
  
  ## Add on loc_id
  lt_combined[,location_id:=loc_id]
  setnames(lt_combined,c("year","pop_gbd"),c("year_id","pop"))
  
  ## Rescramble draws
  lt_combined <- merge(lt_combined,draw_map,by=c("sim"))
  lt_combined[,sim:=new_draw]
  lt_combined[,new_draw:=NULL]
  
  ## Check that no draws are under 0 or too high
  check_draws <- function(x) return(nrow(lt_combined[x<0,]))
  c_vars <- colnames(lt_combined)[grepl("mx",colnames(lt_combined))]
  check_results <- lt_combined[,lapply(.SD,check_draws),.SDcols=c_vars] 
  if (max(check_results) > 0) {
    print("These variables have mx under 0")
    print(check_results)
    BREAK
  }
  
  check_draws <- function(x) return(nrow(lt_combined[is.na(x),]))
  check_results <- lt_combined[,lapply(.SD,check_draws),.SDcols=c_vars] 
  if (max(check_results) > 0) {
    print("These variables have missing values")
    print(check_results)
    BREAK
  }
  
  ## Create age- and draw-specific scalars from HIV-free to with_HIV envelope
  output <- lt_combined
  output[,scalar_del_to_all:=mx_avg_whiv/mx_hiv_free]
  output <- output[,list(year_id,sex_id,age_group_id,sim,scalar_del_to_all)]
  write.dta(output,paste0(whiv_dir,"/scalars_",country,".dta"))
  
  ## Output with-HIV envelope
  output <- lt_combined[,list(location_id,year_id,sex_id,age_group_id,sim,pop,mx_avg_whiv)]
  output[,sim:=paste0("env_",sim)]
  output <- dcast(output,location_id+year_id+sex_id+age_group_id+pop~sim,value.var="mx_avg_whiv")
  write.csv(output,paste0(whiv_dir,"/env_",country,".csv"),row.names=F)
  
  ## Output HIV-free envelope
  output <- lt_combined[,list(location_id,year_id,sex_id,age_group_id,sim,pop,mx_hiv_free)]
  output[,sim:=paste0("env_",sim)]
  output <- dcast(output,location_id+year_id+sex_id+age_group_id+pop~sim,value.var="mx_hiv_free")
  write.csv(output,paste0(hiv_free_dir,"/draws/env_",country,".csv"),row.names=F)

  ## Output HIV-specific deaths
  output <- lt_combined[,list(location_id,year_id,sex_id,age_group_id,sim,mx_avg_whiv,mx_hiv_free)]
  output[,hiv_deaths:=mx_avg_whiv-mx_hiv_free]
  output[,c("mx_avg_whiv","mx_hiv_free"):=NULL]
  write.csv(output,paste0(out_dir_hiv,"/hiv_death_",country,".csv"),row.names=F)
  
  ## Output total envelope deaths pre-Reckoning (Envelope and Spectrum), and total averaged deaths
  output <- lt_combined
  output[,mx_avg_hiv:=mx_avg_whiv-mx_hiv_free]
  collapse_vars <- c("mx_avg_whiv","mx_env_whiv","mx_avg_hiv","mx_spec_hiv","mx_env_hiv")
  ## Collapse to aggregate age groups for reporting
  output[age_group_id <= 5, age_group_id:= 1] # Under-5
  output[age_group_id <= 7 & age_group_id > 5, age_group_id:= 23] # 5-14
  output[age_group_id <= 14 & age_group_id > 7, age_group_id:= 24] # 15-49
  output[age_group_id <= 21 & age_group_id > 14, age_group_id:= 40] # 50+
  
  output <- data.table(output)[,lapply(.SD,sum),.SDcols=collapse_vars,
                           by=c("sex_id","year_id","location_id","age_group_id","sim")]
  setnames(output,c("mx_avg_whiv","mx_env_whiv","mx_env_hiv","mx_spec_hiv","mx_avg_hiv"),c("env_post","env_pre","hiv_pre_env","hiv_pre_oth","hiv_post"))
  output <- melt(output,id.vars=c("sex_id","year_id","location_id","age_group_id","sim"),variable.name="measure_type",value.name="value")
  write.csv(output,paste0(out_dir_hiv,"/reckon_reporting_",country,".csv"),row.names=F)
  
  