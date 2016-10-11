################################################################################
## Description: Compile GPR results
## Date Created: 06 April 2012
################################################################################


  rm(list=ls())
  library(foreign); library(data.table);
  
  if (Sys.info()[1]=="Windows"){
    root <- ""
    save_prerake <- 1
    source("get_locations.r")
  } else {
    root <- ""
    save_prerake <- as.integer(commandArgs()[3])
    username <- commandArgs()[4]
    code_dir <- paste("",sep="")  
    source(paste0("/get_locations.r"))
  }

  aggnats <- c("ZAF")

  setwd(paste("", sep=""))  
  
  # copy and paste the GBD 2013 location sims to the all sims folder so that we rake to the correct level (6/22/2015)
  gbd <- read.csv(paste(root, "GBD_2013_locations.txt", sep = ""), stringsAsFactors=F)
  gbd <- gbd[gbd$level_all != 0,]
  gbd <- gbd[,c("ihme_loc_id","local_id_2013")]
  names(gbd) <- c("ihme_loc_id","iso3")
  gbd$iso3[gbd$iso3 == ""] <- "CHN"
  for(iso in unique(gbd$ihme_loc_id)){
     for (ff in dir("")[dir("") %in% c(paste0("gpr_",gbd$ihme_loc_id,".txt"),paste0("gpr_",gbd$ihme_loc_id,"_sim.txt"))]) file.remove(paste("", ff, sep=""))
  }
  for(iso in unique(gbd$ihme_loc_id)){
      file.copy(from=paste("gpr_",iso,"_sim.txt",sep=""),
        to=paste("gpr_",iso,"_sim.txt",sep=""), overwrite=T)
	  file.copy(from=paste("gpr_",iso,".txt",sep=""),
        to=paste("gpr_",iso,".txt",sep=""), overwrite=T)	
    }
   
  #which values to weight by - mx by pop, qx by pop, or qx by births
  mx <- F
  births <- F
  save_sims <- T

  setwd("")

## get the national iso3s
  codes <- get_locations(level="estimate")
  codes <- codes[,c("ihme_loc_id","level","parent_id","location_id","level_1", "level_2", "level_3")]

## designate which subnational locations to keep when doing 3 layers (nats, nats + subnats (india states), nats + subnats (india states + urban/rural split))
  keep_level_2 <- unique(codes$ihme_loc_id[codes$level_1 == 0 & codes$level_2 == 1 & codes$level_3 == 0])
  keep_level_3 <- unique(codes$ihme_loc_id[codes$level_1 == 0 & codes$level_3 == 1])
  all_subnats <- c(keep_level_2,keep_level_3)    
  
## get subnats (we don't treat Hong Kong and Macau as subnats)
  sub_locs <- codes[codes$level_1 == 0 & (codes$level_3 == 1 | codes$level_2 ==1) & !(codes$ihme_loc_id %in% c("CHN_354","CHN_361")),c("parent_id","ihme_loc_id")]
  parent_locs <- codes[codes$ihme_loc_id %in% codes$ihme_loc_id[codes$location_id %in% sub_locs$parent_id],c("ihme_loc_id","location_id")]
  nat_locs <- codes$ihme_loc_id[!codes$ihme_loc_id %in% unique(sub_locs$ihme_loc_id)] 
  


## get subnational-parent reference list
  names(parent_locs) <- c("ihme_loc_id","parent_id")
  ref <- merge(sub_locs,parent_locs,by="parent_id",all.x=T)
  ref$parent_id <- NULL
  names(ref) <- c("ihme_loc_id","parent_ihme_loc_id")
## England ruins the mortality hierarchy...fix manually
  ref$parent_ihme_loc_id[substr(ref$ihme_loc_id,1,3) == "GBR"] <- "GBR"
  
sub_locs <- sub_locs$ihme_loc_id
parent_locs <- parent_locs$ihme_loc_id


file_fail <- c()
#CHANGEME
## compile all national files
  data_nat <- NULL
  for (cc in nat_locs) { 
      file <- paste("gpr_", cc, ".txt", sep="")
      if (file.exists(file)) data_nat <- rbind(data_nat, read.csv(file, stringsAsFactors = F))
      else {
        cat(paste("Does not exist:", file, "\n")); flush.console()
        file_fail <- c(file_fail, cc)
      }
  } 
  names(data_nat) <- c("ihme_loc_id","year","med","lower","upper")
## we want to scale subnational estimates so they sum to the national, but at the sim level
  
