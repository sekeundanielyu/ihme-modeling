################################################################################
## Description: Compile GPR results
################################################################################


  rm(list=ls())
  library(foreign); library(data.table); library(plyr) 
  
  if (Sys.info()[1]=="Windows") root <- "J:" else root <- "/home/j"

  rr <- as.numeric(commandArgs()[3])
  hivuncert <- as.logical(as.numeric(commandArgs()[4]))

  if (hivuncert) {
    setwd(paste("strPath", sep=""))
  } else {
    setwd(paste("strPath", sep=""))
  }

#   rr <- 5 # East Asia
  # rr <- 159 # South Asia
   # rr <- 138 # North Africa and the Middle East
  
## if we want to run subnationals, then subnationals should be T. If we don't, it should be F
  subnational <- T

## raking mx or qx?
  rake_mx <- T

## Introduce function to loop over ihme_loc_id and sex and bring in the GPR files of each
  append_sims <- function(sex,ihme_loc_id) {
    filepath <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",ihme_loc_id,"_",sex,"_sim_not_scaled")
    tryCatch(read.csv(paste0(filepath,".txt"), stringsAsFactors = F), error = function(e) print(paste(ihme_loc_id,sex,"not found")))
  } 
  append_results <- function(sex,ihme_loc_id) {
    filepath <- paste0("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",ihme_loc_id,"_",sex,"_not_scaled")
    tryCatch(read.csv(paste0(filepath,".txt"), stringsAsFactors = F), error = function(e) print(paste(ihme_loc_id,sex,"not found")))
  } 

## get the national iso3s
  source(paste0(root,"strPath/get_locations.r"))
  codes <- get_locations(level="estimate")
  codes <- codes[codes$region_id == rr & codes$level_all == 1,] # Eliminate those that are estimated but not in the traditional senese (Northern Marianas)

  ## Create conditional statement for ZAF, which will be aggregated from children
    if("ZAF" %in% unique(codes$ihme_loc_id)) {
      zaf_indic <- 1
      zaf_codes <- codes[grepl("ZAF_",codes$ihme_loc_id),]
      codes <- codes[!(grepl("ZAF",codes$ihme_loc_id)),] # Remove all subnationals AND national since national will be aggregated from subnationals
    } else {
      zaf_indic <- 0 
    }

  nat_iso3s <- codes[codes$level == 3 | (codes$ihme_loc_id %in% c("CHN_354","CHN_361","CHN_44533")),] # Keep HK, Macau, and China mainland as national entities
  parent_id_map <- codes[,c("ihme_loc_id","location_id")]
  names(parent_id_map) <- c("parent_loc_id","parent_id")


## Get subnational iso3s (if applicable)
  sub_iso3s <- get_locations(level = 'subnational')
  sub_iso3s <- sub_iso3s[sub_iso3s$region_id == rr & sub_iso3s$level_all == 1,] 
  if(zaf_indic == 1) sub_iso3s <- sub_iso3s[!(grepl("ZAF",sub_iso3s$ihme_loc_id)),]
  count <- length(unique(sub_iso3s$ihme_loc_id))
  if(count == 0) subnational <- F

  if (subnational) {
    ## Figure out if this region has one layer of subnationals or two layers
    keep_level_2 <- unique(sub_iso3s$ihme_loc_id[sub_iso3s$level_1 == 0 & sub_iso3s$level_2 == 1 & sub_iso3s$level_3 == 0])
    keep_level_3 <- unique(sub_iso3s$ihme_loc_id[sub_iso3s$level_1 == 0 & sub_iso3s$level_3 == 1])
    all_subnats <- c(keep_level_2,keep_level_3)
    
    layered <- ifelse(length(keep_level_2 >0), TRUE, FALSE)
    
    sub_iso3s$parent_id[grepl("GBR_",sub_iso3s$ihme_loc_id)] <- 95 # Switch those with parent England to parent GBR because we don't analyze England
    # sub_iso3s$parent_id[grepl("IND_",sub_iso3s$ihme_loc_id)] <- 163 # Switch the parent of India subnationals to India national (ONLY FOR NOW -- WILL CHANGE WHEN WE DO INDIA STATES SEPARATELY)
    
    parent_ids <- unique(sub_iso3s$parent_id[sub_iso3s$ihme_loc_id %in% all_subnats])
    parent_loc_ids <- unique(codes$ihme_loc_id[codes$location_id %in% parent_ids])
    
    ref <- get_locations(level = 'estimate')
    ref <- ref[,c('ihme_loc_id','parent_id')]
    ref$parent_id[grepl("GBR_",ref$ihme_loc_id)] <- 95
  }
  
