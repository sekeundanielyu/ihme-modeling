###################################################################################
#### The program to compute the AAFs for chronic diseases and their confidence ####
#### intervals is split into 3 files. chronicRR.R contains all the relative    ####
#### risk functions, chronicAAF.R contains the definitions of all the          ####
#### functions and computational steps required to derive the AAFs and the CIs ####
#### chronicAnalysis.R defines the input file and output destination and runs  ####
#### the computations. This is the only file that needs to be run.             ####
###################################################################################

### AGE_1   PE_1.111874 		VAR_0.446999664429404
### AGE_2   PE_1.035623			VAR_0.107980600109464
### AGE_3   PE_0.757104			VAR_0.298176575203352

AGE_ADJ_PE 		<- c(1.111874, 1.035623, 0.757104)
AGE_ADJ_VAR 	<- c(0.446999664429404, 0.107980600109464, 0.298176575203352)

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

IHDmale_1 = list (disease = "IHD Mortality  - Age_15-34", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_1 = list (disease = "IHD Mortality  - Age_15-34",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)




####### IHD 35 to 64 #######
####### IHD 35 to 64 #######

#### male ####

IHDmale_2 = list (disease = "IHD Mortality - Age_35-64", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_2 = list (disease = "IHD Mortality - Age_35-64",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)




####### IHD 65 PLUS #######
####### IHD 65 PLUS #######

#### male ####

IHDmale_3 = list (disease = "IHD Mortality - Age_65_PLUS", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.09178),log(1.49618),log(2.43944),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.054^2,0,0,0,0,0.054^2,0,0,0,0,0.056^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0461272772728111^2)

#### female ####


IHDfemale_3 = list (disease = "IHD Mortality - Age_65_PLUS",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.51383),log(3.43525),log(7.41902),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.061^2,0,0,0,0,0.07^2,0,0,0,0,0.079^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.36),
varLnRRFormer = 0.0820366388080261^2)





####### ISCHEMIC Stroke ##########
####### ISCHEMIC Stroke ##########

#### male ####

Ischemicstrokemale = list(disease = "Ischemic Stroke",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),0),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

Ischemicstrokefemale = list(disease = "Ischemic Stroke", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),0),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)







####### ISCHEMIC Stroke 15 to 34 ##########
####### ISCHEMIC Stroke 15 to 34 ##########

#### male ####

Ischemicstrokemale_1 = list(disease = "Ischemic Stroke - Age_15-34",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

Ischemicstrokefemale_1 = list(disease = "Ischemic Stroke - Age_15-34", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),AGE_ADJ_PE[1]),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,AGE_ADJ_VAR[1]),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)


####### ISCHEMIC Stroke 35 to 64 ##########
####### ISCHEMIC Stroke 35 to 64 ##########

#### male ####

Ischemicstrokemale_2 = list(disease = "Ischemic Stroke - Age_35-64",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

Ischemicstrokefemale_2 = list(disease = "Ischemic Stroke - Age_35-64", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),AGE_ADJ_PE[2]),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,AGE_ADJ_VAR[2]),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)



####### ISCHEMIC Stroke 65 PLUS ##########
####### ISCHEMIC Stroke 65 PLUS ##########

#### male ####

Ischemicstrokemale_3 = list(disease = "Ischemic Stroke - Age_65_PLUS",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

Ischemicstrokefemale_3 = list(disease = "Ischemic Stroke - Age_65_PLUS", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[4]*beta[1]),ifelse(x<cons2,exp(beta[4]*beta[2]),exp(beta[4]*beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),AGE_ADJ_PE[3]),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,AGE_ADJ_VAR[3]),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)















####### Hemorrhagic Stroke ##########
####### Hemorrhagic Stroke ##########

#### male ####

Hemorrhagicstrokemale = list(disease = "Hemorrhagic Stroke",
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.06),log(1.14),log(1.28),0),
covBetaCurrent = matrix (c(0.051^2,0,0,0,0,0.052^2,0,0,0,0,0.055^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.33),
varLnRRFormer = 0.195728^2)

#### female ####

