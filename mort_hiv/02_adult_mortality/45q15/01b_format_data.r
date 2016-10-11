################################################################################
## Description: Formats 45q15 data and covariates for the first and second
##              stage models
################################################################################

rm(list=ls())

library(foreign); library(plyr); library(reshape); library(data.table);library(haven)
if (Sys.info()[1]=="Windows") {
  root <- "J:" 
  hivsims <- F
  hivupdate <- F
} else {
  root <- "/home/j"
  print(commandArgs())
  hivsims <- as.logical(as.numeric(commandArgs()[3]))
  hivupdate <- as.logical(as.numeric(commandArgs()[4]))
  hivscalars <- as.logical(as.numeric(commandArgs()[5]))
}


#hivsims <- T
#hivupdate <- T


## Get covariates loading functions
source(paste0(root,"strPath/load_cov_functions.r"))

## set country list
remove(get_locations) # Remove duplicate get_locations
source(paste0(root,"strPath/get_locations.r"))
codes <- get_locations(level = "estimate")
iso3_map <- codes[,c("local_id_2013","ihme_loc_id")]
codes <- codes[,c("location_id","ihme_loc_id")]


####################
## Load covariates 
####################

## make a square dataset onto which we'll merge all covariates and data
data <- get_locations(level="estimate")
data <- data[,c("ihme_loc_id","location_id","location_name","super_region_name","region_name","parent_id")]
data$region_name <- gsub(" ", "_", gsub(" / ", "_", gsub(", ", "_", gsub("-","_",data$region_name))))
data$super_region_name <- gsub(" ", "_", gsub("/", "_", gsub(", ", "_", data$super_region_name)))
data <- merge(data, data.frame(year=1950:2015))

## load pop data, only for weighting the mean of education over ages.
pop <- read.dta(paste0(root,"/WORK/02_mortality/03_models/1_population/results/population_gbd2015.dta"))
pop <- pop[,c("location_id","ihme_loc_id","year","sex","age_group_id","pop")]
pop <- pop[pop$age_group_id > 7 & pop$age_group_id < 18 & pop$sex != "both",] # Only keep ages from 15-60

## Removed for now because age in education is now in 5-year age groups, from what I can tell
# ## Aggregate into 10-year age groups
#   pop$agegr <- NULL
#   for(aa in seq(8, 16, by = 2)) {
#     pop$agegr[pop$age_group_id %in% c(aa,aa+1)] <- aa
#   }
# 
# ## And onwards.. 
#   ## aggregate ages into 10-year age groups
#   pop <- aggregate(pop$pop, by=list(location_id=pop$location_id,ihme_loc_id=pop$ihme_loc_id,year=pop$year,sex=pop$sex,age_group_id=pop$agegr),sum)
#   names(pop)[names(pop)=="x"] <- "pop"

## append on china subnational pop from 1950-1963 by holding it constant in 1964
#   chnp <- pop[grepl("CHN_",pop$ihme_loc_id) & pop$ihme_loc_id != "CHN_44533" & pop$year == 1964,]
#   chnp <- chnp[rep(row.names(chnp), length(1950:1964)), ]
#   chnp$year <- rep(1950:1964,each=length(unique(chnp$ihme_loc_id))*length(unique(chnp$age))*length(unique(chnp$sex)))
#   pop <- pop[(!grepl("CHN_",pop$ihme_loc_id) & pop$ihme_loc_id != "CHN_44533") | pop$year >= 1964,] # Delete empty observations for China subnationals before 1964 if they exist
#   pop <- rbind(pop,chnp)

# for countries mising some pop numbers, keep pop constant from earliest year with data where NA 
# so it doesn't mess up the pop-weighted mean of education
for (ii in unique(pop$location_id)) {
  min <- min(pop$year[pop$location_id == ii & !is.na(pop$pop)],na.rm=T)
  if (min > 1950) {
    for (aa in unique(pop$age)) {
      for (ss in unique(pop$sex)) {
        pop$pop[pop$location_id==ii & pop$sex == ss & pop$age==aa & pop$year < min] <- pop$pop[pop$location_id == ii & pop$sex == ss & pop$age==aa & pop$year==min]
      }
    }
  }
}
rownames(pop) <- NULL


## load LDI, edu, and HIV from covariates DB
# Write a function to check that we have a square dataset from covariates
check_vals <- function(data, cov_type) {
  locs <- get_locations(level = "estimate")
  y_count <- 66
  l_count <- length(unique(locs$ihme_loc_id))
  a_count <- 20 
  s_count <- 2
  if(cov_type == "LDI_pc") target <- y_count * l_count
  if(cov_type == "education_yrs_pc") target <- y_count * l_count * a_count * s_count
  if(target == nrow(data)) {
    print(paste0(cov_type," has expected number of rows"))
  } else {
    stop(paste0("We expected ",target," but got ",nrow(data), " instead"))
  }
}

