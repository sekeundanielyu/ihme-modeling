###################################################################################
#### The program to compute the AAFs for chronic diseases and their confidence ####
#### intervals is split into 3 files. chronicRR.R contains all the relative    ####
#### risk functions, chronicAAF.R contains the definitions of all the          ####
#### functions and computational steps required to derive the AAFs and the CIs ####
#### chronicAnalysis.R defines the input file and output destination and runs  ####
#### the computations. This is the only file that needs to be run.             ####
###################################################################################

## computeMeanStratum: computes the mean alcohol consumption for each age group
## in a given region and for a given sex. 

## popsize: Vector of X. Population size in the X age groups.
## relcoef: Vector of X. Relative coefficients for the X age groups.
## pabs: Vector of X. Proportion of abstainers for the X age groups.
## pformer: Vector of X. Proportion of former drinkers for the X age groups.
## pca: Single value or vector of X identical values. Per capita consumption of alcohol.

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
  
  return(mu)
}

############################################################################
#### the following function, computeMean, will compute the mean alcohol ####
#### consumption and standard deviation for all the inputs using        ####
#### the function computeMeanStratum                                    ####
############################################################################

## compute per gender - age category - region:
## mean consumption, SD, and the resulting estimates of the parameters
## for the gamma distribution (used to model alcohol consumption)
computeMean <- function(data, regional_agefrac, age = NULL, gender = NULL, adjustPCA = 0.8)
{
  ## handle gender subsetting
  if(!is.null(gender))
  {
    ## convert string input to numeric
    if(is.character(gender)) gender <- ifelse(gender == "male", 1, 2)
    ## take relevant gender subset,
    ## do not take age subset because mean of one age group is relative to the other groups, thus need all groups for calculation
    data <- subset(data, SEX %in% gender)
  }

  ## set up return argument
  ret <- subset(data, select = c(REGION, SEX, AGE_CATEGORY,
                        #PCA, VAR_PCA, POPULATION, 
                        LIFETIME_ABSTAINERS, FORMER_DRINKERS))
  if (age < 34) ret <- ret[ret$AGE_CATEGORY == 1,]
  if (age > 34 & age < 59) ret <- ret[ret$AGE_CATEGORY == 2,]
  if (age > 59) ret <- ret[ret$AGE_CATEGORY == 3,]
   ret$age <- age
   ret$MEAN <- NA
  
  
  ## generate index distinguishing all groups for which
  ## a separate mean should be calculated, namely all the
  ## possible region and sex combinations (labeled "pattern")
  
  index <- with(data, paste(REGION, SEX, sep = ":"))
  patterns <- unique(index)

  ## calculate mean
  for (i in patterns)
    {
      pat <- strsplit(i, ":")[[1]]
      dat <- data[data$REGION == pat[1] & data$SEX == pat[2],]
      ret$MEAN[ret$REGION == pat[1] & ret$SEX == pat[2]] <- computeMeanStratum(
      popsize = dat$POPULATION, age_fraction=regional_agefrac[,c("age","pop_scaled","mean_frac")],
      pabs = dat$LIFETIME_ABSTAINERS, pformer = dat$FORMER_DRINKERS,
      pca = dat$PCA, adjustPCA = adjustPCA)
    }
    ret$MEAN <- unlist(ret$MEAN)
  ## calculate sd (different factor for men and women)
  ret$SD <- 1.171 * ret$MEAN
  ret$SD[ret$SEX == 2] <- 1.258 * ret$MEAN[ret$SEX == 2]
   
  ## calculate estimates for the parameters of a gamma distribution
  ret$K <- ret$MEAN^2 / ret$SD^2 ## README: this is always (1/1.171)^2 or 1/1.258^2
  ret$THETA <- ret$SD^2 / ret$MEAN 
  
  ## take subset on age category
  if(!is.null(age)) ret <- subset(ret, age %in% age)

  ## return calculated means
  return(ret)
}



#####################################################################
#### This function, calculateAAF, computes the AAFs and can use  ####
#### a defined number of cores (only available on linux so far)  ####
#####################################################################

