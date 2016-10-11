## Write R version gather code for alchol PAFs, will be much more efficient
## Gather all of the alcohol files and save into GBD2013 format

rm(list=ls()); library(foreign); library(data.table); library(stringr); library(haven)

if (Sys.info()[1] == 'Windows') {
  username <- "mcoates"
  root <- "J:/"
  code_dir <- "C:/Users/mcoates/Documents/repos/drugs_alcohol/"
  
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  code_dir <- paste("/ihme/code/risk/", username, "/drugs_alcohol/", sep="")
  if (username == "") code_dir <- paste0("/homes//drugs_alcohol/")  
  arg <- commandArgs()[-(1:3)] 
  print(arg)
  temp_dir <- arg[1]
  yyy <- as.numeric(arg[2])
  cause_cw_file <- arg[3]
  version <- as.numeric(arg[4])
  out_dir <- arg[5]
  
}

##############
## Set options
##############

debug <- 0
if (debug == 1) {
  temp_dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
  yyy <- 2000
  cause_cw_file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/meta/cause_crosswalk.csv")
  version <- 1
  out_dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output"	
}


## Expand functions (From PAF Calculator)

## demographics
sexes <- c(1,2)
ages <- c(seq(15,80,by=5))
age_group_ids <- c(8:21)
if (length(ages) != length(age_group_ids)) stop("these must be equal length for files below to read in right")

## some causes shouldn't be negative at the mean level
## list those that can so we can check for others with issues- make them stubs we can grepl
neg_causes <- c("IHD","Ischemic Stroke","Hemorrhagic","Hypertension","Diabetes")

## Prep cause crosswalk
cause_cw <- as.data.frame(fread(cause_cw_file))

## Load list of russian countries (these get the PAFs from the Russia calculation)
## Russian Federation all years
## Belarus all years
## Ukraine all years
## Estonia 1990
## Latvia 1990
## Lithuania 1990
## Moldova all years
if (yyy == 1990) in_russia_statement <- c(57,58,59,60,61,62,63)
## Belarus, Russia, Ukraine
if (yyy != 1990) in_russia_statement <- c(57,61,62,63)



##############
## Some cause groups
##############

cause_groups <- c("chronic", "ihd", "ischemicstroke", "inj_self") 
#cause_groups <- c("chronic")
d1 <- list()
missing_files <- c()
for (ccc in cause_groups) {
  for (sss in sexes) {
    for (aaa in age_group_ids) {
      read_age <- aaa
      cat(paste0("reading in ",read_age," ",sss," ",ccc,"\n")); flush.console()
      fl <- paste0(temp_dir,"/AAF_",yyy,"_a",read_age,"_s",sss,"_",ccc,".csv")
      if (file.exists(fl)) {
        d1[[paste0(read_age,sss,ccc)]] <- fread(fl)
      } else {
        missing_files <- c(missing_files,fl)
      }
    }
  }
}
d1 <- as.data.frame(rbindlist(d1,fill=T,use.names=T))
d1$V1 <- NULL

## show missing files
print(missing_files)

## make sure AAF_MEAN > 0 unless it's in our list of accepted < 0 PAF causes
## first recode male breast cancer to 0
d1[d1$DISEASE == "Breast Cancer - MEN" & d1$SEX == 1,names(d1)[grepl("draw",names(d1)) | names(d1) %in% c("AAF_PE","AAF_MEAN","SD")]] <- 0

## check for missing values where there should not be
check_missing <- function(data) {
  if (nrow(data[is.na(data$age),])> 0) stop("missing value in age_group_id")
  drs <- names(data)[grepl("draw",names(data))]
  dat <- lapply(drs,FUN=function(x) {
      cat(paste0("checking ",x,"\n")); flush.console()
      dis <- data.frame(REGION = data$REGION[is.na(data[,paste0(x)])],
                        DISEASE = data$DISEASE[is.na(data[,paste0(x)])],
                        SEX = data$SEX[is.na(data[,paste0(x)])],
                        age = data$age[is.na(data[,paste0(x)])],
                        draw = rep(x,length(data$age[is.na(data[,paste0(x)])])))
  })
  ret <- do.call("rbind",dat)
  return(ret)
}