LDI <- get_cov_estimates('LDI_pc')

# LDI <- read_dta(paste(root,"strPath/ldi.dta", sep = ""))
LDI <- LDI[LDI$year_id <= 2015,c("location_id","year_id","mean_value")]


# Duplicate China national as China mainland
#   LDI_chn <- LDI[LDI$location_id == 6,]
#   LDI_chn$location_id <- 44533
#   LDI <- rbind(LDI,LDI_chn)
names(LDI)[names(LDI)=="year_id"] <- "year"
names(LDI)[names(LDI)=="sex_id"] <- "sex"
names(LDI)[names(LDI)=="mean_value"] <- "LDI_id"

LDI <- merge(LDI,codes,all=FALSE) # Drops China and England
check_vals(LDI,"LDI_pc")

edu <- get_cov_estimates('education_yrs_pc')

# edu <- read_dta(paste(root,"strPath/education.dta", sep = ""))

edu$year <- edu$year_id
edu <- edu[,c("location_id","year","sex_id","age_group_id","mean_value")]
names(edu)[names(edu)=="sex_id"] <- "sex"

# Duplicate China national as China mainland
#   edu_chn <- edu[edu$location_id == 6,]
#   edu_chn$location_id <- 44533
#   edu <- rbind(edu,edu_chn)

edu <- merge(edu,codes,all=FALSE, by = "location_id") # Drops China and England

check_vals(edu,"education_yrs_pc")

## Bring in HIV
## First is GBD2015 placeholder HIV numbers, then replaced by HIV from Spectrum runs where applicable
hiv <- read.csv(paste(root,"strPath/formatted_hiv_45q15.csv",sep=""),stringsAsFactors=F)
# new_hiv <- read.dta("C:/Users/gngu/Desktop/compiled_hiv_summary.dta")
new_hiv <- read.dta("strPath/compiled_hiv_summary.dta")
new_hiv <- new_hiv[new_hiv$agegroup == "45q15" & new_hiv$year >= 1970, c("iso3","sex","year","hiv_cdr")]
new_hiv$sex_new[new_hiv$sex == "male"] <- 1
new_hiv$sex_new[new_hiv$sex == "female"] <- 2
new_hiv$sex <- new_hiv$sex_new
new_hiv$sex_new <- NULL
names(new_hiv)[names(new_hiv)=="iso3"] <- "ihme_loc_id"
names(new_hiv)[names(new_hiv)=="hiv_cdr"] <- "death_rt_1559_mean"

new_locs <- unique(new_hiv$ihme_loc_id)
hiv <- hiv[!(hiv$ihme_loc_id %in% new_locs),]
hiv <- rbind(hiv,new_hiv)

# use hiv_scalars if hivscalars=T


# if(hivscalars){
#   # .9 scalars
#   hiv[hiv$ihme_loc_id %in% c("BWA"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("BWA"),]$death_rt_1559_mean*.9
#   # .8 scalars
#   hiv[hiv$ihme_loc_id %in% c("LSO", "MOZ", "SWZ", "ZWE"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("LSO", "MOZ", "SWZ", "ZWE"),]$death_rt_1559_mean*.8
#   # .7 scalars
#   hiv[hiv$ihme_loc_id %in% c("MWI","UGA"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("MWI","UGA"),]$death_rt_1559_mean*.7
#   # .65 scalars
#   hiv[grepl("KEN",hiv$ihme_loc_id),]$death_rt_1559_mean <- hiv[grepl("KEN",hiv$ihme_loc_id),]$death_rt_1559_mean*.65
#   # .6 scalars
#   hiv[hiv$ihme_loc_id %in% c("ZAF_484"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("ZAF_484"),]$death_rt_1559_mean*.6
#   # .5 scalars
#   hiv[hiv$ihme_loc_id %in% c("GAB", "NAM", "NGA", "ZMB"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("GAB", "NAM", "NGA", "ZMB"),]$death_rt_1559_mean*.5
#   # .3 scalars
#   hiv[hiv$ihme_loc_id %in% c("ERI"),]$death_rt_1559_mean <- hiv[hiv$ihme_loc_id %in% c("ERI"),]$death_rt_1559_mean*.3
#   
# }