## calculation of AAFs:
## input necessary:
## k and theta - from dataset returned of computeMean()
## prop of abstainers and former drinker per stratum  - from dataset returned of computeMean()
## region, sex, age category - from dataset returned of computeMean()
## number of diseases, relative risk function, coefficients, log relative risks for former drinkers - from list(s)-object
## README:
## attention: expects data structure like this:
## oralcancermale = list(disease = "Oral Cavity and Pharynx Cancer - MEN",
##   RR = function(x, beta) {exp(sum(beta * c(1, x, x^2, x^3)))},
##   betaCurrent = c(0, 0.0270986006898689, -0.0000918619672439482, 7.38478068923644*(10^-8)),
##   CovBetaCurrent = matrix(c(0,0,0,0,0,1.94786135584958*10^(-06),-1.69994463981214*10^(-08),3.3878103564092*10^(-11),0,-1.69994463981214*10^(-08),0.0000000001802 ,-3.87375712299595*10^(-13),0, 3.3878103564092*10^(-11),-3.87375712299595*10^(-13),8.65026664126274*10^(-16)),4,4),
##   lnRRFormer = log(1.21),
##   VarLnRRFormer =0.0465106^2)

calculateAAF <- function(data, disease, mc.cores = 1, ...)
{
  ## for parallel computing
  require("parallel")
  
  ## define function calculating the AAF per disease
  ## this is to be applied to each element of the disease argument
  ## definion is done here to avoid having to pass on the data argument formally (lexical scoping)
  calAAFdisease <- function(dis){
    
    ## risk of drinkers
    drkfun <- function(x, pabs, pform, nc, k, theta)
    {
      (1 - pabs - pform)/ nc * dgamma(x, shape = k, scale = theta) * dis$RRCurrent(x, beta = dis$betaCurrent)
    }
    
    ## integral was breaking for places with tiny amount of drinking (eg BGD, 70 year old women)
    ## we can do this rather conditionally
    if (mapply(function(shape, scale) 
    {
      integrate(dgamma, lower = 0.1, upper = 150, shape = shape, scale = scale)$value
    },
    shape = data$K, scale = data$THETA
    ) == 0) {
      maxint <- c()
      for (i in rev(1:1500)) {
        if (mapply(function(shape, scale) 
        {
          integrate(dgamma, lower = 0.1, upper = i, shape = shape, scale = scale)$value
        },
        shape = data$K, scale = data$THETA
        ) > 0) {
          maxint <- c(maxint,i/10)
        }  
      }
    } else{
      maxint <- 150
    }
    
    ## normalizing constant for gamma distribution
    normConst <- mapply(function(shape, scale) 
    {
      integrate(dgamma, lower = 0.1, upper = max(maxint), shape = shape, scale = scale)$value
    },
    shape = data$K, scale = data$THETA
    )
    
    if (!is.null(maxint)) {
      try(drk <- mapply(function(pabs, pform, nc, k, theta)
      {
        integrate(drkfun, lower = 0.1, upper = max(maxint), pabs = pabs, pform = pform, nc = nc,k = k, theta = theta)$value
      },
      pabs = data$LIFETIME_ABSTAINERS,pform = data$FORMER_DRINKERS, nc = normConst, k = data$K, theta = data$THETA
      ),silent=T)
      
      if (!exists("drk")) drk <- 1*(1-data$LIFETIME_ABSTAINERS-data$FORMER_DRINKERS)
      if (is.infinite(drk) | is.nan(drk) | is.na(drk)) drk <- 1*(1-data$LIFETIME_ABSTAINERS-data$FORMER_DRINKERS)
      
      
    } else {
      drk <- 1*(1-data$LIFETIME_ABSTAINERS-data$FORMER_DRINKERS)
    }
    
    ## something critically wrong- unless it's protective, we should be making sure drk is at least 1*prevalence of drinkers
    ## for very small amounts of consumption, this calculation can be quite broken.
    ## seems fair that if the density at .1 is basically 0, we can assume the drinker risk is approx
    ## 1*(1-pabs-pform)
    if (dgamma(.1,shape=data$K,scale=data$THETA) < .00000001) drk <- 1*(1-data$LIFETIME_ABSTAINERS-data$FORMER_DRINKERS)

    ## AAF
    aaf <- (data$LIFETIME_ABSTAINERS + data$FORMER_DRINKERS * exp(dis$lnRRFormer) +
            drk - 1) / (data$LIFETIME_ABSTAINERS +
            data$FORMER_DRINKERS * exp(dis$lnRRFormer) + drk)
    
    return(aaf)
  }

  ## run in parallel (on unix machines)
  aaf <- mclapply(disease, FUN = calAAFdisease, mc.cores = mc.cores)

  ## set up return object
  ret <- data.frame()
  for (i in 1:length(disease)) ret <- rbind(ret, data)
  ret$DISEASE <- rep(sapply(disease, function(x) x$disease), each = nrow(data))
  ret$AAF <- unlist(aaf)

  return(ret)
 }



###########################################################
#### This part will compute the confidence intervals   ####
#### using the funcions above on each set of generated ####
#### parameters.                                       ####
###########################################################
## calculation of the confidence intervals
## (parametric bootstrap)