test1 <- check_missing(d1)
if (nrow(test1) > 0) {
  print(test1)
  stop("Missing draws in the above draw/age/sex/cause combinations")
}

## cleaning up some variables
setnames(d1,"REGION","location_id")
d1$type <- NA
d1$type[grepl("Mortality",d1$DISEASE)] <- "Mortality"
d1$type[grepl("Morbidity",d1$DISEASE)] <- "Morbidity"
d1$type[is.na(d1$type)] <- "both"
for (strng in c("- Mortality ","- Morbidity ","- Ages 15-34","- Ages 35-64","- Ages 65 +","- Age_15-34","- Age_35-64","- Age 65 +","Ages 65+"," - MEN"," - WOMEN"," - ")) {
  d1$DISEASE <- gsub(strng,"",d1$DISEASE)
}
d1$DISEASE<-gsub("+","",d1$DISEASE,fixed = TRUE)
d1$DISEASE <- gsub("IHD ","IHD",d1$DISEASE)
d1$DISEASE <- gsub("Ischemic Stroke ","Ischemic Stroke",d1$DISEASE)
setnames(d1,"DISEASE","cause")


d1 <- d1[!((d1$cause %in% c("IHD","Ischemic Stroke")) & d1$type == "Morbidity"),]
d1$type[d1$cause %in% c("IHD","Ischemic Stroke")] <- "both"


d1$type[d1$cause == "Hemorrhagic Stroke" & d1$sex == 2] <- "both"

d1$AAF_PE <- d1$AAF_MEAN <- d1$SD <- NULL

#################
## Non-Russia files (all age injury files)
#################


cause_groups <- c("inj_aslt", "inj_mvaoth") 
d2 <- list()
for (ccc in cause_groups) {
  read_age <- aaa
  cat(paste0("reading in ",ccc,"\n")); flush.console()
  fl <- paste0(temp_dir,"/AAF_",yyy,"_",ccc,".csv")
  if (file.exists(fl)) {
    d2[[paste0(read_age,sss,ccc)]] <- fread(fl)
  } else {
    missing_files <- c(missing_files,fl)
  }
}

d2 <- as.data.frame(rbindlist(d2,fill=T,use.names=T))
d2$V1 <- NULL
setnames(d2,"REGION","location_id")

test2 <- check_missing(d2)
if (nrow(test2) > 0) {
  print(test2)
  stop("Missing draws in the above draw/age/sex/cause combinations")
}

d2$type <- NA
d2$type[grepl("Mortality",d2$DISEASE)] <- "Mortality"
d2$type[grepl("Morbidity",d2$DISEASE)] <- "Morbidity"
d2$type[is.na(d2$type)] <- "both"
for (strng in c(" - Mortality - WOMEN"," - Morbidity - WOMEN"," - Mortality - MEN"," - Morbidity - MEN")) {
  d2$DISEASE <- gsub(strng,"",d2$DISEASE)
}
setnames(d2,"DISEASE","cause")
d2$AAF_PE <- d2$AAF_MEAN <- d2$SD <- NULL


##########
## Russia causes
##########

cause_groups <- c("russia") 
d3 <- list()
for (ccc in cause_groups) {
  for (sss in sexes) {
    for (aaa in age_group_ids) {
      read_age <- aaa
      cat(paste0("reading in ",read_age," ",sss," ",ccc,"\n")); flush.console()
      fl <- paste0(temp_dir,"/AAF_",yyy,"_a",read_age,"_s",sss,"_",ccc,".csv")
      if (file.exists(fl)) {
        d3[[paste0(read_age,sss,ccc)]] <- fread(fl)
      } else {
        missing_files <- c(missing_files,fl)
      }
    }
  }
}
d3 <- as.data.frame(rbindlist(d3,fill=T,use.names=T))

