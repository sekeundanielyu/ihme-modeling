## Generate and graph consumption by age group/year and sex
rm(list=ls())
  library(foreign); library(reshape); library(lattice); library(latticeExtra); library(MASS);library(scales)


	# For testing purposes, set argument values manually if in windows
 if (Sys.info()["sysname"] == "Windows") {
		arg <- c(2010, 1, 1, "chronic", "J:/WORK/05_risk/01_database/02_data/drugs_alcohol/04_paf/04_models/code", "J:/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output", "/clustertmp/gregdf/alcohol_temp", 1, TRUE, 10, 10)
	} else {
    arg <- c(2010, 1, 1, "chronic", "/home/j/WORK/05_risk/01_database/02_data/drugs_alcohol/04_paf/04_models/code", "/home/j/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output", "/clustertmp/gregdf/alcohol_temp", 1, TRUE, 10, 10)                  # First args are for unix use only
	}
 # root <- "J:/"
## Read in arguments passed in by shell script.
#	yyy <- as.numeric(arg[1])                     # Year for current analysis
#	aaa <- as.numeric(arg[2])                     # Age-group for current analysis (1=15-34, 2=35-64, 3=65+)
#	sss <- as.numeric(arg[3])                     # Sex for current analysis (1=male, 2=female)
#	ccc <- arg[4]                                 # cause group for current analysis
	code.dir <- arg[5]                            # Code directory
	data.dir <- arg[6]                            # Data directory
	out.dir <- arg[7]                             # Directory to put temporary draws in
	mycores <- as.numeric(arg[8])                 # Number of cores (which can be used to parallelize)
	myverbose <- as.logical(arg[9])               # Whether to print messages to console showing progress
	myB <- as.numeric(arg[10])            # Number of draws to run (higher than save to match EG methods)
	mysavedraws <- as.numeric(arg[11])            # Number of draws to save


## bring in input data
years <- c(1990,1995,2000,2005,2010,2013)

data <- list()
count <- 1
for (yyy in years) {
  data[[count]] <- read.csv(paste0(data.dir,"/alc_data_",yyy,".csv"),stringsAsFactors=F)
  data[[count]]$year <- yyy
  count <- count + 1
}
data <- do.call("rbind",data)

## bring in age splitting values
ages <- seq(from=15,to=80,by=5)
sexes <- c(1,2)

agesplit <- list()
count <- 1
for (yyy in years) {
  for (aaa in ages) {
    for (sss in sexes) {
      toname <- paste(yyy,aaa,sss,sep="_")
      cat(paste0(toname," \n"))
      agesplit[[count]] <- read.csv(paste0("/clustertmp/gregdf/alcohol_temp","/alc_age_frac_",toname,".csv"),stringsAsFactors=F)
      names(agesplit)[count] <- toname
      agesplit[[count]]$sex <- NULL
      agesplit[[count]]$year <- NULL
      count <- count + 1
      ## to save space, since we have the year age sex in the list title, we can drop the year age sex in the dataset
    }
  }
}

## define function to get consumption among drinkers
computeMeanStratum <- function(popsize, age_fraction, pabs, pformer, pca, adjustPCA = 0.8)
{
  ## get age group that corresponds to the age
  if (age_fraction[1] < 34) agegroup <- 1
  if (age_fraction[1] > 34 & age_fraction[1] < 59) agegroup <- 2
  if (age_fraction[1] > 59) agegroup <- 3


  ## calculate adjusted pca- this is among whole population
  pca <- pca * 1000 * 0.789 * adjustPCA / 365
  ## percent of drinkers in each age group
  pdrk <- (1 - pabs - pformer)
  ## alcohol consumption total is just per capita consumption times population
  tot <- pca * sum(popsize)
  ## consumption total in this age group is total consumption times fraction of total consumption in this age
  cons_age <- tot*age_fraction[3]
  ## consumption per drinker in this age group is consumption in this age group divided by the number of drinkers
  mu <- cons_age/(pdrk[agegroup]*age_fraction[2])
  mu <- unlist(mu)
  
  meancons <- cons_age/age_fraction[2]
  meancons <- unlist(meancons)

  return(mu)
}


## NOW WE HAVE ALL THE INPUT DATA WE NEED, AND THE FUNCTION WE NEED--- let's see if we can push this to get most out of it without loops
B <- 1:100
cons <- list()
count <- 1


sexes <- 1:2
ages <- seq(from=15,to=80,by=5)
years <- c(1990,1995,2000,2005,2010,2013)
regions <- sort(unique(data$REGION))
combos <- c()
for (i in regions) {
  for (j in sexes) {
    for (a in ages) {
      for (y in years) {
        combos <- c(combos,paste(i,j,a,y,sep="_"))
      }
    }
  }
}