# Add years before each country's min year, which had no HIV
hiv_rest <- data.table(hiv)
setkey(hiv_rest,ihme_loc_id,sex)
hiv_rest <- as.data.frame(hiv_rest[,
                                   list(year=1950:(min(year)-1),
                                        death_rt_1559_mean=0),
                                   key(hiv_rest)])
hiv <- rbind(hiv,hiv_rest)


# merge together
codmod <- merge(edu,hiv,by=c("ihme_loc_id","year","sex"))
codmod <- merge(codmod,LDI,by=c("location_id","ihme_loc_id","year"))
codmod$sex <- ifelse(codmod$sex==1,"male","female")

# format
codmod <- codmod[!is.na(codmod$age_group_id) & codmod$year <= 2015,]  
codmod$age_group_id <- as.numeric(codmod$age_group_id)
codmod <- codmod[codmod$age_group_id > 7 & codmod$age_group_id < 18 & codmod$ihme_loc_id %in% unique(data$ihme_loc_id),]
#   codmodtest2 <- codmod[codmod$age_group_id > 7 & codmod$age_group_id < 18,]
#   codmodtest3 <- codmodtest2[codmod$ihme_loc_id %in% unique(data$ihme_loc_id),]
codmod <- merge(codmod, pop, by=c("location_id","ihme_loc_id","sex","year","age_group_id"), all.x=T)
codmod <- ddply(codmod, c("ihme_loc_id", "year", "sex"), 
                function(x) { 
                  if (sum(is.na(x$pop))==0) w <- x$pop else w <- rep(1,length(x$pop))
                  data.frame(LDI_id = x$LDI_id[1], 
                             mean_yrs_educ = weighted.mean(x$mean_value, w),
                             hiv = ifelse(is.na(x$death_rt_1559_mean[1]), 0, x$death_rt_1559_mean[1])
                  )
                }
)

####################
## Prep data  
####################

## load 45q15 data, drop shocks and exclusions 
raw <- read.csv(paste(root, "strPath/raw.45q15.txt", sep=""), 
                header=T, stringsAsFactors=F)
raw <- subset(raw, raw$shock == 0 & raw$exclude == 0 & raw$adj45q15 < 1)
raw$year <- floor(raw$year)

## duplicate data in countries with only one data point (to avoid pinching in the GPR estimates) 
single <- table(raw$ihme_loc_id, raw$sex)
single <- melt(single)
single <- single[single$value == 1,]
single$ihme_loc_id <- as.character(single$Var.1)
single$sex <- as.character(single$Var.2)
for (ii in 1:nrow(single)) { 
  # Use subset instead of bracket subsetting because the brackets return multiple na values when I have nas for ihme_loc_id
  add <- subset(raw, raw$ihme_loc_id == single$ihme_loc_id[ii] & raw$sex == single$sex[ii]) 
  add$adj45q15 <- add$adj45q15*1.25
  raw <- rbind(raw, add) 
  add$adj45q15 <- (add$adj45q15/1.25)*0.75
  raw <- rbind(raw, add)
} 

n_raw <- nrow(raw) # Find the number of data rows before merging, to make sure none get dropped prior to regression

## assign data categories 
## category I: Complete
raw$category[raw$adjust == "complete"] <- "complete" 
## category II: DDM adjusted (include all subnational)
raw$category[raw$adjust == "ddm_adjusted"] <- "ddm_adjust"
## category III: GB adjusted
raw$category[raw$adjust == "gb_adjusted"] <- "gb_adjust" 
## category IV: Unadjusted 
raw$category[raw$adjust == "unadjusted"] <- "no_adjust"
## category V: Sibs
raw$category[raw$source_type == "SIBLING_HISTORIES"] <- "sibs" 

## assign each country to a data group 
raw$vr <- as.numeric(grepl("VR|SRS", raw$source_type))
types <- ddply(raw, c("location_id","ihme_loc_id","sex"),
               function(x) {
                 cats <- unique(x$category)
                 vr <- mean(x$vr)
                 vr.max <- ifelse(vr == 0, 0, max(x$year[x$vr==1]))
                 vr.num <- sum(x$vr==1)
                 if (length(cats) == 1 & cats[1] == "complete" & vr == 1 & vr.max > 1980 & vr.num > 10) type <- "complete VR only"
                 else if (("ddm_adjust" %in% cats | "gb_adjust" %in% cats) & vr == 1 & vr.max > 1980 & vr.num > 10) type <- "VR only"
                 else if ((vr < 1 & vr > 0) | (vr == 1 & (vr.max <= 1980 | vr.num <= 10))) type <- "VR plus"
                 else if ("sibs" %in% cats & vr == 0) type <- "sibs"
                 else if (!"sibs" %in% cats & vr == 0) type <- "other"
                 else type <- "none"
                 return(data.frame(type=type, stringsAsFactors=F))
               })     