## compile all subnational sims
  data_sub <- list()
  count <- 1
  for (cc in sub_locs) { 
      file <- paste("gpr_", cc,"_sim.txt", sep="")
      if (file.exists(file)) { data_sub[[count]] <- read.csv(file, stringsAsFactors = F)
        cat(paste("Loaded:", file, "\n")); flush.console()
        count <- count + 1
      } else {
        cat(paste("Does not exist:", file, "\n")); flush.console()
        file_fail <- c(file_fail,cc)
      }
  }
  data_sub <- do.call("rbind",data_sub)
  
  if (is.null(file_fail)) {
    file_fail <- "NO MISSING FILES"
  }

  ## save file that says which gpr files didn't exist
  file_fail <- data.frame(ihme_loc_id = file_fail)
  write.csv(file_fail,paste0(root, "missing_gpr_files.csv"),row.names=F)
  stopifnot(as.character(file_fail$ihme_loc_id[1]) == "NO MISSING FILES")  

  #make this work when we're not doing hiv sims too
  if(is.null(data_sub$hivsim)) data_sub$hivsim <- 0
  data_sub <- data_sub[,c("ihme_loc_id","year","hivsim","mort","sim")]
  ## rerandomize sims
  set.seed(33)
  sim2 <- as.data.frame(cbind(sim=0:999,rand=runif(1000)))
  sim2 <- sim2[order(sim2$rand),]
  sim2$sim2 <- 0:999
  data_sub <- merge(data_sub,sim2[,c("sim","sim2")])
  data_sub$sim <- data_sub$sim2
  data_sub$sim2 <- NULL

## save original subnational sim data to merge back in for pre 1981 Scotland and N Ireland since we have data for them
   data_sub_orig <- data_sub[data_sub$ihme_loc_id %in% c("GBR_433","GBR_434"),]

## compile all parent country sims
  data_parent <- NULL 
  for (cc in parent_locs) { 
      file <- paste("data/gpr_files/final/gpr_", cc,"_sim.txt", sep="")
      if (file.exists(file)) data_parent <- rbind(data_parent, read.csv(file, stringsAsFactors = F))
      else cat(paste("Does not exist:", file, "\n")); flush.console()
  }
  if(is.null(data_parent$hivsim)) data_parent$hivsim <- 0


  data_parent <- data_parent[,c("ihme_loc_id","year","hivsim","mort","sim")]
  ## rerandomize sims
  set.seed(800813)
  sim3 <- as.data.frame(cbind(sim=0:999,rand=runif(1000)))
  sim3 <- sim3[order(sim3$rand),]
  sim3$sim3 <- 0:999
  data_parent <- merge(data_parent,sim3[,c("sim","sim3")])
  data_parent$sim <- data_parent$sim3
  data_parent$sim3 <- NULL

## get populations for population weighting
  pop <- read.dta(paste(root, "population_gbd2015.dta",sep=""))
  pop <- pop[pop$ihme_loc_id %in% sub_locs & pop$sex == "both" & pop$age_group_id %in% c(5,28),c("ihme_loc_id","year","age_group_name","pop")]
  pop <- data.table(pop)
  setkey(pop,ihme_loc_id,year)
  pop <- as.data.frame(pop[,list(pop_child=sum(pop)),by=key(pop)])
  pop <- pop[!is.na(pop$pop_child),] 
## attach births too
  brs <- read.dta(paste(root, "births_gbd2015.dta",sep=""))
  brs <- brs[brs$ihme_loc_id %in% sub_locs & brs$sex == "both",c("ihme_loc_id","year","births")]
  pop <- merge(pop,brs,by=c("ihme_loc_id","year"))

## merge parent iso3 onto population data
  pop <- merge(pop,ref)

## add in missing years for China subnational (hold them constant)
  add <- pop[pop$parent_ihme_loc_id == "CHN_44533" & pop$year == 1964,]
  tmp <- NULL
  for (i in 1:length(1950:1963)) tmp <- rbind(tmp,add)
  tmp$year <- rep(1950:1963,each=31)
  pop <- rbind(tmp,pop)


#################################################################
#Pop diagnostics - scaling
#popd <- data.table(pop[pop$gbd_country_iso3 == "CHN",],key = "year")
#popdtest <- popd[,sum(pop_child), by = key(popd)]
#
#poptest <- merge(popch, popdtest)


#################################################################

## for merging
  pop$year <- pop$year + 0.5

## merge population onto subnational data

   data_sub <- merge(data_sub,pop[,c("ihme_loc_id","year","births","pop_child","parent_ihme_loc_id")],by=c("ihme_loc_id","year"))