getregs <- function(x,data1=data,agesplit1=agesplit) {
    full <- strsplit(x,split="_")[[1]]
    if (full[1] %in% c("CHN","GBR","MEX")) {
      i <- paste0(full[1],"_",full[2])
      sss1 <- full[3]
      aaa1 <- full[4]
      yyy1 <- full[5]
    } else {
      i <- full[1]
      sss1 <- full[2]
      aaa1 <- full[3]
      yyy1 <- full[4]
    }

    regionaldata <- data1[data1$year == yyy1 & data1$SEX == sss1 & data1$REGION == i,]
    cat("Region:", x," \n")
        pca <- rnorm(B, mean = regionaldata$PCA[1], sd = sqrt(regionaldata$VAR_PCA[1]))
        pca[pca <= 0.001] <- 0.001

        ## sample proportion of abstainers and former drinkers per age category

        pabs1 <- rnorm(B, mean = regionaldata$LIFETIME_ABSTAINERS[1],
                     sd = sqrt(regionaldata$LIFETIME_ABSTAINERS[1] * (1 -
                       regionaldata$LIFETIME_ABSTAINERS[1]) / 1000))
        pabs2 <- rnorm(B, mean = regionaldata$LIFETIME_ABSTAINERS[2],
                     sd = sqrt(regionaldata$LIFETIME_ABSTAINERS[2] * (1 -
                       regionaldata$LIFETIME_ABSTAINERS[2]) / 1000))
        pabs3 <- rnorm(B, mean = regionaldata$LIFETIME_ABSTAINERS[3],
                     sd = sqrt(regionaldata$LIFETIME_ABSTAINERS[3] * (1 -
                       regionaldata$LIFETIME_ABSTAINERS[3]) / 1000))

        pform1 <- rnorm(B, mean = regionaldata$FORMER_DRINKERS[1],
                     sd = sqrt(regionaldata$FORMER_DRINKERS[1] * (1 -
                       regionaldata$FORMER_DRINKERS[1]) / 1000))
        pform2 <- rnorm(B, mean = regionaldata$FORMER_DRINKERS[2],
                     sd = sqrt(regionaldata$FORMER_DRINKERS[2] * (1 -
                       regionaldata$FORMER_DRINKERS[2]) / 1000))
        pform3 <- rnorm(B, mean = regionaldata$FORMER_DRINKERS[3],
                     sd = sqrt(regionaldata$FORMER_DRINKERS[3] * (1 -
                       regionaldata$FORMER_DRINKERS[3]) / 1000))

        pdrink1 <- rnorm(B, mean = regionaldata$DRINKERS[1],
                     sd = sqrt(regionaldata$DRINKERS[1] * (1 -
                       regionaldata$DRINKERS[1]) / 1000))
        pdrink2 <- rnorm(B, mean = regionaldata$DRINKERS[2],
                     sd = sqrt(regionaldata$DRINKERS[2] * (1 -
                       regionaldata$DRINKERS[2]) / 1000))
        pdrink3 <- rnorm(B, mean = regionaldata$DRINKERS[3],
                     sd = sqrt(regionaldata$DRINKERS[3] * (1 -
                       regionaldata$DRINKERS[3]) / 1000))

        pdrink1[pdrink1 < 0.001] <- 0.001
        pdrink2[pdrink2 < 0.001] <- 0.001
        pdrink3[pdrink3 < 0.001] <- 0.001

        pform1[pform1 < .0001] <- .0001
        pform2[pform2 < .0001] <- .0001
        pform3[pform3 < .0001] <- .0001

        ## check proportions for validity (in each age category)
        ## SCALING ALL ESTIMATES TO 1 USING AN ENVELOPE METHOD

        tsum1 <- pabs1 + pform1 + pdrink1
        pabs1 <- (pabs1 / tsum1)
        pform1 <- (pform1 / tsum1)

        tsum2 <- pabs2 + pform2 + pdrink2
        pabs2 <- (pabs2 / tsum2)
        pform2 <- (pform2 / tsum2)

        tsum3 <- pabs3 + pform3 + pdrink3
        pabs3 <- (pabs3 / tsum3)
        pform3<- (pform3 / tsum3)

        ## combine proportions
        pabs <- cbind(pabs1, pabs2, pabs3)
        pform <- cbind(pform1, pform2, pform3)


    mu <- lapply(B,function(b) {computeMeanStratum(popsize = regionaldata$POPULATION,
                   age_fraction=agesplit1[[paste(yyy1,aaa1,sss1,sep="_")]][agesplit1[[paste(yyy1,aaa1,sss1,sep="_")]]$iso3 == i,c("age","mean_pop",paste0("draw_",b))],
                   pabs = pabs[b,], pformer = pform[b,], pca = pca[b],
                   adjustPCA = .8)} )
    mu <- unlist(mu)
    #max <- max(mu)
    #min <- min(mu)
    #upper <- quantile(mu,probs=.975)
    #lower <- quantile(mu,probs=.025)
    #mean <- mean(mu)
    #summ <- c(max,min,upper,lower,mean)
    
    return(mu)
    }
    
    lcombos <- as.list(combos)
    ## for testing lcombos1 <- as.list(combos[1:15])
    
    require("parallel")
    ret <- mclapply(lcombos,function(x) {getregs(x)},mc.cores=12)
    ret <- do.call("rbind",ret)
    ret <- cbind(combos,ret)
    
    write.csv(ret,"/clustertmp//alcohol_temp/pca_breakdown_draws.csv",row.names=F)
    