test3 <- check_missing(d3)
if (nrow(test3) > 0) {
  print(test3)
  stop("Missing draws in the above draw/age/sex/cause combinations")
}

## cleaning up some variables
setnames(d3,"REGION","location_id")
d3$type <- NA
d3$type[grepl("Mortality",d3$DISEASE)] <- "Mortality"
d3$type[grepl("Morbidity",d3$DISEASE)] <- "Morbidity"
d3$type[is.na(d3$type)] <- "both"
for (strng in c(" - MEN"," - WOMEN")) {
  d3$DISEASE <- gsub(strng,"",d3$DISEASE)
}
setnames(d3,"DISEASE","cause")
d3$AAF_PE <- d3$AAF_MEAN <- d3$SD <- d3$V1 <- NULL

## keep the rows that are russia specific
## Note that there is some injuries here, but they won't take into account effects to non-drinkers... So I use the ones
d3 <- d3[d3$location_id %in% in_russia_statement & d3$cause %in% c("Pancreatitis", "Lower Respiratory Infections", "Stroke", "Tuberculosis", "Liver Cirrhosis"),]
d3$cause[d3$cause == "Stroke"] <- "Hemorrhagic Stroke"

## New Russia IHD and Ischemic Stroke Analysis results here
## These take the place of the IHD and Ischemic stroke numbers produced by the code above

cause_groups <- c("russ_ihd_is") 
d4 <- list()
for (ccc in cause_groups) {
  for (sss in sexes) {
    for (aaa in age_group_ids) {
      read_age <- aaa
      cat(paste0("reading in ",read_age," ",sss," ",ccc,"\n")); flush.console()
      fl <- paste0(temp_dir,"/AAF_",yyy,"_a",read_age,"_s",sss,"_",ccc,".csv")
      if (file.exists(fl)) {
        d4[[paste0(read_age,sss,ccc)]] <- fread(fl)
      } else {
        missing_files <- c(missing_files,fl)
      }
    }
  }
}
d4 <- as.data.frame(rbindlist(d4,fill=T,use.names=T))


test4 <- check_missing(d4)
if (nrow(test4) > 0) {
  print(test4)
  stop("Missing draws in the above draw/age/sex/cause combinations")
}

## cleaning up some variables
setnames(d4,"REGION","location_id")
d4$DISEASE[d4$DISEASE == "IHD Mortality"] <- "IHD"
d4$type <- NA
d4$type[grepl("Mortality",d4$DISEASE)] <- "Mortality"
d4$type[grepl("Morbidity",d4$DISEASE)] <- "Morbidity"
d4$type[is.na(d4$type)] <- "both"
setnames(d4,"DISEASE","cause")
d4$V1 <- d4$AAF_PE <- d4$AAF_MEAN <- d4$SD <- NULL
d4 <- d4[d4$location_id %in% in_russia_statement,]
    



## compile all data
d <- rbind(d1,d2,use.names=T)
d <- d[!d$cause == "TRUE",]

## Drop the rows that we should have gotten from the Russia file
d <- d[!(d$location_id %in% in_russia_statement & d$cause %in% c("Pancreatitis", "Lower Respiratory Infections", "Hemorrhagic Stroke", "Ischemic Stroke", "Tuberculosis", "Liver Cirrhosis", "IHD")),]

## add 3
d <- rbind(d,d3,use.names=T)
d <- d[!d$cause == "TRUE",]

## add 4
d <- rbind(d,d4,use.names=T)
d <- d[!d$cause == "TRUE",]

names(d) <- gsub("draw","draw_",names(d))

d$mortality[d$type %in% c("Mortality","both")] <- 1
d$morbidity[d$type %in% c("Morbidity","both")] <- 1