##weight mx or qx by pop or births
    if(births) data_sub$pop_child <- data_sub$births
    if(mx){
           data_sub$mort <- log(1-data_sub$mort)/-5
           data_parent$mort <- log(1-data_parent$mort)/-5
    }

## by sim, gbd_country_iso3, sex, and year: get population weighted mean of subnational mort
    data_sub$weighted <- data_sub$mort * data_sub$pop_child
    wmeans <- data.table(data_sub)
    setkey(wmeans,parent_ihme_loc_id,year,sim)
    wmeans <- as.data.frame(wmeans[,sum(weighted)/sum(pop_child),by=key(wmeans)])
    names(wmeans) <- gsub("V1","wmean",names(wmeans))

## now we have weighted means for parents, if we ever want to use these instead of raking, we can
## We're doing this for ZAF
  replace_nats <- wmeans[wmeans$parent_ihme_loc_id %in% c(aggnats),]
  names(replace_nats)[names(replace_nats) == "parent_ihme_loc_id"] <- "ihme_loc_id"
  names(replace_nats)[names(replace_nats) == "wmean"] <- "mort"

## merge on mort for parent countries, get scaling ratio
  names(data_parent) <- gsub("ihme_loc_id","parent_ihme_loc_id", names(data_parent))
  ratio <- merge(wmeans,data_parent[,c("parent_ihme_loc_id","sim","year","mort")])
  ratio$ratio <- ratio$mort/ratio$wmean
  
#######################################################################################################
## Diagnostics on the china raking
#wmeans.col <- data.table(wmeans)
#setkey(wmeans.col,"gbd_country_iso3","year")
#wmeans.col <- wmeans.col["CHN",list(wmean = mean(wmean)), by = key(wmeans.col)]
#setnames(wmeans.col, "gbd_country_iso3","iso3")
#
#nat.col <- data_nat[data_nat$iso3 == "CHN",c("iso3","year","med")]
#nat.col <- data.table(nat.col, key = c("iso3","year"))
#
#comp.wmean <- merge(wmeans.col, nat.col)
#comp.wmean$pct.diff <- (comp.wmean$wmean - comp.wmean$med)/comp.wmean$med
#
#write.csv(comp.wmean, "diagnostics/2014_5_8_chn_raking/chn_weighted_avg.csv", row.names = F)



#######################################################################################################


## Here, we scale all the UK subnational to UK (England is disaggregated)
## For UK, keep normal scaling after 1981. Pre-1981, don't scale Scotland/Ireland (XSC/XNI) but do scale others
  #these scaling values will only make sense for non XNI,XSC shires
  wmeans.gbr <- data.table(data_sub[data_sub$parent_ihme_loc_id == "GBR",])
  setkey(wmeans.gbr,year,sim)
  wmeans.gbr <- wmeans.gbr[,list(correct = sum(weighted[ihme_loc_id %in% c("GBR_433","GBR_434")])/sum(pop_child),
                         incor = sum(weighted[!(ihme_loc_id %in% c("GBR_433","GBR_434"))])/sum(pop_child)),by=key(wmeans.gbr)]
  wmeans.gbr <- merge(wmeans.gbr,data_parent[data_parent$parent_ihme_loc_id == "GBR",c("year","sim","mort")])
  setkey(wmeans.gbr,year,sim)
  wmeans.gbr$ratio1 <- (wmeans.gbr$mort-wmeans.gbr$correct)/wmeans.gbr$incor

  #only keep pre 1981 numbers
  wmeans.gbr$parent_ihme_loc_id <- "GBR"
  wmeans.gbr <- as.data.frame(wmeans.gbr[wmeans.gbr$year < 1981,])

  #push these numbers into the ratio df
  ratio <- merge(ratio,wmeans.gbr[,c("year","sim","ratio1","parent_ihme_loc_id")],all = T)
  ratio$ratio[!is.na(ratio$ratio1)] <- ratio$ratio1[!is.na(ratio$ratio1)]

## merge scaling ratio onto sims, and scale up values at the sim level and aggregate mean/upper/lower
  data_sub <- merge(data_sub[,c("ihme_loc_id","year","hivsim","sim","mort","parent_ihme_loc_id")], ratio[,c("parent_ihme_loc_id","sim","year","ratio")],by=c("parent_ihme_loc_id","sim","year"))