Hemorrhagicstrokefemale = list(disease = "Hemorrhagic Stroke", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.38),log(1.36),log(1.62),0),
covBetaCurrent = matrix (c(0.042^2,0,0,0,0,0.068^2,0,0,0,0,0.086^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.15),
varLnRRFormer = 0.253779^2)






####### Pancreatitis #######
####### Pancreatitis #######

#### male ####

pancreatitismale = list(disease = "Pancreatitis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.43),log(2.07),log(6.69),0),
covBetaCurrent = matrix (c(0.162^2,0,0,0,0,0.154^2,0,0,0,0,0.151^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####

pancreatitisfemale = list(disease = "Pancreatitis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.09),log(5.01),log(19.26),0),
covBetaCurrent = matrix (c(0.225^2,0,0,0,0,0.19^2,0,0,0,0,0.176^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)

####### Lower Respiratory Infections ########
####### Lower Respiratory Infections ########


#### male ####

lowerrespmale = list(disease = "Lower Respiratory Infections", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent =  c(log(0.95),log(1.92),log(3.29),0),
covBetaCurrent = matrix (c(0.075^2,0,0,0,0,0.121^2,0,0,0,0,0.129^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####


lowerrespfemale = list(disease = "Lower Respiratory Infections", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.10),log(3.21),log(3.42),0),
covBetaCurrent = matrix (c(0.096^2,0,0,0,0,0.115^2,0,0,0,0,0.132^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)











####### Tuberculosis #######
####### Tuberculosis #######

#### male ####

tuberculosismale = list(disease = "Tuberculosis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.01),log(1.97),log(4.14),0),
covBetaCurrent = matrix (c(0.1^2,0,0,0,0,0.094^2,0,0,0,0,0.095^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.21),
varLnRRFormer = 0.0465106^2)

#### female ####

tuberculosisfemale = list (disease = "Tuberculosis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(0.93),log(4.06),log(5.32),0),
covBetaCurrent = matrix (c(0.191^2,0,0,0,0,0.160^2,0,0,0,0,0.185^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.44),
varLnRRFormer = 0.0585138^2)


####### Liver Cirrhosis #######
####### Liver Cirrhosis #######

#### male ####

livercirrhosismale = list (disease = "Liver Cirrhosis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(0.92),log(1.77),log(6.21),0),
covBetaCurrent = matrix (c(0.097^2,0,0,0,0,0.095^2,0,0,0,0,0.095^2,0,0,0,0,0),4,4),
lnRRFormer = log(1.31),
varLnRRFormer = 0.343816^2)

#### female ####

livercirrhosisfemale = list (disease = "Liver Cirrhosis", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(2.50),log(7.07),log(12.08),0),
covBetaCurrent = matrix (c(0.091^2,0,0,0,0,0.095^2,0,0,0,0,0.105^2,0,0,0,0,0),4,4),
lnRRFormer = log(6.5),
varLnRRFormer = 0.54991^2)















############# Transport Accidents ##############
############# Transport Accidents ##############
############# Transport Accidents ##############

#### male ####

transportaccidentsmale = list (disease = "MVA mort", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.52),log(2.68),log(4.20),0),
covBetaCurrent = matrix (c(0.121^2,0,0,0,0,0.117^2,0,0,0,0,0.121^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)

#### female ####

transportaccidentsfemale = list (disease = "MVA mort", 
RRCurrent = function(x,beta) ifelse(x>=0,ifelse(x<cons1,exp(beta[1]),ifelse(x<cons2,exp(beta[2]),exp(beta[3]))),0),
betaCurrent = c(log(1.98),log(4.48),log(3.17),0),
covBetaCurrent = matrix (c(0.132^2,0,0,0,0,0.144^2,0,0,0,0,0.189^2,0,0,0,0,0),4,4),
lnRRFormer = log(1),
varLnRRFormer = 0)


relativeriskmale = list(Ischemicstrokemale , Ischemicstrokemale , Ischemicstrokemale )

relativeriskfemale = list(Ischemicstrokefemale, Ischemicstrokefemale , Ischemicstrokefemale )





