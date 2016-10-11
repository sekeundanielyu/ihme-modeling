
########################################################################################
#### The program to compute the AAFs for chronic diseases and their confidence 	    ####
#### intervals is split into 3 files. chronicRR_RUSSIA.R contains all the relative  ####
#### risk functions, chronicAAF.R contains the definitions of all the               ####
#### functions and computational steps required to derive the AAFs and the CIs      ####
#### chronicAnalysis.R defines the input file and output destination and runs       ####
#### the computations. This is the only file that needs to be run.                  ####
########################################################################################


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

cons1=25.360714285714285714285714285714  ### one bottle a week

cons2= 76.082142857142857142857142857143 ### three bottles a week

####### Pancreatitis #######
####### Pancreatitis #######

#### male ####

pancreatitismale = list(disease = "Pancreatitis - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.43),log(2.07),log(6.69),0),
covBetaCurrent = matrix (c(0.162^2,0,0,0,0,0.154^2,0,0,0,0,0.151^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####

pancreatitisfemale = list(disease = "Pancreatitis - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.09),log(5.01),log(19.26),0),
covBetaCurrent = matrix (c(0.225^2,0,0,0,0,0.19^2,0,0,0,0,0.176^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)

####### Lower Respiratory Infections ########
####### Lower Respiratory Infections ########


#### male ####

lowerrespmale = list(disease = "Lower Respiratory Infections - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent =  c(log(0.95),log(1.92),log(3.29),0),
covBetaCurrent = matrix (c(0.075^2,0,0,0,0,0.121^2,0,0,0,0,0.129^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####


lowerrespfemale = list(disease = "Lower Respiratory Infections - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.10),log(3.21),log(3.42),0),
covBetaCurrent = matrix (c(0.096^2,0,0,0,0,0.115^2,0,0,0,0,0.132^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)

####### Stroke ##########
####### Stroke ##########

#### male ####

strokemale = list(disease = "Stroke - MEN",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),0),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

strokefemale = list(disease = "Stroke - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),0),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)



####### Tuberculosis #######
####### Tuberculosis #######

#### male ####

tuberculosismale = list(disease = "Tuberculosis - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.01),log(1.97),log(4.14),0),
covBetaCurrent = matrix (c(0.1^2,0,0,0,0,0.094^2,0,0,0,0,0.095^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####

tuberculosisfemale = list (disease = "Tuberculosis - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(0.93),log(4.06),log(5.32),0),
covBetaCurrent = matrix (c(0.191^2,0,0,0,0,0.160^2,0,0,0,0,0.185^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)


####### Liver Cirrhosis #######
####### Liver Cirrhosis #######

#### male ####

livercirrhosismale = list (disease = "Liver Cirrhosis - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(0.92),log(1.77),log(6.21),0),
covBetaCurrent = matrix (c(0.097^2,0,0,0,0,0.095^2,0,0,0,0,0.095^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.31),
varLnRRFormer = 0.343816^2)

#### female ####

livercirrhosisfemale = list (disease = "Liver Cirrhosis - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.50),log(7.07),log(12.08),0),
covBetaCurrent = matrix (c(0.091^2,0,0,0,0,0.095^2,0,0,0,0,0.105^2,0,0,0,0,0),4,4),
lnRRFormer = log(6.5),
varLnRRFormer = 0.54991^2)


####### IHD #######
####### IHD #######

#### male ####

IHDmale = list (disease = "IHD - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),0),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.31),
varLnRRFormer = 0.343816^2)

#### female ####


IHDfemale = list (disease = "IHD - WOMEN",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),0),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,0),4,4),
lnRRFormer = log(6.5),
varLnRRFormer = 0.54991^2)

############# Transport Accidents ##############
############# Transport Accidents ##############
############# Transport Accidents ##############

#### male ####

transportaccidentsmale = list (disease = "Transport Accidents - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.52),log(2.68),log(4.20),0),
covBetaCurrent = matrix (c(0.121^2,0,0,0,0,0.117^2,0,0,0,0,0.121^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

transportaccidentsfemale = list (disease = "Transport Accidents - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.98),log(4.48),log(3.17),0),
covBetaCurrent = matrix (c(0.132^2,0,0,0,0,0.144^2,0,0,0,0,0.189^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

############# Other Accidents ##############
############# Other Accidents ##############
############# Other Accidents ##############

#### male ####

otheraccidentsmale = list (disease = "Other Accidents - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.58),log(2.48),log(6.07),0),
covBetaCurrent = matrix (c(0.069^2,0,0,0,0,0.07^2,0,0,0,0,0.072^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

otheraccidentsfemale = list (disease = "Other Accidents - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.08),log(5.24),log(8.56),0),
covBetaCurrent = matrix (c(0.088^2,0,0,0,0,0.095^2,0,0,0,0,0.102^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)


############# Suicide ##############
############# Suicide ##############
############# Suicide ##############

#### male ####

suicidemale = list (disease = "Suicide - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.21),log(3.47),log(8.62),0),
covBetaCurrent = matrix (c(0.113^2,0,0,0,0,0.106^2,0,0,0,0,0.107^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

suicidefemale = list (disease = "Suicide - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.82),log(8.22),log(14.75),0),
covBetaCurrent = matrix (c(0.157^2,0,0,0,0,0.147^2,0,0,0,0,0.157^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)



############# Assault ##############
############# Assault ##############
############# Assault ##############

assaultmale = list (disease = "Assault - MEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.75),log(3.67),log(9.47),0),
covBetaCurrent = matrix (c(0.089^2,0,0,0,0,0.086^2,0,0,0,0,0.089^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

assaultfemale = list (disease = "Assault - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(3.55),log(10.23),log(19.11),0),
covBetaCurrent = matrix (c(0.105^2,0,0,0,0,0.107^2,0,0,0,0,0.114^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

############# Undetermined Intent ##############
############# Undetermined Intent ##############
############# Undetermined Intent ##############

#### male ####

undeterminedintentmale = list (disease = "Undetermined Intent - MEN",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.49),log(2.36),log(4.40),0),
covBetaCurrent = matrix (c(0.07^2,0,0,0,0,0.07^2,0,0,0,0,0.073^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

undeterminedintentfemale = list (disease = "Undetermined Intent - WOMEN", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.43),log(4.54),log(7.93),0),
covBetaCurrent = matrix (c(0.077^2,0,0,0,0,0.091^2,0,0,0,0,0.099^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

################ Creating a list of all the diseases ####################


relativeriskmale = list(pancreatitismale,lowerrespmale,strokemale,tuberculosismale, livercirrhosismale,IHDmale, transportaccidentsmale,otheraccidentsmale,suicidemale,assaultmale,undeterminedintentmale)

relativeriskfemale = list(pancreatitisfemale,lowerrespfemale,strokefemale,tuberculosisfemale,livercirrhosisfemale,IHDfemale,transportaccidentsfemale,otheraccidentsfemale,suicidefemale,assaultfemale,undeterminedintentfemale)


## remove single diseases to clean up workspace
rm(pancreatitismale,lowerrespmale,strokemale,tuberculosismale, livercirrhosismale,IHDmale, transportaccidentsmale,otheraccidentsmale,suicidemale,assaultmale,undeterminedintentmale)

rm(pancreatitisfemale,lowerrespfemale,strokefemale,tuberculosisfemale,livercirrhosisfemale,IHDfemale,transportaccidentsfemale,otheraccidentsfemale,suicidefemale,assaultfemale,undeterminedintentfemale)