## compile all national files
  sexes <- c("male","female")
  data_nat <- expand.grid(sexes,unique(nat_iso3s$ihme_loc_id))
  colnames(data_nat) <- c("sex","ihme_loc_id")
  data_nat <- mdply(data_nat,append_results, .progress = "text")

  data_nat$mort_med <- as.numeric(data_nat$mort_med)
  data_nat$mort_lower <- as.numeric(data_nat$mort_lower)
  data_nat$mort_upper <- as.numeric(data_nat$mort_upper)

  if (subnational) {
    
    ## we want to scale subnational estimates so they sum to the national, but at the sim level
    ## compile all subnational sims
      data_sub <- NULL 
      sexes <- c("male","female")
      data_sub <- expand.grid(sexes,all_subnats)
      colnames(data_sub) <- c("sex","ihme_loc_id")
      data_sub <- mdply(data_sub,append_sims, .progress = "text")
      data_sub$mort <- as.numeric(data_sub$mort)
      
      ## rerandomize sims
      set.seed(33)
      sim2 <- as.data.frame(cbind(sim=0:999,rand=runif(1000)))
      sim2 <- sim2[order(sim2$rand),]
      sim2$sim2 <- 0:999
      data_sub <- merge(data_sub,sim2[,c("sim","sim2")])
      data_sub$sim <- data_sub$sim2
      data_sub$sim2 <- NULL
          
      ## converto to mx if necessary
      if (rake_mx) data_sub$mort <- log(1-data_sub$mort)/-45
    
    ## compile all parent country sims
      data_parent <- NULL 
      sexes <- c("male","female")
      data_parent <- expand.grid(sexes,parent_loc_ids)
      colnames(data_parent) <- c("sex","ihme_loc_id")
      data_parent <- mdply(data_parent,append_sims, .progress = "text")
      data_parent$mort <- as.numeric(data_parent$mort)
    
      ## rerandomize sims
      set.seed(8008135)
      sim3 <- as.data.frame(cbind(sim=0:999,rand=runif(1000)))
      sim3 <- sim3[order(sim3$rand),]
      sim3$sim3 <- 0:999
      data_parent <- merge(data_parent,sim3[,c("sim","sim3")])
      data_parent$sim <- data_parent$sim3
      data_parent$sim3 <- NULL
      
      ## converto to mx if necessary
      if (rake_mx) data_parent$mort <- log(1-data_parent$mort)/-45
      
    ## get adult populations for population weighting
      pop <- read.dta(paste(root,"strPath/population_gbd2015.dta",sep=""))
      pop <- pop[pop$ihme_loc_id %in% all_subnats & pop$sex != "both" & pop$age_group_id < 17 & pop$age_group_id > 7,c("pop","ihme_loc_id","sex","year","age_group_id")]
      
    # Aggregate to adult population size
      pop <- aggregate(pop$pop, by=list(ihme_loc_id=pop$ihme_loc_id,year=pop$year,sex=pop$sex),sum)
      names(pop)[names(pop)=="x"] <- "pop_adult"
      pop <- pop[!is.na(pop$pop_adult),]
    
    ## merge parent iso3 onto population data
      pop <- merge(pop,ref)
    
    ## for merging
      pop$year <- pop$year + 0.5  
    
    ## merge population onto subnational data
      data_sub <- merge(data_sub,pop[,c("ihme_loc_id","sex","year","pop_adult","parent_id")], by = c("ihme_loc_id","year","sex"))
      data_sub <- merge(data_sub,parent_id_map,by="parent_id")
      sub_cov <- data_sub[,c("ihme_loc_id","sex","year","sim","hiv","pred.1.wRE","pred.1.noRE","pred.2.final")] ## Save covariates to merge back on later
    
    ## If layered, split into two levels of subnationals here so that you don't have a bunch of excess data in the scaling
      if (layered) {
        data_sub2 <- data_sub[data_sub$parent_loc_id %in% keep_level_2,]
        data_sub <- data_sub[!data_sub$parent_loc_id %in% keep_level_2,]
      }

    ## by sim, gbd_country_iso3, sex, and year: get population weighted mean of subnational mort
      data_sub$weighted <- data_sub$mort * data_sub$pop_adult
      ## for UK subnational, we have XNI and XSC deaths (complete VR) for 1980 and earlier, but not for any other "shire"; so we subtract these at the
      ## sim level from the national populations (when we scale them up, we only scale up the other shires for this range).
      ## This means we will be doing all calculations separately before and after 1981, then rbinding them at the end
          ## We no longer do this now that we are  doing two levels of scaling, because the first level scales England, N Ireland,
          ##     and Scotland, and the second level then scales the rest of the "shires" to the newly scaled England numbers
          ## !! NOTE !! We are doing this again.
      wmeans_pre <- data.table(data_sub[data_sub$year < 1981,])
      wmeans_post <- data.table(data_sub[data_sub$year >= 1981,])
      setkey(wmeans_pre,parent_loc_id,sex,year,sim)
      if(rr == 73) {
        wmeans_pre <- as.data.frame(wmeans_pre[,list(wmean=(sum(weighted)-sum(weighted[ihme_loc_id %in% c("GBR_433","GBR_434")]))/sum(pop_adult),totw=sum(pop_adult),xni_xsc_w=sum(weighted[ihme_loc_id %in% c("GBR_433","GBR_434")])),by=key(wmeans_pre)])        
      } else wmeans_pre <- as.data.frame(wmeans_pre[,list(wmean=(sum(weighted))/sum(pop_adult),totw=sum(pop_adult)),by=key(wmeans_pre)])        
      setkey(wmeans_post,parent_loc_id,sex,year,sim)
      wmeans_post <- as.data.frame(wmeans_post[,list(wmean=(sum(weighted))/sum(pop_adult),totw=sum(pop_adult)),by=key(wmeans_post)])

    ## merge on mort for parent countries, get scaling ratio
      names(data_parent) <- gsub("ihme_loc_id","parent_loc_id", names(data_parent))
      ratio_pre <- merge(wmeans_pre,data_parent[,c("parent_loc_id","sim","sex","year","mort")])
      ratio_post <- merge(wmeans_post,data_parent[,c("parent_loc_id","sim","sex","year","mort")])
      if(rr == 73) ratio_pre$ratio[ratio_pre$parent_loc_id == "GBR"] <- (ratio_pre$mort[ratio_pre$parent_loc_id == "GBR"] - (ratio_pre$xni_xsc_w[ratio_pre$parent_loc_id == "GBR"]/ratio_pre$tot[ratio_pre$parent_loc_id == "GBR"]))/ratio_pre$wmean[ratio_pre$parent_loc_id == "GBR"]
      ratio_pre$ratio[ratio_pre$parent_loc_id != "GBR"] <- ratio_pre$mort[ratio_pre$parent_loc_id != "GBR"]/ratio_pre$wmean[ratio_pre$parent_loc_id != "GBR"]
      ratio_post$ratio <- ratio_post$mort/ratio_post$wmean
    
    ## combine pre-1980 and post-1980
      ratio <- rbind(ratio_pre[,c("parent_loc_id","sim","sex","year","ratio","wmean")],ratio_post[,c("parent_loc_id","sim","sex","year","ratio","wmean")])

    ## merge scaling ratio onto sims, and scale up values at the sim level and aggregate mean/upper/lower
      data_sub <- merge(data_sub[,c("ihme_loc_id","sex","year","sim","mort","parent_loc_id")], 
                        ratio[,c("ratio","sex","year","sim","parent_loc_id")])
      ## make sure we don't scale the XNI and XSC pre 1981 values
      data_sub$ratio[data_sub$ihme_loc_id %in% c("GBR_433","GBR_434") & data_sub$year < 1981] <- 1
      ## multiply the ratio
      data_sub$mort <- data_sub$mort * data_sub$ratio
    
    
    ## If you have multiple levels of hierarchy, we repeat the process for the second (now-scaled) tier
    if(layered == T) {
      data_parent <- data_sub[, c("ihme_loc_id","sex","year","sim","mort")]
      names(data_parent)[names(data_parent) == "ihme_loc_id"] <- "parent_loc_id"
      
      ## by sim, gbd_country_iso3, sex, and year: get population weighted mean of subnational mort
      data_sub2$weighted <- data_sub2$mort * data_sub2$pop_adult
      
      wmeans <- data.table(data_sub2)
      setkey(wmeans,parent_loc_id,sex,year,sim)
      wmeans <- as.data.frame(wmeans[,list(wmean=(sum(weighted))/sum(pop_adult),totw=sum(pop_adult)),by=key(wmeans)])
      
      ## merge on mort for parent countries, get scaling ratio
      names(data_parent) <- gsub("ihme_loc_id","parent_loc_id", names(data_parent))
      ratio <- merge(wmeans,data_parent[,c("parent_loc_id","sim","sex","year","mort")])
      ratio$ratio <- ratio$mort/ratio$wmean
      
      ## merge scaling ratio onto sims, and scale up values at the sim level and aggregate mean/upper/lower
      data_sub2 <- merge(data_sub2[,c("ihme_loc_id","sex","year","sim","mort","parent_loc_id")], 
                        ratio[,c("ratio","sex","year","sim","parent_loc_id")])
     
      ## multiply the ratio
      data_sub2$mort <- data_sub2$mort * data_sub2$ratio
      
      ## Add to other non-hierarchical subnationals
      data_sub <- data_sub[!(data_sub$parent_loc_id %in% unique(data_parent$parent_loc_id)),]
      data_sub <- rbind(data_sub,data_sub2)
    }

    ## convert back to 45q15 if necessary
      if (rake_mx) data_sub$mort <- 1- exp(-45*data_sub$mort)
    
    ## Merge back on covariates
      data_sub <- merge(data_sub,sub_cov, by=c("ihme_loc_id","sex","year","sim"))
    
    ## save sims that are now scaled
      for (cc in unique(data_sub$ihme_loc_id)) {
        for (ss in unique(data_sub$sex)) {
          cat(paste(cc,"\n")); flush.console()
          write.csv(data_sub[data_sub$ihme_loc_id == cc & data_sub$sex==ss,c("ihme_loc_id","sex","year","sim","mort","hiv","pred.1.wRE")],paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_sim.txt",sep=""),row.names=F)
        }
      }
    
      ## aggregate
      data_sub <- data.table(data_sub)
      setkey(data_sub,ihme_loc_id,sex,year)
      data_sub <- as.data.frame(data_sub[,list(mort_med=mean(mort),mort_lower=quantile(mort,0.025),mort_upper=quantile(mort,0.975),
                                               med_hiv=quantile(hiv,.5),mean_hiv=mean(hiv),
                                               med_stage1=quantile(pred.1.noRE,.5),
                                               med_stage2 =quantile(pred.2.final,.5)
                                               ),by=key(data_sub)])
    
    ## save aggregated that are now scaled
      for (cc in unique(data_sub$ihme_loc_id)) {
        for (ss in unique(data_sub$sex)) {
          cat(paste(cc,"\n")); flush.console()
          write.csv(data_sub[data_sub$ihme_loc_id == cc & data_sub$sex==ss,c("ihme_loc_id","sex","year","mort_med","mort_lower","mort_upper","med_hiv","mean_hiv","med_stage1","med_stage2")],paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,".txt",sep=""),row.names=F)
        }
      }
    
    ## append national and subnational together
      data <- rbind(data_nat,data_sub)
  } else {
    data <- data_nat
  }