## A) draw random samples of the following parameters:
## pca ~ N(pca^, var^(pca^))
##   both from input-file: PCA, VAR_PCA
##   if pca <= 0 then pca <- 0.001
##   transform: 0.8*pca_listlitresperyear*1000*0.789/365
## p_abs ~ N(p_abs^, sqrt(p_abs^ * (1-p_abs^) / n))
## p_form ~ N(p_form^, sqrt(p_form^ * (1-p_form^) /n))
##   both per age category! needed to sample mu (mean consumption)
##   both from input-file: LIFETIME_ABSTAINERS, FORMER_DRINKERS
##   n = 1000
##   check that p_abs + p_former <= 0, otherwise scale down (and keep 0.01 reserved for the drinkers)
## mu <- computeMean(pop(input), relcoef(input), p_abs(random), p_form(random), pca(random))
##   needs all but pca to be a vector of 3 (for 3 age categories)
## k ~ N(1/1.171^2, sqrt(4 * 0.012^2 / 1.171^6)) for men (other values for women)
## theta <- mu/k (both random)
## betasRR <- MultivN(betas, Cov(betas))
##   mvrnorm() from pkg MASS
##   beta, Cov(beta) from disease-list
## RR_form ~ exp( N(RR_form^, Var^(RR_form^)) )
##   both RR_form and its variance from the disease-list
## B) calculate AAF