###################  
## repeat for the second level of the hierarchy (india states), already scaled once
## merge population onto subnational data

 data_parent2 <- data_sub[data_sub$ihme_loc_id %in% keep_level_2, c("ihme_loc_id","year","hivsim","mort","sim")]
 names(data_parent2)[names(data_parent2) == "ihme_loc_id"] <- "parent_ihme_loc_id"
 data_sub2 <- data_sub[data_sub$parent_ihme_loc_id %in% unique(data_parent2$parent_ihme_loc_id),] # Figure out which subnationals you need to re-run
 data_sub2 <- merge(data_sub2,pop[,c("ihme_loc_id","year","births","pop_child","parent_ihme_loc_id")], by=c("parent_ihme_loc_id","ihme_loc_id","year"))

##weight mx or qx by pop or births
    if(births) data_sub2$pop_child <- data_sub2$births
    if(mx){
           data_sub2$mort <- log(1-data_sub2$mort)/-5
           data_parent2$mort <- log(1-data_parent2$mort)/-5
    }

## by sim, gbd_country_iso3, sex, and year: get population weighted mean of subnational mort
    data_sub2$weighted <- data_sub2$mort * data_sub2$pop_child
    wmeans2 <- data.table(data_sub2)
    setkey(wmeans2,parent_ihme_loc_id,year,sim)
    wmeans2 <- as.data.frame(wmeans2[,sum(weighted)/sum(pop_child),by=key(wmeans2)])
    names(wmeans2) <- gsub("V1","wmean",names(wmeans2))

## merge on mort for parent countries, get scaling ratio
  names(data_parent2) <- gsub("ihme_loc_id","parent_ihme_loc_id", names(data_parent2))
  names(data_parent2) <- gsub("parent_parent_ihme_loc_id","parent_ihme_loc_id", names(data_parent2))
  ratio2 <- merge(wmeans2,data_parent2[,c("parent_ihme_loc_id","sim","year","mort")])
  ratio2$ratio <- ratio2$mort/ratio2$wmean

## merge scaling ratio onto sims, and scale up values at the sim level and aggregate mean/upper/lower
  data_sub2 <- merge(data_sub2[,c("ihme_loc_id","year","hivsim","sim","mort","parent_ihme_loc_id")], ratio2[,c("parent_ihme_loc_id","sim","year","ratio")],by=c("parent_ihme_loc_id","sim","year"))  

## Add to other non-hierarchical subnationals (data_sub and ratio)
  data_sub <- data_sub[!(data_sub$parent_ihme_loc_id %in% unique(data_parent2$parent_ihme_loc_id)),]
  data_sub <- rbind(data_sub,data_sub2)
  
  ratio <- ratio[!(ratio$parent_ihme_loc_id %in% unique(data_parent2$parent_ihme_loc_id)),]
  ## to match the other ratio dataset (ratio1 only exists for GBR)
  ratio2$ratio1 <- "NA"
  ratio <- rbind(ratio,ratio2)
  
## end  adding second hierarchy here ########################### 

  #inds for xni,xsc pre1981 (don't scale)
  inds <- (data_sub$ihme_loc_id %in% c("GBR_433","GBR_434") & data_sub$year < 1981)

  #######################################################################################################
## Diagnostics on the china raking
#  data_sub$mort_scaled[!inds] <- data_sub$mort[!inds] * data_sub$ratio[!inds]
#  data_sub_chn <- data.table(data_sub[data_sub$gbd_country_iso3 == "CHN",], key = c("year","iso3"))
#  data_sub_chn <- data_sub_chn[, list(mort = mean(mort), mort_scaled = mean(mort_scaled)), by = key(data_sub_chn)]
#  data_sub_chn$pct_chg <- (data_sub_chn$mort - data_sub_chn$mort_scaled)/data_sub_chn$mort_scaled
#
#  write.csv(data_sub_chn, "diagnostics/2014_5_8_chn_raking/chn_chg_by_province.csv", row.names = F)

#######################################################################################################

  data_sub$mort[!inds] <- data_sub$mort[!inds] * data_sub$ratio[!inds]
#}

##convert back to qx from mx
    if(mx){
           data_sub$mort <- 1-exp(-5*data_sub$mort)
           data_parent$mort <- 1-exp(-5*data_parent$mort)
    }