## copy national level
  for (cc in unique(data_nat$ihme_loc_id)) {
    for (ss in unique(data_nat$sex)) {
      cat(paste(cc,"\n")); flush.console()
      file.copy(from=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_not_scaled.txt",sep=""),
                to=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,".txt",sep=""))
      file.copy(from=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_sim_not_scaled.txt",sep=""),
                to=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_sim.txt",sep=""))
    }
  }

## Aggregate South African subnationals to create national-level draws
  if(zaf_indic == 1) {
    zaf_ids <- get_locations(level = "subnational", subnat_only="ZAF")
    zaf_ids <- unique(zaf_ids$ihme_loc_id)
    sexes <- c("male","female")
    zaf_data <- expand.grid(sexes,zaf_ids)
    colnames(zaf_data) <- c("sex","ihme_loc_id")
    zaf_data <- mdply(zaf_data,append_sims, .progress = "text")
    zaf_data$mort <- as.numeric(zaf_data$mort) 
    if (rake_mx) zaf_data$mort <- log(1-zaf_data$mort)/-45
    
    ## rerandomize sims
    set.seed(66)
    sim_zaf <- as.data.frame(cbind(sim=0:999,rand=runif(1000)))
    sim_zaf <- sim_zaf[order(sim_zaf$rand),]
    sim_zaf$sim2 <- 0:999
    zaf_data <- merge(zaf_data,sim_zaf[,c("sim","sim2")])
    zaf_data$sim <- zaf_data$sim2
    zaf_data$sim2 <- NULL
    
    ## get adult populations for population weighting
    pop <- read.dta(paste(root,"/WORK/02_mortality/03_models/1_population/results/population_gbd2015.dta",sep=""))
    pop <- pop[pop$ihme_loc_id %in% zaf_ids & pop$sex != "both" & pop$age_group_id < 17 & pop$age_group_id > 7,c("pop","ihme_loc_id","sex","year","age_group_id")]
    
    # Aggregate to adult population size
    pop <- aggregate(pop$pop, by=list(ihme_loc_id=pop$ihme_loc_id,year=pop$year,sex=pop$sex),sum)
    names(pop)[names(pop)=="x"] <- "pop_adult"
    pop <- pop[!is.na(pop$pop_adult),]
    
    ## for merging
    pop$year <- pop$year + 0.5  
    
    ## merge population onto subnational data
    zaf_data <- merge(zaf_data,pop[,c("ihme_loc_id","sex","year","pop_adult")], by = c("ihme_loc_id","year","sex"))
    zaf_data$weighted <- zaf_data$mort * zaf_data$pop_adult
    zaf_data <- data.table(zaf_data)
#     print(names(zaf_data))
#     print(head(zaf_data))
    setkey(zaf_data,sex,year,sim)
    zaf_data <- as.data.frame(zaf_data[,list(wmean=(sum(weighted))/sum(pop_adult)),by=key(zaf_data)])        
    
    ## Format and output ZAF national
    zaf_data$ihme_loc_id <- "ZAF"
    
    ## convert back to 45q15 if necessary
    if (rake_mx) zaf_data$mort <- 1- exp(-45*zaf_data$wmean)

    ## Grab ZAF national covariates and output
      zzz <- "ZAF"
      zaf_national <- expand.grid(sexes,zzz)
      colnames(zaf_national) <- c("sex","ihme_loc_id")
      zaf_national <- mdply(zaf_national,append_sims, .progress = "text")
      zaf_national <- zaf_national[,c("ihme_loc_id","sex","year","sim","hiv","pred.1.wRE","pred.1.noRE","pred.2.final")]
      zaf_data <- merge(zaf_data,zaf_national,by=c("ihme_loc_id","sex","year","sim"))

    ## save aggregated ZAF sims
      for (ss in unique(zaf_data$sex)) {
        cat(paste("ZAF","\n")); flush.console()
        write.csv(zaf_data[zaf_data$sex==ss,c("ihme_loc_id","sex","year","sim","mort","hiv","pred.1.wRE")],paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_ZAF_",ss,"_sim.txt",sep=""),row.names=F)
      }
    
    ## aggregate
      zaf_data <- data.table(zaf_data)
      setkey(zaf_data,ihme_loc_id,sex,year)
      zaf_data <- as.data.frame(zaf_data[,list(mort_med=mean(mort),mort_lower=quantile(mort,0.025),mort_upper=quantile(mort,0.975),
                                               med_hiv=quantile(hiv,.5),mean_hiv=mean(hiv),
                                               med_stage1=quantile(pred.1.noRE,.5),
                                               med_stage2 =quantile(pred.2.final,.5)
                                               ),by=key(zaf_data)])
      
    ## save aggregated ZAF summary
      for (ss in unique(zaf_data$sex)) {
        cat(paste("ZAF","\n")); flush.console()
        write.csv(zaf_data[zaf_data$sex==ss,c("ihme_loc_id","sex","year","mort_med","mort_lower","mort_upper","med_hiv","mean_hiv","med_stage1","med_stage2")],paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_ZAF_",ss,".txt",sep=""),row.names=F)
      }

    ## Copy all of the ZAF subnationals
    for (cc in zaf_ids) {
      for (ss in unique(zaf_data$sex)) {
        cat(paste(cc,"\n")); flush.console()
        file.copy(from=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_not_scaled.txt",sep=""),
                  to=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,".txt",sep=""))
        file.copy(from=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_sim_not_scaled.txt",sep=""),
                  to=paste("gpr/",ifelse(hivuncert==T,"compiled/",""),"gpr_",cc,"_",ss,"_sim.txt",sep=""))
      }
    }
  }