confintAAF <- function(data, agefrac, disease, B, verbose = TRUE, mc.cores = 1,
                       gender = 1, age = 1, adjustPCA = 0.8, saveDraws=0)
{
  require("MASS")

  ## check if only one gender-age combination has been selected
  if (length(gender) > 1)
    {
      gender <- gender[1]
      warning("Only the first element of the gender argument is used.")
    }
  
  if (length(age) > 1)
    {
      age <- age[1]
      warning("Only the first element of the age argument is used.")
    }
  
  ## convert string input to numeric
  if(is.character(gender)) gender <- ifelse(gender == "male", 1, 2)
  
  ## take relevant gender subset,
  ## do not take age subset because mean of one age group is relative to the other groups, thus need all groups for calculation
  data <- subset(data, SEX == gender)
  
  ## drop unnecessary variables
  data <- subset(data, select = c(REGION, SEX, AGE_CATEGORY,
                        PCA, VAR_PCA, POPULATION, 
                        LIFETIME_ABSTAINERS, FORMER_DRINKERS,DRINKERS ))
  
  if (age < 34) agegrouping <- 1
  if (age > 34 & age < 59) agegrouping <- 2
  if (age > 59) agegrouping <- 3
  
  ## set up return object
  ret <- subset(data, AGE_CATEGORY == agegrouping, select = c(REGION, SEX, AGE_CATEGORY))
  ret <- data.frame(REGION = rep(ret$REGION, each = length(disease)),
                    SEX = rep(ret$SEX, each = length(disease)),
                    AGE_CATEGORY = rep(ret$AGE_CATEGORY, each = length(disease)),
                    DISEASE = rep(sapply(disease, function(x) x$disease),
                      times = nrow(ret)), AAF_PE = NA,AAF_MEAN=NA, SD = NA)

					  
  ## IHME changes - add "saveDraws" number of columns if we are saving draws
	if (saveDraws > 0) {
		temp <- data.frame(matrix(data=NA, nrow=nrow(ret), ncol=saveDraws))
		names(temp) <- paste("draw", 1:saveDraws, sep="")
		ret <- cbind(ret, temp)
	}

  ## work through region-gender groups
  regions <- unique(data$REGION)
  for (i in regions)
    {
      ## print status
      if(verbose)
      cat("Region:", i, "(", which(i == regions), "out of", length(regions), ")\n")
      regionaldata <- data[data$REGION == i,]
      regionalagefrac <- agefrac[agefrac$location_id == i,]

      ## sample pca (must be positive)
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
      

  
      ## calculate mean
      mu <- rep(NA, length.out = B)
      for(b in 1:B)
        {
          mu[b] <- computeMeanStratum(popsize = regionaldata$POPULATION,
                 age_fraction=regionalagefrac[,c("age","pop_scaled",paste0("draw_",b))],
                 pabs = pabs[b,], pformer = pform[b,], pca = pca[b],
                 adjustPCA = adjustPCA)
        }
      mu <- unlist(mu)
      mu[mu < 1] <- 1
    
      ## calculate corresponding parameters of the gamma distribution
      k <- if(gender == 1)
        {
          rnorm(B, mean = 1/1.171^2, sd = sqrt(4 * 0.012^2 / 1.171^6))
        } else 
        {
          rnorm(B, mean = 1/1.258^2, sd = sqrt(4 * 0.018^2 / 1.258^6))
        }
        
      theta <- mu / k


	  set.seed(1000)
      calAAFdis <- function(dis, saveDraws)
        {
          ## print status if argument "verbose" is TRUE
          if(verbose) cat("Region:", i, "; disease:", dis$disease, "\n")
          ## draw random sample of beta coefficients
          beta <- mvrnorm(B, mu = dis$betaCurrent, Sigma = dis$covBetaCurrent) # one set = one row

          ## draw random sample of log relative risk for former drinkers
          lnRR <- rnorm(B, mean = dis$lnRRFormer, sd = sqrt(dis$varLnRRFormer))

          ## calculate AAF
          aaf <- rep(NA, length.out = B)
          for (b in 1:B)
            {
              ## normalizing constant for gamma distribution
            normConst <- integrate(dgamma, lower = 0.1, upper = 150, shape = k[b],scale = theta[b])$value
            ## risk of drinkers

            ## integral was breaking for places with tiny amount of drinking (eg BGD, 70 year old women)
            ## we can do this rather conditionally
            if (integrate(dgamma, lower = 0.1, upper = 150, shape = k[b],scale = theta[b])$value == 0) {
              maxint <- c()
              for (i in rev(1:1500)) {
                if (integrate(dgamma, lower = 0.1, upper = 150, shape = k[b],scale = theta[b])$value > 0) {
                  maxint <- c(maxint,i/10)
                }  
              }
            } else{
              maxint <- 150
            }
            
            if (!is.null(maxint)) {
              try(drk <- integrate(function(x){
                (1 - pabs[b,agegrouping] - pform[b,agegrouping])/ normConst * dgamma(x, shape = k[b],scale = theta[b]) * dis$RRCurrent(x, beta = beta[b,])
              }, lower = 0.1, upper = 150)$value,silent=T)
              
              if (!exists("drk")) drk <- 1*(1-pabs[b,agegrouping]-pform[b,agegrouping])
              if (is.infinite(drk) | is.nan(drk) | is.na(drk)) drk <- 1*(1-pabs[b,agegrouping]-pform[b,agegrouping])
              
              
            } else {
              drk <- 1*(1-pabs[b,agegrouping]-pform[b,agegrouping])
            }
            
      
#             drk <- integrate(function(x){
#               (1 - pabs[b,agegrouping] - pform[b,agegrouping])/ normConst * dgamma(x, shape = k[b],scale = theta[b]) * dis$RRCurrent(x, beta = beta[b,])
#             }, lower = 0.1, upper = 150)$value
            
              ## something critically wrong- unless it's protective, we should be making sure drk is at least 1*prevalence of drinkers
              ## for very small amounts of consumption, this calculation can be quite broken.
              ## seems fair that if the density at .1 is basically 0, we can assume the drinker risk is approx
              ## 1*(1-pabs-pform)
              if (dgamma(.1,shape=k[b],scale=theta[b]) < .00000001) drk <- 1*(1-pabs[b,agegrouping]-pform[b,agegrouping])
              

          ## AAF
          aaf[b] <- (pabs[b,agegrouping] + pform[b,agegrouping] * exp(lnRR[b]) +
            drk - 1) / (pabs[b,agegrouping] + pform[b, agegrouping] * exp(lnRR[b]) + drk)
            }

          ## return mean and sd
          retour <- c(mean(aaf), sd(aaf))
          names(retour) <- c("mean", "sd")
		  
		  ## For IHME - save first "saveDraws" number of draws also
		  if (saveDraws > 0) {
			retour <- c(retour, aaf[1:saveDraws])
			names(retour) <- c("mean", "sd", paste("draw", 1:saveDraws, sep=""))
			}

          return(retour)
      }
      ## as the P.E. is not the mean of the AAF we will output both here (not the same due to exponential in RR)
      regionaldata=regionaldata[regionaldata$SEX==gender,]
      meanforPE=computeMean(regionaldata,regionalagefrac,age,gender)
      pointestimateAAF<-calculateAAF(data=meanforPE[meanforPE$age==age,] ,disease)$AAF
    aafConf <- mclapply(disease, calAAFdis, mc.cores = mc.cores, saveDraws = saveDraws)
    #names(aafConf) <- sapply(disease, function(x) x$disease)
    ret[ret$REGION == i, 6:(7 + saveDraws)] <- matrix(unlist(aafConf), ncol = 2 + saveDraws, byrow = TRUE)
    ret[ret$REGION == i, 5] <- pointestimateAAF
  }

  return(ret)
}