if (save_sims) {
  for(iso in unique(data_sub$ihme_loc_id)){
    if (!iso %in% ref$ihme_loc_id[ref$parent_ihme_loc_id %in% aggnats]) {
          if(max(data_sub$hivsim == 0)){
            if(save_prerake == 1) {
              file.copy(from=paste("gpr_",iso,"_sim.txt",sep=""),
                to=paste("gpr_",iso,"_sim.txt",sep=""), overwrite=T)
              write.csv(data_sub[data_sub$ihme_loc_id == iso,c("year","sim","ihme_loc_id","mort")]
                   ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
            } else {
              write.csv(data_sub[data_sub$ihme_loc_id == iso,c("year","sim","ihme_loc_id","mort")]
                   ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
            }
          }else{
            if(save_prerake == 1) {
              file.copy(from=paste("gpr_",iso,"_sim.txt",sep=""),
                to=paste("gpr_",iso,"_sim.txt",sep=""), overwrite=T)
              write.csv(data_sub[data_sub$ihme_loc_id == iso,c("year","sim","hivsim","ihme_loc_id","mort")]
                  ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
            } else {
              write.csv(data_sub[data_sub$ihme_loc_id == iso,c("year","sim","hivsim","ihme_loc_id","mort")]
                   ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
            }
          }
    }
  }

## SAVE NATIONALS THAT ARE AGGREGATES (WON'T WORK FOR HIV SIMS)
  for (iso in unique(replace_nats$ihme_loc_id)) {
    temp <- replace_nats[replace_nats$ihme_loc_id == iso,]
    if(save_prerake == 1) {
      file.copy(from=paste("gpr_",iso,"_sim.txt",sep=""),
                to=paste("gpr_",iso,"_sim.txt",sep=""), overwrite=T)
      write.csv(temp[temp$ihme_loc_id == iso,c("year","sim","ihme_loc_id","mort")]
                ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
    } else {
      write.csv(temp[temp$ihme_loc_id == iso,c("year","sim","ihme_loc_id","mort")]
                ,paste("gpr_",iso,"_sim.txt",sep=""),row.names=F)
    }
  }
  
}

## save mean/upper/lower from sims
  data_sub <- data.table(data_sub)
  setkey(data_sub,ihme_loc_id,year)
  data_sub <- as.data.frame(data_sub[,list(med=mean(mort),lower=quantile(mort,0.025),upper=quantile(mort,0.975)),by=key(data_sub)])

## find summary of sims for replacement nats and replace
  replace_nats <- data.table(replace_nats)
  setkey(replace_nats,ihme_loc_id,year)
  replace_nats <- as.data.frame(replace_nats[,list(med=mean(mort),lower=quantile(mort,0.025),upper=quantile(mort,0.975)),by=key(replace_nats)])
for (iso in unique(replace_nats$ihme_loc_id)) {
  temp <- replace_nats[replace_nats$ihme_loc_id == iso,]
  if(save_prerake == 1) {
    file.copy(from=paste("gpr_",iso,".txt",sep=""),
              to=paste("gpr_",iso,".txt",sep=""), overwrite=T)
    write.csv(temp[temp$ihme_loc_id == iso,c("year","ihme_loc_id","lower","upper","med")]
              ,paste("gpr_",iso,".txt",sep=""),row.names=F)
  } else {
    write.csv(temp[temp$ihme_loc_id == iso,c("year","ihme_loc_id","lower","upper","med")]
              ,paste("gpr_",iso,".txt",sep=""),row.names=F)
  }
}

data_nat <- data_nat[!data_nat$ihme_loc_id %in% replace_nats$ihme_loc_id,]
data_nat <- rbind(data_nat,replace_nats)

## append national and subnational together
  ## don't want to use subnationals that belong to nationals that we're aggregating here (since they're raked and we want unraked)
  ## load in original files again and replace in data_sub
data_subagg <- NULL
for (cc in ref$ihme_loc_id[ref$parent_ihme_loc_id %in% aggnats]) { 
  file <- paste("gpr_", cc, ".txt", sep="")
  data_subagg <- rbind(data_subagg, read.csv(file, stringsAsFactors = F))
} 
names(data_subagg) <- c("ihme_loc_id","year","med","lower","upper")

data_sub <- data_sub[!data_sub$ihme_loc_id %in% unique(data_subagg$ihme_loc_id),]
data_sub <- rbind(data_sub,data_subagg)

  data <- rbind(data_nat,data_sub)
  na.obs <- unique(data_nat$ihme_loc_id[is.na(data_nat$med) | is.na(data_nat$upper) | is.na(data_nat$lower)])
  write.csv(na.obs,paste0(root, "NA_values_gpr.csv"),row.names=F)

## save final file 
  data <- data[order(data$ihme_loc_id, data$year),c("ihme_loc_id","year","med","lower","upper")]

  savevar <- ""
  if(mx) savevar <- "_mx"
  if(births) savevar <- "_births"

  setwd(paste0(root, ""))

  write.csv(data, file=paste("estimated_5q0_noshocks",savevar,".txt",sep = ""), row.names=F)
  write.csv(data, file=paste("estimated_5q0_noshocks_", Sys.Date(),savevar, ".txt", sep=""), row.names=F)