#   ## split VR only groups by population size
#   mean.pop <- tapply(raw$exposure, paste(raw$ihme_loc_id, raw$sex, sep="#"), mean)  
#   types$mean.pop <- 0
#   for (ii in names(mean.pop)) {
#     ihme_loc_id <- strsplit(ii,"#")[[1]][1]
#     sex <- strsplit(ii,"#")[[1]][2]
#     jj <- (types$ihme_loc_id == ihme_loc_id & types$sex == sex & grepl("VR only", types$type))
#     if (mean.pop[ii] >= 300000 & sum(jj)>0) {
#       types$type[jj] <- paste(types$type[jj], "- large")
#       types$mean.pop[jj] <- mean.pop[ii]
#     } else if (mean.pop[ii] < 300000 & sum(jj)>0) {
#       types$type[jj] <- paste(types$type[jj], "- small") 
#       types$mean.pop[jj] <- mean.pop[ii]
#     } 
#   } 
#     


## drop excess variables
names(raw) <- gsub("adj45q15", "mort", names(raw))
names(raw) <- gsub("sd", "adjust.sd", names(raw))
raw <- raw[order(raw$ihme_loc_id, raw$year, raw$sex, raw$category),c("location_id","ihme_loc_id", "year", "sex", "obs45q15", "mort", "source_type", "category", "vr", "exposure", "comp", "adjust.sd")]

####################
## Merge everything together
####################

## merge all covariates to build a square dataset
data <- merge(data, codmod, all.x=T, by = c("ihme_loc_id","year"))

## merge in 45q15 data
data <- merge(data, raw, by=c("location_id","ihme_loc_id", "sex", "year"), all.x=T)
data$data <- as.numeric(!is.na(data$mort))
data$year <- data$year + 0.5

## merge in country data classification 
data <- merge(data, types, by=c("location_id","ihme_loc_id","sex"), all.x=T)
data$type <- as.character(data$type)
data$type[is.na(data$type)] <- "no data"

## Identify number of years covered by VR within each country after 1970
new_data <- data.table(unique(data[data$data==1 & !is.na(data$vr) & data$vr==1 & data$year>=1970,c("ihme_loc_id","year")]))
setkey(new_data,ihme_loc_id)
data_length <- as.data.frame(new_data[,length(year),by=key(new_data)])
names(data_length) <- c("ihme_loc_id","covered_years")

## Designate a cutoff point of covered years under which we will put into their own category
req_years <- 20
sibs_years <- 21 # How many DHS's do you need to consider a country "covered" by DHS? 2 DHS surveys should make for 10 years' worth of data (assuming no overlap)
data <- merge(data,data_length,by="ihme_loc_id",all.x=T)
data[is.na(data$covered_years),]$covered_years <- 0
data$type[data$type != "no data" & data$type != "sibs" & data$covered_years >= req_years] <- data$ihme_loc_id[data$type != "no data" & data$type != "sibs" & data$covered_years >= req_years]
data$type[data$type != "no data" & data$type != "sibs" & data$covered_years < req_years] <- paste0("sparse_data_",data$type[data$type != "no data" & data$type != "sibs" & data$covered_years < req_years])
data$type[data$type == "sibs" & data$covered_years >= sibs_years] <- "sibs_large"
data$type[data$type == "sibs" & data$covered_years < sibs_years] <- "sibs_small"

data$type[data$ihme_loc_id == "ALB"] <- "sparse_data_VR only" # We got new data for Albania that bumped it into its own country, but don't want to run param select 10/22

n_formatted <- nrow(data[!is.na(data$mort),])
if(n_raw != n_formatted) {
  stop(paste0("Number raw is ",n_raw," and number formatted is ", n_formatted))
}

## format and save
data <- data[order(data$ihme_loc_id, data$sex, data$year),
             c("location_id","location_name","super_region_name", "region_name",
               "parent_id", "ihme_loc_id", "sex", "year", "LDI_id", "mean_yrs_educ", "hiv", "obs45q15", "mort", "source_type", 
               "comp", "adjust.sd", "type", "category", "vr", "data", "exposure")]
write.csv(data, paste(root, "strPath/input_data.txt", sep=""),row.names=F)
write.csv(data, paste(root, "strPath/input_data_", Sys.Date(), ".txt", sep=""),row.names=F)


