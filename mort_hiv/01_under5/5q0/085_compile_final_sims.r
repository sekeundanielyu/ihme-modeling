## 2/21/2014
## Sample 1000 draws from all of the GPR sims to be the official draws

rm(list=ls())

library(foreign); library(plyr); library(reshape); library(data.table);
if (Sys.info()[1]=="Windows") root <- "" else root <- ""

## load parameters
cc <- commandArgs()[3]
seed <- as.integer(commandArgs()[4])
parents <- c("CHN","IND","GBR","MEX")

print(paste("seed",seed))

set.seed(seed)

######################
## Set directories
######################

dirs <- NULL
dirs[["codes"]] <- paste(root,"",sep="")
dirs[["hiv"]] <- paste(root,"",sep="")
dirs[["in"]] <- ""
dirs[["out"]] <- paste(root, "", sep="")

######################
## Load codes
######################

setwd(dirs[["codes"]])
codes <- read.csv("IHME_COUNTRY_CODES_Y2013M07D26.CSV",stringsAsFactors=F)
codes <- unique(na.omit(codes[codes$indic_cod == 1,c("iso3","gbd_country_iso3")]))
codes <- codes[codes$gbd_country_iso3 != "ZAF",]

#####################
## Load hiv sims and final-sim to hiv-sim crosswalk
#####################

setwd(dirs[["hiv"]])

#####
## crosswalk
#####

cw <- read.csv("final_sim_hiv_sim_crosswalk.csv",stringsAsFactors=F)

## get numbers of simulations
nsim <- max(cw$endsim)
nhiv <- max(cw$hivsim)
sample_size <- nsim/nhiv 

## testing 
# nsim <- 20
# nhiv <- 5
# sample_size <- 4
# cc <- "TZA"

#####
## hiv sims
#####

hiv <- read.csv("formatted_hiv_5q0_sim_level.csv",stringsAsFactors=F)
hiv$year <- hiv$year + 0.5
names(hiv)[names(hiv)=="sim"] <- "hivsim"

## get list of missing countries
missing <- codes$iso3[!(codes$iso3 %in% unique(hiv$iso3))]

# Get subnational HIV if it has no estimates by copying national for all provinces (temporary fix until we get subnational HIV)
if (cc %in% missing) {
  
  ## save parent country hiv
  parents_hiv <- hiv[hiv$iso3 %in% parents,]
  parents_hiv$gbd_country_iso3 <- parents_hiv$iso3
  parents_hiv$iso3 <- NULL
  
  #get subnational iso3s and years
  subnat <- codes[codes$iso3 == cc,c("iso3","gbd_country_iso3")]  
  
  #merge national hiv onto provinces
  hiv <- merge(subnat,parents_hiv,by=c("gbd_country_iso3"))
  hiv$gbd_country_iso3 <- NULL
  
} else {
  ## save country specific hiv
  hiv <- hiv[hiv$iso3 == cc,]
}

## add missing years
tmp <- list()
length(tmp) <- nhiv
for (sim in 1:nhiv) {
  tmp[[sim]] <- data.frame(iso3=rep(cc,length(1950:(floor(min(hiv$year)-1)))),
                           year=1950:(floor(min(hiv$year)-1)),
                           hivsim=sim,
                           hiv=0)
}

tmp <- do.call(rbind,tmp)
tmp$year <- tmp$year + 0.5
hiv <- rbind(hiv,tmp)

#####################
## Load gpr sims for a country, then sample (nsim/nhiv) sims from each hivsim scenario in order to get (nsim) final sims.
##    Do this by year, so that all years have consistent hiv pattern.
##    This allows 5q0 and 45q15 final sim numbers to match up with consistent hiv scenarios.
#####################

setwd(dirs[["in"]])
all <- list()
length(all) <- nhiv
for (i in 1:nhiv) {
  all[[i]] <- data.table(read.csv(paste("gpr_",cc,"_",i,"_sim.txt",sep="")))
  setkey(all[[i]],iso3,year)
  all[[i]] <- all[[i]][,
                       list(mort=sample(mort,sample_size,replace=F),
                            hivsim=rep(i,sample_size)),
                       key(all[[i]])]
  all[[i]] <- cbind(all[[i]],sim=rep(cw$endsim[cw$hivsim==i],length(unique(all[[i]]$year))))
}
all <- do.call(rbind,all)

## merge hiv death rate numbers onto this dataset
all <- merge(all,hiv,by=c("iso3","year","hivsim"))
all$hivsim <- all$hiv
all$hiv <- NULL
all$sim <- all$sim - 1

###########################
## collapse to get aggregated dataset
###########################

all <- data.table(all)
setkey(all,iso3,year)
agg <- all[,
           list(mort_med=mean(mort),
                mort_lower=quantile(mort,0.025),
                mort_upper=quantile(mort,0.975)),
           key(all)]

####################################################
## save sim-level dataset and aggregated datasets
####################################################

setwd(dirs[["out"]])
write.csv(all,paste("gpr_",cc,"_sim.txt",sep=""),row.names=F)
write.csv(agg,paste("gpr_",cc,".txt",sep=""),row.names=F)