#if (nrow(unique(d[,names(d)[!names(d) %in% c("type","morbidity")]])) != nrow(unique(d))) stop("duplicates somewhere in morbidity")
#if (nrow(unique(d[,names(d)[!names(d) %in% c("type","mortality")]])) != nrow(unique(d))) stop("duplicates somewhere in mortality")
        

## Fix causes
d <- data.table(d)
cause_cw <- data.table(cause_cw)
d <- as.data.frame(merge(d,cause_cw,by="cause",all.x=T,allow.cartesian = T))

if (length(cause_cw$acause[!cause_cw$acause %in% unique(d$acause)]) > 0) {
  print(cause_cw$acause[!cause_cw$acause %in% unique(d$acause)])
  stop("missing causes")
} 
if (any(is.na(d$acause))) {
  print(unique(d$cause[is.na(d$acause)]))
  stop("missing acause for one or more causes")
}


## combine these
road <- d[d$acause %in% c("inj_trans_road_2wheel", "inj_trans_road_4wheel"),]
d <- d[!d$acause %in% c("inj_trans_road_2wheel", "inj_trans_road_4wheel"),]
d$cause <- NULL

road_count <- nrow(road)

## Use same method as PAF Independent aggregation (multiplicative)

for (i in 1:1000) {
  cat(paste0("converting draw ", i,"\n")); flush.console()
  road[,paste0("draw_",i)][road[,paste0("draw_",i)] >= 1] <- .9999
  road[,paste0("draw_",i)] <- log(1-road[,paste0("draw_",i)])
}

road <- data.table(road)
setkey(road,acause,age,type,mortality,morbidity,location_id,SEX,AGE_CATEGORY)
road <- as.data.frame(road[,lapply(.SD, sum, na.rm=F), by=key(road), .SDcols=c(names(road)[grepl("draw",names(road))])]) 
for (i in 1:1000) {
  cat(paste0("converting draw ", i,"\n")); flush.console()
  road[,paste0("draw_",i)] <- 1-exp(road[,paste0("draw_",i)])
}

d <- rbind(d,road,use.names=T)
d <- d[!d$acause == "TRUE",]


## Adjust neo_colorectal
colon <- d[d$acause %in% c( "neo_colorectal+rectal","neo_colorectal"),]
d <- d[!d$acause %in% c( "neo_colorectal+rectal","neo_colorectal"),]



for (i in 1:1000) {
  cat(paste0("converting draw ", i,"\n")); flush.console()
  colon[colon$acause == "neo_colorectal+rectal",paste0("draw_",i)] <- .35*colon[colon$acause == "neo_colorectal+rectal",paste0("draw_",i)]
  colon[colon$acause == "neo_colorectal",paste0("draw_",i)] <- .65*colon[colon$acause == "neo_colorectal",paste0("draw_",i)]
}
colon$acause[colon$acause == "neo_colorectal+rectal"] <- "neo_colorectal"

colon <- data.table(colon)
setkey(colon,acause,age,type,mortality,morbidity,location_id,SEX,AGE_CATEGORY)
colon <- as.data.frame(colon[,lapply(.SD, sum, na.rm=F), by=key(colon), .SDcols=c(names(colon)[grepl("draw",names(colon))])]) 

d <- rbind(d,colon,use.names=T)
d <- d[!d$acause == "TRUE",]

  ## Expand out to most detailed causes
  ##acause_expand acause (was a stata function greg wrote for GBD 2013)
  ## now using stan's cause expanding from his J:/temp- should use database in future, was using Greg's GBD 2013 jtemp before
## stata code
#joinby ancestor_cause using "$j/temp/stan/GBD_2015/risks/cause_expand.dta", unmatched(master)
#replace ancestor_cause = descendant_cause if ancestor_cause!=descendant_cause & descendant_cause!=. // if we have a no match (for example a sequelae)
#drop descendant_cause _merge
#rename ancestor_cause cause_id
## cause_expand <- as.data.frame(read_dta(paste0(root,"/temp/gregdf/expand_functions/acause.dta")))


