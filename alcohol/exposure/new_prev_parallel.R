## make new prevalence data from DisMod to swap in 


rm(list=ls()); library(foreign)
library(data.table)

if (Sys.info()[1] == 'Windows') {
  root <- "J:/"
} else {
  root <- "/home/j/"
}

## get the arguments passed from submission
year <- commandArgs()[3]
version <- commandArgs()[4]
## year <- 1990
## version <- "v12"


## get geographic units
countries <- read.csv(paste0(root,"WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/intermediate/alc_data_1990.csv"),stringsAsFactors=F)
countries <- unique(countries$REGION)

## loop over geographic units to bring in files
data <- list()
k <- 1
for (i in 1:length(unique(countries))) {
  for (j in c("male","female")) {
    for (type in c("current_drinker_incidence","former_drinker_incidence","lifetime_abstainer_incidence","binger_incidence","binge_times_incidence")) {
      iso <- countries[i]
      cat(paste(iso,j,type,year,"\n"))
      data[[k]] <- read.csv(paste0(root,"temp/dccasey/Alcohol/alc_cat/rescaleresults/",version,"/",type,"_",iso,"_",year,"_",j,".csv"),stringsAsFactors=F)
      data[[k]] <- data[[k]][data[[k]]$age >= 15 & data[[k]]$age < 81,]
      data[[k]]$type <- type
      data[[k]]$sex <- j
      data[[k]]$iso3 <- iso
      data[[k]]$denominator <- NULL
      k <- k + 1
    }
  }
}
data <- do.call("rbind",data)

binge_ses <- data[data$type %in% c("binger_incidence","binge_times_incidence"),]

## now have dataset, need to collapse to mean level from sim level, then need to population weight to aggregate age groups
data$mean <- apply(as.matrix(data[,names(data)[grepl("draw",names(data))]]),MARGIN=1,FUN=function(x) {mean(x)})

## drop the draws
data <- data[,names(data)[!grepl("draw",names(data))]]
data$year <- year

## now need to grab population so that we can aggregate across age groups
pop <- read.dta(paste0(root,"WORK/02_mortality/04_outputs/02_results/envelope.dta"))
pop <- pop[pop$location_type %in% c("country", "subnational") & pop$year == year & pop$age > 14 & pop$age < 81 & pop$sex != 3,]
pop <- pop[,c("iso3","year","age","sex","mean_pop")]
data$sex[data$sex == "male"] <- "1"
data$sex[data$sex == "female"] <- "2"
data$sex <- as.numeric(data$sex)
data <- merge(data,pop,by=c("iso3","year","age","sex"),all.x=T)


data$type[data$type == "current_drinker_incidence"] <- "DRINKERS"
data$type[data$type == "former_drinker_incidence"] <- "FORMER_DRINKERS"
data$type[data$type == "lifetime_abstainer_incidence"] <- "LIFETIME_ABSTAINERS"
data$type[data$type == "binger_incidence"] <- "BINGERS"
data$type[data$type == "binge_times_incidence"] <- "BINGE_TIMES"

binge_ses$type[binge_ses$type == "binger_incidence"] <- "BINGERS"
binge_ses$type[binge_ses$type == "binge_times_incidence"] <- "BINGE_TIMES"

## now need to reshape before we weight collapse to aggregate age groups (because the bingers needs to be weighted by drinkers, not total pop)
data <- reshape(data, timevar="type",idvar=c("iso3","age","sex","year","mean_pop"),direction="wide")

data$drkpop <- data$mean.DRINKERS*data$mean_pop
data$bingepop <- data$mean.BINGERS*data$drkpop

data$agegroup[data$age < 34] <- 1
data$agegroup[data$age > 34 & data$age < 59] <- 2
data$agegroup[data$age > 59] <- 3

dat <- data.table(data)
setkey(dat,agegroup,sex,iso3,year)
dat <- as.data.frame(dat[,list(DRINKERS=weighted.mean(mean.DRINKERS,w=mean_pop),FORMER_DRINKERS=weighted.mean(mean.FORMER_DRINKERS,w=mean_pop),
                                 LIFETIME_ABSTAINERS=weighted.mean(mean.LIFETIME_ABSTAINERS,w=mean_pop),BINGERS=weighted.mean(mean.BINGERS,w=drkpop),
                                 BINGE_TIMES=weighted.mean(mean.BINGE_TIMES,w=bingepop)),by=key(dat)])

## now dat has the results we want, but we need to add the binge_times_se
binge_ses$year <- year
binge_ses$sex[binge_ses$sex == "male"] <- "1"
binge_ses$sex[binge_ses$sex == "female"] <- "2"
binge_ses$sex <- as.numeric(binge_ses$sex)
binge_ses <- merge(binge_ses,data[,c("iso3","age","sex","year","agegroup","bingepop","drkpop")],by=c("iso3","age","sex","year"),all.x=T)

for (i in 0:999) {
  print(i)
  binge_ses[binge_ses$type == "BINGE_TIMES",paste0("draw_",i)] <- binge_ses[binge_ses$type == "BINGE_TIMES",paste0("draw_",i)]*binge_ses$bingepop[binge_ses$type == "BINGE_TIMES"]
  binge_ses[binge_ses$type == "BINGERS",paste0("draw_",i)] <- binge_ses[binge_ses$type == "BINGERS",paste0("draw_",i)]*binge_ses$drkpop[binge_ses$type == "BINGERS"]
}

binge_ses$age <- NULL

binge_ses <- aggregate(binge_ses[,c(names(binge_ses[grepl("draw",names(binge_ses))]),"bingepop","drkpop")],by=list(agegroup=binge_ses$agegroup,sex=binge_ses$sex,
  iso3=binge_ses$iso3,year=binge_ses$year, type=binge_ses$type),FUN=function(x) {sum(x)})

for (i in 0:999) {
  binge_ses[binge_ses$type == "BINGE_TIMES",paste0("draw_",i)] <- binge_ses[binge_ses$type == "BINGE_TIMES",paste0("draw_",i)]/binge_ses$bingepop[binge_ses$type == "BINGE_TIMES"]
  binge_ses[binge_ses$type == "BINGERS",paste0("draw_",i)] <- binge_ses[binge_ses$type == "BINGERS",paste0("draw_",i)]/binge_ses$drkpop[binge_ses$type == "BINGERS"]
}

binge_ses$SE <- apply(as.matrix(binge_ses[,names(binge_ses)[grepl("draw",names(binge_ses))]]),MARGIN=1,FUN=function(x) {sd(x)})
binge_ses <- binge_ses[,names(binge_ses)[!grepl("draw",names(binge_ses))]]
binge_ses$bingepop <- binge_ses$drkpop <- NULL
binge_ses2 <- binge_ses[binge_ses$type == "BINGE_TIMES",]
binge_ses <- binge_ses[binge_ses$type == "BINGERS",]
names(binge_ses)[names(binge_ses) == "SE"] <- "BINGERS_SE"
names(binge_ses2)[names(binge_ses2) == "SE"] <- "BINGE_TIMES_SE"
binge_ses$type <- binge_ses2$type <- NULL
binge_ses <- merge(binge_ses,binge_ses2,all=T)

dat <- merge(dat,binge_ses[,c("agegroup","iso3","year","sex","BINGE_TIMES_SE","BINGERS_SE")],by=c("iso3","year","agegroup","sex"),all.x=T)

write.csv(dat,paste0(root,"/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/intermediate/swap_prev_",year,".csv"),row.names=F)


