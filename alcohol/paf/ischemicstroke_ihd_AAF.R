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
computeMean <- function(data, agefrac, age = NULL, gender = NULL, adjustPCA = 0.8)
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
  ret <- subset(data, select = c(REGION, SEX, AGE_CATEGORY,GROUP,
                                 #PCA, VAR_PCA, POPULATION, 
                                 LIFETIME_ABSTAINERS, FORMER_DRINKERS,BINGERS, BINGE_A,BINGE_TIMES,BINGE_TIMES_SE))
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
	af <- agefrac[agefrac$location_id == pat[1],]
   ret$MEAN[ret$REGION == pat[1] & ret$SEX == pat[2]] <- computeMeanStratum(
      popsize = dat$POPULATION, age_fraction=af[,c("age","pop_scaled","mean_frac")],
      pabs = dat$LIFETIME_ABSTAINERS, pformer = dat$FORMER_DRINKERS,
      pca = dat$PCA, adjustPCA = adjustPCA)
  }
  
  ret$MEAN <- unlist(ret$MEAN)
  
  ## in draws, we're making mean .1 if it's less than .1, diong now for point estimate too
  ret$MEAN[ret$MEAN < .1] <- .1
  
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

calculateAAF <- function(data, age_fraction,disease, age, mc.cores = 8,TestStatus="no",noisy, ...)
{
  ## for parallel computing
  if (age_fraction$age[1] < 34) agegroup <- 1
  if (age_fraction$age[1] > 34 & age_fraction$age[1] < 59) agegroup <- 2
  if (age_fraction$age[1] > 59) agegroup <- 3
  require("parallel")
  data <- subset(data, AGE_CATEGORY == agegroup)
  disease = disease
  #disease <- switch(age, disease[1], disease[2], disease[3])
  #deaths=subset(deaths, AGE==age)
  
  groups=unique(data$GROUP)
  groups=subset(groups,groups!="0") ## this removes the "0" which are the sub-populations to be ignored.
  ngroups=length(groups)
  
  ## for parallel computing
  require("parallel")
  
  ## set up return object
  ret <- data.frame()
  for (i in 1:ngroups) ret<-rbind(ret,data.frame(rep(groups[i],length(disease))))
  colnames(ret)="GROUP"
  ret$DISEASE <- rep(sapply(disease, function(x) x$disease), times = ngroups)
  groupcounter=0
  
  for (i in groups)
  {

    groupcounter=groupcounter+1
    if (noisy == T) {
      cat(paste(groupcounter," running of ",length(groups)," this is ",data$REGION[data$GROUP==i], "\n")); flush.console()
    }
    datagroup=subset(data,GROUP==i)
    #deathsgroup=subset(deaths,GROUP==i)
    
    ## calculate quantities not specific to the disease
    pcurrent <- (1 - datagroup$LIFETIME_ABSTAINERS - datagroup$FORMER_DRINKERS)
    
    ## define function calculating the AAF per disease
    ## this is to be applied to each element of the disease argument
    ## definion is done here to avoid having to pass on the data argument formally (lexical scoping)
    calAAFdisease <- function(dis){
      print(dis$disease)
      ## this will add the number of deaths for a given disease in the data.frame
      ## so that the order in the deaths input file and the prevalence input file
      ## doesn't have to match. 
      
      datagroupdis=datagroup
      datagroupdis$DISEASE=rep(dis$disease, times = length(datagroupdis[,1]))
      #don't need to combine aaf for groups, don't need deaths
      #datagroupdis$DEATHS=rep(NA,length(datagroupdis[,1]))
      #for (j in 1:length(datagroupdis[,1]))
      #{
      #  datagroupdis$DEATHS[j]=subset(deathsgroup,(REGION==datagroupdis[j,]$REGION) & (AGE==datagroupdis[j,]$AGE_CATEGORY) &  (DISEASE==dis$disease))$DEATHS
      #}
      
      ## finding the 1 crossing of RR(x)
      crossing=uniroot(function(x){dis$RRCurrent(x,dis$betaCurrent)-1},interval=c(1,150))$root
      
      ## normalizing constant for gamma distribution
      normConstAll <- mapply(function(shape, scale) 
      {
        integrate(dgamma, lower = 0, upper = 150, shape = shape, scale = scale, stop.on.error=FALSE)$value
      },
      shape = datagroupdis$K, scale = datagroupdis$THETA)
      
      ## mostly non-bingers (0 - BINGE_A)
      normConstNB <- mapply(function(shape, scale) 
      {
        integrate(dgamma, lower = 0, upper = datagroupdis$BINGE_A, shape = shape, scale = scale,stop.on.error=FALSE)$value},
      shape = datagroupdis$K, scale = datagroupdis$THETA)
      ## bingers (BINGE_A - 150g)
      normConstB <- mapply(function(shape, scale) 
      {
        integrate(dgamma, lower = datagroupdis$BINGE_A, upper = 150, shape = shape, scale = scale,stop.on.error=FALSE)$value
      },shape = datagroupdis$K, scale = datagroupdis$THETA)
      
      ## Normalizing the distributions 
      Above_BI <- (normConstB / normConstAll) * pcurrent
      Below_BI <- (normConstNB / normConstAll) * pcurrent
      
      ## if low enough consumption, normConst can be 0, replace if that's the case
      if (normConstAll == 0) Above_BI <- 0
      if (normConstAll == 0) Below_BI <- pcurrent
      
      ## proportion of bingers in the entire population
      Bingers_total <- datagroupdis$BINGERS * pcurrent

      ## represents total among 0to60 that are bingers (as a proportion of the total population)
      ## for women this same variable represents the total among 0to48 but the variable name
      ## remains unchanged
      Bingers_in_0toThres <- Bingers_total - Above_BI
      
     
      Bingers_in_0toThres <- Bingers_in_0toThres*datagroupdis$BINGE_TIMES
      
      ## The drinkers in the 0 to 60 group that aren't bingers are going to be
      ## considered in their gamma function. This represents the fraction of 
      ## the gamma distribution that are all non-bingers.
      
      non_bingersprop <- (Below_BI - Bingers_in_0toThres) / Below_BI
      
      
      if(TestStatus=="yes")
      {
        ## This test will quit the program and give an error message if the 
        ## proportion of bingers among drinkers is smaller than the prevalence of
        ## drinking 60+ among drinkers. 
        
        for(w in 1:length(Above_BI))
        {
          if(Bingers_total[w]<Above_BI[w])
          {
            warning(paste("The prevalence of bingers among drinkers for Region: ", datagroupdis$REGION[w],
                          ", agegroup ",datagroupdis$AGE[w],", gender: ", datagroupdis$SEX[w],
                          " is not coherent with exposure data (there are fewer bingers than people that drink 60g/day or more on average)"))
            stop()   ## SHOULD USE TEST STATUS NO- NOW WE ARE REPLACING BINGERS WITH % WHO DRINK > 60g/day IF LARGER
           ## THIS WAS MADE NECESSARY BECAUSE WE ARE USING OUR OWN CONSUMPTION AND JUERGEN'S BINGERS
          }
        }
      }
      
      if(TestStatus=="no")
      {
        for(w in 1:length(Above_BI))
        {
          if(Above_BI[w]>Bingers_total[w])
          {
            Bingers_total[w]=Above_BI[w]
            non_bingersprop[w]=1
            Bingers_in_0toThres[w]=0
          }
        }
      }
      

      

      
      
      if(crossing<datagroupdis$BINGE_A[1]){
        
        ##bingers above BINGE_A simply have the normal RR
        
        bingeAboveThresfun=function(x, pabs, pform, nc, k, theta)
        {
          (1 - pabs - pform) / nc * dgamma(x, shape = k, scale = theta) * dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        bingeAboveThres=mapply(function(pabs, pform, nc, k, theta)
        {
          integrate(bingeAboveThresfun, lower = datagroupdis$BINGE_A, upper = 150, pabs = pabs, pform = pform,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, pabs = datagroupdis$LIFETIME_ABSTAINERS, pform = datagroupdis$FORMER_DRINKERS,nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ##non-bingers also keep the unmodified RR
        
        non_bingersfunc=function(x, pabs, pform, nb, nc, k, theta)
        {
          (1 - pabs - pform) / nc * nb * dgamma(x, shape = k, scale = theta) * dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        non_bingers=mapply(function(pabs, pform, nb, nc, k, theta)
        {
          integrate(non_bingersfunc, lower = 0, upper = datagroupdis$BINGE_A, pabs = pabs, pform = pform, nb=nb,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, pabs = datagroupdis$LIFETIME_ABSTAINERS, pform = datagroupdis$FORMER_DRINKERS, nb=non_bingersprop, nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ## bingers below BINGE_A but above the crossing also keep the unmodified RR
        
        bingers_above_crossingfunc=function(x,bingers_below_BINGE_A, nc, k, theta)
        {
          1 / nc * bingers_below_BINGE_A * dgamma(x, shape = k, scale = theta) *
            dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        bingers_above_crossing=mapply(function(bingers_below_BINGE_A, nc, k, theta)
        {
          integrate(bingers_above_crossingfunc, lower = crossing, upper = datagroupdis$BINGE_A, bingers_below_BINGE_A=bingers_below_BINGE_A,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, bingers_below_BINGE_A=Bingers_in_0toThres,
        nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ## bingers below the crossing will have an RR set to 1
        
        bingers_below_crossingfunc=function(x,bingers_below_BINGE_A, nc, k, theta)
        {
          1 / nc * bingers_below_BINGE_A * dgamma(x, shape = k, scale = theta)
        }
        
        bingers_below_crossing=mapply(function(bingers_below_BINGE_A, nc, k, theta){
          integrate(bingers_below_crossingfunc, lower = 0, upper = crossing, bingers_below_BINGE_A=bingers_below_BINGE_A,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, bingers_below_BINGE_A=Bingers_in_0toThres,
        nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ## AAF
        aafall <- (datagroupdis$LIFETIME_ABSTAINERS + datagroupdis$FORMER_DRINKERS * exp(dis$lnRRFormer) +
                     bingeAboveThres + non_bingers +bingers_above_crossing +bingers_below_crossing - 1) / (datagroupdis$LIFETIME_ABSTAINERS +
                                                                                                             datagroupdis$FORMER_DRINKERS * exp(dis$lnRRFormer) +  bingeAboveThres + non_bingers +bingers_above_crossing +bingers_below_crossing)
        
      }##if(crossing<data$BINGE_A[1])
      
      
      
      if(crossing>datagroupdis$BINGE_A[1]){
        
        ## the bingers that are above BINGE_A and above crossing will have an unchanged RR
        
        bingers_above_crossingfunc=function(x, pabs, pform, nc, k, theta){
          (1 - pabs - pform) / nc * dgamma(x, shape = k, scale = theta) *
            dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        bingers_above_crossing=mapply(function(pabs, pform, nc, k, theta){
          integrate(bingers_above_crossingfunc, lower = crossing, upper = 150, pabs = pabs, pform = pform,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, pabs = datagroupdis$LIFETIME_ABSTAINERS, pform = datagroupdis$FORMER_DRINKERS, 
        nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ## the bingers above BINGE_A but below the crossing will receive an RR of 1
        
        bingers_betweenfunc=function(x, pabs, pform, nc, k, theta){
          (1 - pabs - pform) / nc * dgamma(x, shape = k, scale = theta) *
            dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        bingers_between=mapply(function(pabs, pform, nc, k, theta){
          integrate(bingers_betweenfunc, lower = datagroupdis$BINGE_A, upper = crossing, pabs = pabs, pform = pform,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, pabs = datagroupdis$LIFETIME_ABSTAINERS, pform = datagroupdis$FORMER_DRINKERS, 
        nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        
        ## the bingers below BINGE_A also receive an RR of 1 and therefore simply correspond
        ## to the value Bingers_in_0toThres
        
        ## finally, the non-bingers simply keep their usual RR   
        
        non_bingersfunc=function(x, pabs, pform, nb, nc, k, theta){
          (1 - pabs - pform) / nc * nb * dgamma(x, shape = k, scale = theta) *
            dis$RRCurrent(x, beta = dis$betaCurrent)
        }
        
        non_bingers=mapply(function(pabs, pform, nb, nc, k, theta){
          integrate(non_bingersfunc, lower = 0, upper = datagroupdis$BINGE_A, pabs = pabs, pform = pform, nb=nb,
                    nc = nc, k = k, theta = theta,stop.on.error=FALSE)$value
        }, pabs = datagroupdis$LIFETIME_ABSTAINERS, pform = datagroupdis$FORMER_DRINKERS, nb=non_bingersprop,
        nc = normConstAll, k = datagroupdis$K, theta = datagroupdis$THETA)
        
        ## AAF
        aafall <- (datagroupdis$LIFETIME_ABSTAINERS + datagroupdis$FORMER_DRINKERS * exp(dis$lnRRFormer) +bingers_above_crossing +bingers_between+Bingers_in_0toThres+non_bingers-1) /
          (datagroupdis$LIFETIME_ABSTAINERS + datagroupdis$FORMER_DRINKERS * exp(dis$lnRRFormer) + bingers_above_crossing +bingers_between+Bingers_in_0toThres+non_bingers )
        
        
      } ##if(crossing>data$BINGE_A[1])
      ## combined AAF for the group  - we're not doing this...
      ##aafgroup=sum(aafall*datagroupdis$DEATHS)/sum(datagroupdis$DEATHS)
      aafgroup=aafall
      return(aafgroup)
      
    } ##calAAFdisease <- function(dis)
    
    
    ## run in parallel (on unix machines)
    aaf <- mclapply(disease, calAAFdisease, mc.cores=mc.cores)
    
    ret$AAF[(length(disease)*(groupcounter-1)+1):(length(disease)*groupcounter)] = unlist(aaf)
    
  }# for each group
  return (ret)
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

confintAAF <- function(data, agefrac, disease, B, verbose = TRUE, mc.cores = 8, gender = 1, age = 1, adjustPCA = 0.8,TestStatus, saveDraws=0,mortmorb=1)
{
  require("MASS")
  require("parallel")
  
  if (agefrac$age[1] < 34) agegroup <- 1
  if (agefrac$age[1] > 34 & agefrac$age[1] < 59) agegroup <- 2
  if (agefrac$age[1] > 59) agegroup <- 3
  
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
  diseasecopy=disease
  
  ## take relevant gender subset,
  ## do not take age subset because mean of one age group is relative to the other groups, thus need all groups for calculation
  data <- subset(data, SEX == gender)
  
  disease <- switch(agegroup, disease[1:2], disease[3:4], disease[5:6])
  
  ## drop unnecessary variables
  data <- subset(data, select = c(REGION, SEX, AGE_CATEGORY, GROUP,
                                  PCA, VAR_PCA, POPULATION,
                                  BINGERS, BINGERS_SE,BINGE_TIMES, BINGE_TIMES_SE,
                                  LIFETIME_ABSTAINERS, FORMER_DRINKERS,BINGE_A))
  
  #groups=unique(data$GROUP)
  #groups=subset(groups,groups!="0") ## this removes the "0" which are the sub-populations to be ignored.
  #ngroups=length(groups)
  
  ##note: all age groups are still needed to compute the mean alcohol consumption
  ## so in this case, the regions in the groups are selected, then the mean values
  ## computed and the AAFs sampled only for the subpopulations contained in the groups
  ## this of course happens for each group. This did not have to be made in the PE 
  ## calculation because this step is taken care of by another function!
  
  ## set up return object
  #ret <- data.frame()
  #for (i in 1:ngroups) ret<-rbind(ret,data.frame(rep(groups[i],length(disease))))
  #colnames(ret)="GROUP"
  #ret$DISEASE <- rep(sapply(disease, function(x) x$disease), times = ngroups)
  #ret$AAF_PE=NA
  #ret$AAF_MEAN=NA
  #ret$AAF_SD=NA
  
  ## set up return object
  ret <- subset(data, AGE_CATEGORY == agegroup, select = c(REGION, SEX, AGE_CATEGORY))
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
  
  
  #cores<-makeCluster(mc.cores)
  #registerDoParallel(cores)
  
  #foreachoutput<-foreach(g=1:length(groups),.export=c("computeMeanStratum","computeMean","calculateAAF","mvrnorm"),.combine='rbind') %dopar%
  #{
   #u=groups[g]
    #here, the regions within the groups are extracted
    #regionsgroup=unique(subset(data,GROUP==u)$REGION)
    #deathsgroup=subset(deaths,GROUP==u)
    
    ## work through region-gender groups
    regions <- unique(data$REGION)
    
    ## regionssamples will contain all the samples of the regions in the group. It will later 
    ## be subsetted to only include the sub-populations in the groups (this is for example
    ## if only 1 or a subset of the age categories are evaluated).
    ## We are not subsetting using the GROUP variable anymore, but using the REGION values
    ## contained in each group. This therefore only works as long as each REGION can
    #allregionssamples=subset(data,(REGION %in% regions) & (AGE_CATEGORY==age), select=c(REGION,SEX,AGE_CATEGORY,GROUP,BINGE_A))
    #allregionssamples=data.frame(REGION = rep(allregionssamples$REGION,each = B),
    #                             SEX = rep(allregionssamples$SEX,each = B),
    #                             AGE_CATEGORY = rep(allregionssamples$AGE_CATEGORY, each=B),
    #                             GROUP = rep(allregionssamples$GROUP, each = B),
    #                             BINGE_A = rep(allregionssamples$BINGE_A, each=B),
    #                             PABS=NA,PFORM=NA,MU=NA, K=NA,THETA=NA,BINGERS=NA, NON_BINGERS=NA, BINGERS_0TOTHRES=NA)
    #allregionssamples$SAMPLE=rep(1:B,times=length(regions))
    
    
    for (i in regions)
    {
      ## print status
      if(verbose)
        cat("Region:", i, "(", which(i == regions), "out of", length(regions), ")\n")
      regionaldata <- data[data$REGION == i,]
	  regionalagefrac <- agefrac[agefrac$location_id == i,]
      
      ## sample pca (must be positive)
      pca <- rnorm(B, mean = regionaldata$PCA[1], sd = sqrt(regionaldata$VAR_PCA[1]))
      pca[pca <= 0] <- 0.001
      
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
      
      ## check proportions for validity (in each age category)
      ## the proportion of drinkers needs to be >= 1%
      ## so if pabs + pform >= 0.99, they are scaled down accrodingly
      tsum1 <- pabs1 + pform1
      pabs1[tsum1 >= 0.99] <- (pabs1 / tsum1*0.99)[tsum1 >= 0.99]
      pform1[tsum1 >= 0.99] <- (pform1 / tsum1*0.99)[tsum1 >= 0.99]
      tsum2 <- pabs2 + pform2
      pabs2[tsum2 >= 0.99] <- (pabs2 / tsum2*0.99)[tsum2 >= 0.99]
      pform2[tsum2 >= 0.99] <- (pform2 / tsum2*0.99)[tsum2 >= 0.99]
      tsum3 <- pabs3 + pform3
      pabs3[tsum3 >= 0.99] <- (pabs3 / tsum3*0.99)[tsum3 >= 0.99]
      pform3[tsum3 >= 0.99] <- (pform3 / tsum3*0.99)[tsum3 >= 0.99]
      
      ## combine proportions
      pabs <- cbind(pabs1, pabs2, pabs3)
      pform <- cbind(pform1, pform2, pform3)
      
      #allregionssamples[allregionssamples$REGION==i,]$PABS=pabs[,age]
      #allregionssamples[allregionssamples$REGION==i,]$PFORM=pform[,age]
      
      ## proportion of current drinkers
      pcurrent <- 1 - pabs[,agegroup] - pform[,agegroup]
      
      ## sample proportion of bingers
	  ## bingers is in proportion of drinkers that's bingers, then we get out of total people
      bingers <- rnorm(B, mean = regionaldata$BINGERS[agegroup], sd = regionaldata$BINGERS_SE[agegroup])
      bingers[bingers < 0.001] <- 0.001
      ## now converting to percent of total people
      bingers <- bingers * pcurrent
    
	    ## sample binge frequency
	    binge_times <- rnorm(B, mean=regionaldata$BINGE_TIMES[agegroup],sd=regionaldata$BINGE_TIMES_SE[agegroup])
	    binge_times[binge_times < 0.001] <- 0.001
      
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
      mu[mu < 0.1] <- 0.1
      
      #allregionssamples[allregionssamples$REGION==i,]$MU=mu
      
      ## calculate corresponding parameters of the gamma distribution
      k <- if(gender == 1)
      {
        rnorm(B, mean = 1/1.171^2, sd = sqrt(4 * 0.012^2 / 1.171^6))
      } else 
      {
        rnorm(B, mean = 1/1.258^2, sd = sqrt(4 * 0.018^2 / 1.258^6))
      }
      
      #allregionssamples[allregionssamples$REGION==i,]$K=k
      
      theta <- mu / k
      
      #allregionssamples[allregionssamples$REGION==i,]$THETA=theta
      

      normConst <- mapply(function(shape, scale) {
        integrate(dgamma, lower = 0, upper = 150, shape = shape, scale = scale,stop.on.error=FALSE)$value},
        shape = k, scale = theta)
      ## mainly non-bingers (0 - 60g)
      normConstNB <- mapply(function(shape, scale) {
        integrate(dgamma, lower = 0, upper = regionaldata$BINGE_A[agegroup], shape = shape, scale = scale,stop.on.error=FALSE)$value},
        shape = k, scale = theta)
      ## bingers (60 - 150g)
      normConstB <- mapply(function(shape, scale) {
        integrate(dgamma, lower = regionaldata$BINGE_A[agegroup], upper = 150, shape = shape, scale = scale,stop.on.error=FALSE)$value},
        shape = k, scale = theta)
      
      ## Normalizing the distributions 
      Above_BI <- (normConstB / normConst) * pcurrent
      Below_BI <- (normConstNB / normConst) * pcurrent
      
      ## if low enough consumption, normConst can be 0, replace if that's the case
      Above_BI[normConst == 0] <- 0
      Below_BI[normConst == 0] <- pcurrent
      
      
      ## proportion of bingers in the entire population
      Bingers_total <- bingers
      

      ## represents total among 0to threshold that are bingers (as a proportion of the total population)
      Bingers_in_0toThres <- Bingers_total - Above_BI
    
  
  		Bingers_in_0toThres <- Bingers_in_0toThres*binge_times
        
      ## The drinkers in the 0 to 60 group that aren't bingers are going to be
      ## considered in their gamma function.
      ## this one has to be normalised to take into account the bingers
      ## (that will have a RR of 1)
      
      Non_bingers <- (Below_BI - Bingers_in_0toThres) / Below_BI
      
      ## for some countries with very small tail, the simulated percent of bingers
      ## might become smaller than the integral of the tail. In this case, the 
      ## value needs to be adjusted. 
      for(w in 1:length(Above_BI))
      {
        if(Above_BI[w]>Bingers_total[w])
        {
          bingers[w]=Above_BI[w]
          Non_bingers[w]=1
          Bingers_in_0toThres[w]=0
        }
      }
      #allregionssamples[allregionssamples$REGION==i,]$BINGERS <- bingers
      #allregionssamples[allregionssamples$REGION==i,]$NON_BINGERS = non_bingers
      #allregionssamples[allregionssamples$REGION==i,]$BINGERS_0TOTHRES = Bingers_in_0toThres
      
    #} # for (i in regions)
    
    
    calAAFdis <- function(dis,saveDraws)
    {
      ## print status if argument "verbose" is TRUE
      if(verbose) cat("Region:", i, "; disease:", dis$disease, "\n")
      
      ## now to copy the deaths information in the data.frame
      #allregionssamplesdis=allregionssamples
      #allregionssamplesdis$DISEASE=rep(dis$disease, times = length(allregionssamplesdis[,1]))
      #allregionssamplesdis$DEATHS=rep(NA,length(allregionssamplesdis[,1]))
      #number of sub-populations
      #nsubpops=length(allregionssamplesdis[,1])/B
      #for (j in 1:nsubpops) 
      #{
      #  if(verbose)
      #  {
      #    cat("searching deaths ", j, " out of ", nsubpops,"\n")
      #  }
      #  allregionssamplesdis$DEATHS[((j-1)*B+1):(j*B)]=subset(deathsgroup,(REGION==allregionssamplesdis[(j-1)*B+1,]$REGION) & (AGE==allregionssamplesdis[(j-1)*B+1,]$AGE_CATEGORY) &  (DISEASE==dis$disease))$DEATHS
      #}
      
      
      ## draw random sample of beta coefficients
      beta <- mvrnorm(B, mu = dis$betaCurrent, Sigma = dis$covBetaCurrent) # one set = one row
      
      ## draw random sample of log relative risk for former drinkers
      lnRR <- rnorm(B, mean = dis$lnRRFormer, sd = sqrt(dis$varLnRRFormer))
      
      ## if the value of RR at 1 is not smaller than 1-1, then there cannot be a 0 crossing, in this case, set crossing to 0
      ## which will cause the program to simply integrate all normally not caring about bingers.
      ## ischemic stroke and IHD have different numbers of betas
      
      if (ccc == "ihd") {
        crossing= mapply(function(b1,b2,b3,b4,b5) {
          a <- try(ifelse(dis$RRCurrent(1, beta = c(b1,b2,b3,b4,b5))<1,
                          uniroot(function(x){dis$RRCurrent(x, beta = c(b1,b2,b3,b4,b5))-1},interval=c(1,150),extendInt="upX")$root,
                          0),silent=T)
          ## if it doesn't work, then we'll replace
          if (!exists("a")) a <- 0
          return(a)
          
        },
        b1=beta[,1],b2=beta[,2],b3=beta[,3],b4=beta[,4],b5=beta[,5])      
      }
      if (ccc == "ischemicstroke") {
        crossing= mapply(function(b1,b2,b3,b4) {
          a <- try(ifelse(dis$RRCurrent(1, beta = c(b1,b2,b3,b4))<1,
                          uniroot(function(x){dis$RRCurrent(x, beta = c(b1,b2,b3,b4))-1},interval=c(1,150),extendInt="upX")$root,
                          0),silent=T)
          ## if it doesn't work, then we'll replace
          if (!exists("a")) a <- 0
          return(a)
          
        },
        b1=beta[,1],b2=beta[,2],b3=beta[,3],b4=beta[,4])         
      }
          
      ## calculate AAF
      aaf <- rep(NA, length.out = B)
      for (b in 1:B)
      {
        if(verbose) cat("AAF iteration: ",b, " out of", B, "for disease ", dis$disease,"\n")
        #allregionssampleB=subset(allregionssamplesdis,SAMPLE==b)
        ## The AAF has to be computed for each sub-population in the group and merged with the death count. 
        ## and that needs to be done for each sample. 
        #allregionssampleB$AAF=NA
        
        #for (r in 1:length(allregionssampleB$REGION))
        #{
          normConst <- integrate(dgamma, lower = 0, upper = 150, shape = k[b],scale = theta[b],stop.on.error=FALSE)$value
          
          if(crossing[b]==0){
            
            ## risk of drinkers
            drk <- integrate(function(x){
              (1 - pabs[b,agegroup] - pform[b,agegroup])/ normConst * dgamma(x, shape = k[b],scale = theta[b]) * dis$RRCurrent(x, beta = beta[b,])
            }, lower = 0, upper = 150,stop.on.error=FALSE)$value
            
            ## AAF
            aaf[b] <- (pabs[b,agegroup] + pform[b,agegroup] * exp(lnRR[b]) +
                         drk - 1) / (pabs[b,agegroup] + pform[b,agegroup] * exp(lnRR[b]) + drk)
          }
          
          if(0<crossing[b] && crossing[b]<regionaldata$BINGE_A[agegroup]){
            
            ##bingers above BINGE_A simply have the normal RR
            
            bingeAboveThres=integrate(function(x){
              (1 - pabs[b,agegroup] - pform[b,agegroup]) / normConst * dgamma(x, shape = k[b], scale = theta[b]) *
                dis$RRCurrent(x, beta = beta[b,])}, lower = regionaldata$BINGE_A[agegroup], upper = 150, stop.on.error=FALSE)$value
            
            
            ##non-bingers also keep the unmodified RR
            
            non_bingers=integrate(function(x){(1 - pabs[b,agegroup] - pform[b,agegroup]) / normConst * Non_bingers[b] * dgamma(x, shape = k[b], scale = theta[b]) *
                                                dis$RRCurrent(x, beta = beta[b,])}, lower = 0, upper = regionaldata$BINGE_A[agegroup],stop.on.error=FALSE)$value
            
            
            ## bingers below BINGE_A but above the crossing also keep the unmodified RR
            
            bingers_above_crossing=integrate(function(x){
              1 / normConst * Bingers_in_0toThres[b] * dgamma(x, shape = k[b], scale = theta[b]) *
                dis$RRCurrent(x, beta = beta[b,])}, lower = crossing[b], upper = regionaldata$BINGE_A[agegroup],stop.on.error=FALSE)$value
            
            
            ## bingers below the crossing will have an RR set to 1
            
            bingers_below_crossing=integrate(function(x){1 / normConst * Bingers_in_0toThres[b] * dgamma(x, shape = k[b], scale = theta[b])
            }, lower = 0, upper = crossing[b], stop.on.error=FALSE)$value        
            
            ## AAF
            aaf[b] <- (pabs[b,agegroup] + pform[b,agegroup] * exp(lnRR[b]) +
                         bingeAboveThres + non_bingers +bingers_above_crossing +bingers_below_crossing - 1) / (pabs[b,agegroup] +
                         pform[b,agegroup] * exp(lnRR[b]) +  bingeAboveThres + non_bingers +bingers_above_crossing +bingers_below_crossing)

          }##if(crossing<data$BINGE_A[1])
          
          
          if(crossing[b]>regionaldata$BINGE_A[agegroup]){
            
            ## the bingers that are above BINGE_A and above crossing will have an unchanged RR
            
            bingers_above_crossing=integrate(function(x){(1 - pabs[b,agegroup] - pform[b,agegroup]) / normConst* dgamma(x, shape = k[b], scale = theta[b]) *
                                                           dis$RRCurrent(x, beta = beta[b,])}, lower = crossing[b], upper = 150,stop.on.error=FALSE)$value
            
            
            ## the bingers above BINGE_A but below the crossing will receive an RR of 1
            
            bingers_between=integrate(function(x){(1 - pabs[b,agegroup] - pform[b,agegroup]) / normConst * dgamma(x, shape = k[b], scale = theta[b])}, lower = regionaldata$BINGE_A[agegroup], upper = crossing[b],stop.on.error=FALSE)$value
            
            
            ## the bingers below BINGE_A also receive an RR of 1 and therefore simply correspond
            ## to the value Bingers_in_0toThres
            
            ## finally, the non-bingers simply keep their usual RR   
            
            non_bingers=integrate(function(x){(1 - pabs[b,agegroup] - pform[b,agegroup]) / normConst * Non_bingers[b] * dgamma(x, shape = k[b], scale = theta[b]) *
                                                dis$RRCurrent(x, beta = beta[b,])}, lower = 0, upper = regionaldata$BINGE_A[agegroup],stop.on.error=FALSE)$value
            
            ## AAF
            aaf[b] <- (pabs[b,agegroup] + pform[b,agegroup] * exp(lnRR[b]) +bingers_above_crossing +bingers_between+Bingers_in_0toThres[b]+non_bingers-1) /
              (pabs[b,agegroup] + pform[b,agegroup] * exp(lnRR[b]) + bingers_above_crossing +bingers_between+Bingers_in_0toThres[b]+non_bingers )
            
            
          } ##if(crossing>data$BINGE_A[1])
          
        #} #for (r in 1:length(allregionssampleB$REGION))
        
        #aaf[b]=sum(allregionssampleB$AAF*allregionssampleB$DEATHS)/sum(allregionssampleB$DEATHS)
      }#for b in 1:B
      
      ## return mean and sd
      retour <- c(mean(aaf), sd(aaf))
      names(retour) <- c("mean", "sd")
        if (saveDraws > 0) {
		  retour <- c(retour, aaf[1:saveDraws])
	   	names(retour) <- c("mean", "sd", paste("draw", 1:saveDraws, sep=""))
	   	}
      return(retour)
    }#calAAFdis
    
    ## as the P.E. is not the mean of the AAF we will output both here (not the same due to exponential in RR)
	aafConf <- mclapply(disease,calAAFdis,saveDraws=saveDraws,mc.cores=mc.cores)
	
    #pointestimateAAF<-calculateAAF(means,disease=diseasecopy, deaths=deaths, age=age,TestStatus=TestStatus)$AAF
   # aafConf <- lapply(disease, calAAFdis)
   # This is what will get output by the foreach statement at each iteration
   #output<-matrix(c(pointestimateAAF,unlist(aafConf)), ncol = 3, byrow = TRUE)
    #names(aafConf) <- sapply(disease, function(x) x$disease)
	ret[ret$REGION == i, 6:(7 + saveDraws)] <- matrix(unlist(aafConf), ncol = 2 + saveDraws, byrow = TRUE)
  } # for (i in regions)  
  #}#  foreach (u in groups)
  #stopCluster(cores)
    meanforPE=computeMean(data=data,gender=gender,agefrac=agefrac,age=age)
    means=meanforPE
  pointestimateAAF<-calculateAAF(data=means[means$age==age,],age_fraction=agefrac,disease=disease, age=age,mc.cores=mc.cores,TestStatus=TestStatus,noisy=T)$AAF
  ret[,5] <- pointestimateAAF
  ret$age <- age
  
  return(ret)
  
} #confintAAF