## if we're going to use hiv sims, we need to save those here
if (hivsims & hivupdate) {
  shiv <- read.dta(paste0("strPath/compiled_hiv_sims.dta"))
  # shiv <- read.dta("C:/Users/gngu/Desktop/compiled_hiv_sims.dta")
  shiv <- shiv[shiv$agegroup == "45q15" & shiv$year >= 1970,]
  shiv$agegroup <- NULL
  names(shiv)[names(shiv) == "draw"] <- "sim"
  ## the hiv sims aren't numbered 1-250, so we need to make sure they are
  combos <- length(unique(shiv$year))*length(unique(shiv$sex))*length(unique(shiv$iso3))
  ## make square dataset because things may be missing, so we need to identify them
  iso_sim <- paste0(shiv$iso3,"&&",shiv$sim)
  sqr <- expand.grid(unique(shiv$year),unique(shiv$sex),unique(iso_sim))
  names(sqr) <- c("year","sex","iso_sim")
  sqr$iso_sim <- as.character(sqr$iso_sim)
  sqr$iso3 <- sapply(strsplit(sqr$iso_sim,"&&"),"[",1)
  sqr$sim <- as.numeric(sapply(strsplit(sqr$iso_sim,"&&"),"[",2))
  sqr$iso_sim <- NULL
  shiv <- merge(sqr,shiv,all=T,by=c("year","sex","iso3","sim"))
  stopifnot(combos*250==length(shiv$year))
  
  shiv <- shiv[order(shiv$iso3,shiv$sex,shiv$sim,shiv$year),]
  ## No longer making up fake 2014/2015 numbers
#   shiv$row <- 1:length(shiv$hiv_cdr)
#   rows <- shiv$row[is.na(shiv$hiv_cdr) & shiv$year == 2014] 
#   shiv$hiv_cdr[is.na(shiv$hiv_cdr) & shiv$year == 2014] <- shiv$hiv_cdr[rows-1]*exp(log(shiv$hiv_cdr[rows-1]/shiv$hiv_cdr[rows-4])/3)
#   rows <- shiv$row[is.na(shiv$hiv_cdr) & shiv$year == 2015] 
#   shiv$hiv_cdr[is.na(shiv$hiv_cdr) & shiv$year == 2015] <- shiv$hiv_cdr[rows-1]*exp(log(shiv$hiv_cdr[rows-1]/shiv$hiv_cdr[rows-4])/3)
#   
  ## renumber the sims so that saving them in simfiles for 45q15 works
  shiv <- shiv[order(shiv$iso3,shiv$sex,shiv$year,shiv$sim),]
  shiv$sim <- rep(1:250,combos)
  
  ## for any locations not in this hiv simfile, we'll replicate all the mean values here for sims
#   locsub <- unique(data$ihme_loc_id[!data$ihme_loc_id %in% unique(shiv$iso3)])
#   extras <- expand.grid(unique(c(1970:2015)),unique(shiv$sex),locsub,1:250)
#   names(extras) <- c("year","sex","ihme_loc_id","sim")
#   hdat <- unique(data[,c("year","sex","ihme_loc_id","hiv")])
#   extras$year <- extras$year + .5
#   
#   extras <- merge(extras, unique(data[,c("year","sex","ihme_loc_id","hiv")]),by=c("year","sex","ihme_loc_id"),all.x=T)
#   names(extras)[names(extras) == "ihme_loc_id"] <- "iso3"
#   names(extras)[names(extras) == "hiv"] <- "hiv_cdr"
#   extras <- extras[order(extras$iso3,extras$sex,extras$year,extras$sim),c("year","sex","iso3","hiv_cdr","sim")]
#   extras$hiv_cdr[is.na(extras$hiv_cdr)] <- 0
#   extras$year <- extras$year - .5
#   extras <- unique(extras)
#   
#   shiv <- shiv[,c("year","sex","iso3","sim","hiv_cdr")]
#   shiv <- rbind(shiv,extras)
  
  stopifnot(length(shiv$year)==length(unique(shiv$year))*length(unique(shiv$sex))*length(unique(shiv$iso3))*length(unique(shiv$sim)))
  
  
  ## loop over sims and save simfiles so that they can be used to run models
  for (i in sort(unique(shiv$sim))) {
    print(i)
    temp <- shiv[shiv$sim == i,]
    stopifnot(length(temp$year)==length(unique(shiv$year))*length(unique(shiv$iso3))*length(unique(shiv$sex)))
    if (length(temp$year)!=length(unique(shiv$year))*length(unique(shiv$iso3))*length(unique(shiv$sex))) print(paste0(i," doesn't have right observations"))
    write.csv(temp,paste0("strPath/sim",i,".csv"),row.names=F)
  }
  
} 
  