acause <- as.data.frame(read_dta(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/acause_causeid_map.dta")))
cause_expand <- as.data.frame(read_dta(paste0(root,"/temp/stan/GBD_2015/risks/cause_expand.dta")))
if (length(d$acause[!unique(d$acause) %in% acause$acause])) stop("acauses will not map")

d <- data.table(d)
d <- merge(d,acause,by=c("acause"),all.x=T)
if (length(d$cause_id[is.na(d$cause_id)]) > 0) stop("missing cause ids")
setnames(d,"cause_id","ancestor_cause")
cause_expand <- data.table(cause_expand)
d <- merge(d,cause_expand,all.x=T,by="ancestor_cause",allow.cartesian = T)
## get acause again
setnames(d,"descendant_cause","cause_id")
d$acause <- NULL
if (any(is.na(d$cause_id))) stop("missing cause_id")
d <- merge(d,acause,by="cause_id",all.x=T)
d <- as.data.frame(d)

## query this from somewhere later for robustness
age_expand <- as.data.table(data.frame(age=c(0,0,0,1,seq(5,80,by=5)),age_group_id=c(2:21)))
if (any(!unique(d$age) %in% unique(age_expand$age))) stop("ages not in possible ages")
d <- data.table(d)
d <- as.data.frame(merge(d,age_expand,by="age",all.x=T,allow.cartesian=T))

## gbd names
setnames(d,"SEX","sex_id")
d$AGE_CATEGORY <- d$ancestor_cause <- d$age <- d$type <- NULL

d <- as.data.frame(d)

## Recode breast cancer for men
## The code that generates breast cancer for men appears to have floating point issues, where it isn't exactly 0. Recode to 0 here
for (i in 1:1000) {
  d[d$acause == "neo_breast" & d$sex_id == 1,paste0("draw_",i)] <- 0
}

## Add on 100% attributable cause
alc <- expand.grid(location_id=unique(d$location_id),age_group_id=unique(d$age_group_id),sex_id=unique(d$sex_id),mortality=1,morbidity=1)
alc$acause <- "mental_alcohol"
alc$cause_id <- 560
for (i in 1:1000) {
  alc[,paste0("draw_",i)] <- 1
}

d <- rbind(alc,d,use.names=T)
d <- d[!d$acause == "TRUE",]


for (i in 1:1000) {
  setnames(d,paste0("draw_",i),paste0("draw_",(i-1)))
}
d <- as.data.frame(d)


## Instead of saving these separately by sex/year save two files, and save them in parallel in next step
## mort
write.csv(d[d$mortality == 1 & !is.na(d$mortality),],paste0(out_dir,"/",version,"_prescale/paf_yll_",yyy,".csv"),row.names=F)
## morb
write.csv(d[d$morbidity == 1 & !is.na(d$morbidity),],paste0(out_dir,"/",version,"_prescale/paf_yld_",yyy,".csv"),row.names=F)


## new version saves one big file, laucnhes several jobs to resave everything
## Save
# for (loc in unique(d$location_id)) {
#   for (s in unique(d$sex_id)) {
#     cat(paste0("writing ",loc," sex ",s,"\n")); flush.console()
#     ## mort
#     write.csv(d[d$location_id == loc & d$sex_id == s & d$mortality == 1 & !is.na(d$mortality),],paste0(out_dir,"/",version,"_prescale/paf_yll_",loc,"_",yyy,"_",s,".csv"),row.names=F)
#     ## morb
#     write.csv(d[d$location_id == loc & d$sex_id == s & d$morbidity == 1 & !is.na(d$morbidity),],paste0(out_dir,"/",version,"_prescale/paf_yld_",loc,"_",yyy,"_",s,".csv"),row.names=F)
#   }
# }



