###################################################################################
#### The program to compute the AAFs for chronic diseases and their confidence ####
#### intervals is split into 3 files. chronicRR.R contains all the relative    ####
#### risk functions, chronicAAF.R contains the definitions of all the          ####
#### functions and computational steps required to derive the AAFs and the CIs ####
#### chronicAnalysis.R defines the input file and output destination and runs  ####
#### the computations. This is the only file that needs to be run.             ####
###################################################################################

### AGE_1   PE_0.361367 			VAR_0.192781^2
### AGE_2   PE_0.043652			VAR_0.023287^2
### AGE_3   PE_-0.337606			VAR_0.180105^2

AGE_ADJ_PE 		<- c(0.361367, 0.043652, -0.337606)
AGE_ADJ_VAR 	<- c(0.192781^2, 0.023287^2, 0.180105^2)

## data for the various diseases, separatly for men and women
## information includes:
## disease: name of the disease
## RRCurrent: relative risk function for the (current) drinkers
## betaCurrent: coefficients for the RR function of (current) drinkers
## covBetaCurrent: covariance matrix for the beta coefficients of the (current) drinkers
## lnRRFormer: log relative risk of former drinkers
## varLnRRFormer: variance of log relative risk estimate of former drinkers


## THESE FUNCTIONS ARE STEP FUNCTIONS BASED ON ALCOHOL INTAKE AS MEASURED IN RUSSIAN BOTTLES ###
## THESE FUNCTIONS THUS EXPRESSED USING THE CONSTANTS DEFINED BELOW  ###

## TRANSFORMING BOTTLES INTO GRAMS ##

cons1= 25.360714285714285714285714285714  ### one bottle a week

cons2= 76.082142857142857142857142857143 ### three bottles a week



####### IHD #######
####### IHD #######

#### male ####

IHDmale = list (disease = "IHD Mortality", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),0),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale = list (disease = "IHD Mortality",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),0),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)







####### IHD 15 to 34 #######
####### IHD 15 to 34 #######

#### male ####

IHDmale_1 = list (disease = "IHD Mortality", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_1 = list (disease = "IHD Mortality",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)




####### IHD 35 to 64 #######
####### IHD 35 to 64 #######

#### male ####

IHDmale_2 = list (disease = "IHD Mortality", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_2 = list (disease = "IHD Mortality",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)




####### IHD 65 PLUS #######
####### IHD 65 PLUS #######

#### male ####

IHDmale_3 = list (disease = "IHD Mortality", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_3 = list (disease = "IHD Mortality",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4])*exp(beta[1]),ifelse(x<cons2,exp(beta[4])*exp(beta[2]),exp(beta[4])*exp(beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)



relativeriskmale = list(IHDmale_1,   IHDmale_2,  IHDmale_3)

relativeriskfemale = list(IHDfemale_1,  IHDfemale_2,   IHDfemale_3)


