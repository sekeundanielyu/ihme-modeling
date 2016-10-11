###################################################################################
#### The program to compute the AAFs for chronic diseases and their confidence ####
#### intervals is split into 3 files. chronicRR.R contains all the relative    ####
#### risk functions, chronicAAF.R contains the definitions of all the          ####
#### functions and computational steps required to derive the AAFs and the CIs ####
#### chronicAnalysis.R defines the input file and output destination and runs  ####
#### the computations. This is the only file that needs to be run.             ####
###################################################################################


## data for the various diseases, separatly for men and women
## information includes:
## disease: name of the disease
## RRCurrent: relative risk function for the (current) drinkers
## betaCurrent: coefficients for the RR function of (current) drinkers
## covBetaCurrent: covariance matrix for the beta coefficients of the (current) drinkers
## lnRRFormer: log relative risk of former drinkers
## varLnRRFormer: variance of log relative risk estimate of former drinkers


####### Oral Cavity and Pharynx Cancer #######
## male
oralcancermale = list(disease = "Oral Cavity and Pharynx Cancer - MEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(1*beta[1] + x*beta[2] + x^2*beta[3] + x^3*beta[4]),exp(1*beta[1] + 100*beta[2] + 100^2*beta[3] + 100^3*beta[4]))},
  #RRCurrent = function(x, beta) {exp(sum(beta * c(1, x, x^2, x^3)))},
  betaCurrent = c(0, 0.0270986006898689, -0.0000918619672439482, 7.38478068923644*(10^-8)),
  covBetaCurrent = matrix(c(0,0,0,0,0,1.94786135584958*10^(-06),-1.69994463981214*10^(-08),3.3878103564092*10^(-11),0,-1.69994463981214*10^(-08),0.0000000001802 ,-3.87375712299595*10^(-13),0, 3.3878103564092*10^(-11),-3.87375712299595*10^(-13),8.65026664126274*10^(-16)),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
## female
oralcancerfemale = list(disease = "Oral Cavity and Pharynx Cancer - WOMEN",
    RRCurrent = function(x, beta) {ifelse(x < 100,exp(1*beta[1] + x*beta[2] + x^2*beta[3] + x^3*beta[4]),exp(1*beta[1] + 100*beta[2] + 100^2*beta[3] + 100^3*beta[4]))},
  #RRCurrent = function(x, beta){exp(sum(beta * c(1, x, x^2, x^3)))},
  betaCurrent = c(0, 0.0270986006898689, -0.0000918619672439482, 7.38478068923644*10^(-08)),
  covBetaCurrent = matrix(c(0,0,0,0,0,1.94786135584958*10^(-06),-1.69994463981214*10^-08,3.3878103564092*10^-11,0,-1.69994463981214*10^-08,0.0000000001802,-3.87375712299595*10^-13,0,3.3878103564092*10^-11,-3.87375712299595*10^-13,8.65026664126274*10^-16),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

####### Oral Oesophagus Cancer ###########
## male
oesophaguscancermale = list(disease = "Oesophagus Cancer - MEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(1*beta[1] + x*beta[2] + x^2*beta[3] + x^3*beta[4]),exp(1*beta[1] + 100*beta[2] + 100^2*beta[3] + 100^3*beta[4]))},
  betaCurrent = c(0,0.0132063596418668,0,-4.14801974664481*10^(-08)),
  covBetaCurrent = matrix(c(0,0,0,0,0,1.5257062507551*10^(-07),0,-6.88520511004078*10^(-13),0,0,0,0,0,-6.88520511004078*10^(-13),0,8.09350992351893*10^(-18)),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
## female
oesophaguscancerfemale = list(disease = "Oesophagus Cancer - WOMEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(1*beta[1] + x*beta[2] + x^2*beta[3] + x^3*beta[4]),exp(1*beta[1] + 100*beta[2] + 100^2*beta[3] + 100^3*beta[4]))},
  betaCurrent = c(0,0.0132063596418668,0,-4.14801974664481*10^(-08)),
  covBetaCurrent =  matrix(c(0,0,0,0,0,1.5257062507551*10^(-07),0,-6.88520511004078*10^(-13),0,0,0,0,0,-6.88520511004078*10^(-13),0,8.09350992351893*10^(-18)),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

######## Colon Cancer ########
## male
coloncancermale = list(disease = "Colon Cancer - MEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(x * beta[2]),exp(100 * beta[2]))},
  betaCurrent = c(0,0.0019,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000005,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
## female
coloncancerfemale = list(disease = "Colon Cancer - WOMEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(x * beta[2]),exp(100 * beta[2]))},
  betaCurrent = c(0,0.0019,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000005,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

######## Rectum Cancer #########
## male
rectumcancermale = list(disease = "Rectum Cancer - MEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(x * beta[2]),exp(100 * beta[2]))},
  betaCurrent = c(0,0.0035,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000002,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
## female
rectumcancerfemale = list(disease = "Rectum Cancer - WOMEN", 
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(x * beta[2]),exp(100 * beta[2]))},
  betaCurrent = c(0,0.0035,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000002,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)
 
######## Liver Cancer ########
## male
livercancermale = list(disease = "Liver Cancer - MEN",
  RRCurrent = function(x, beta){ifelse(x < 100,exp(x * beta[2] + x^2 * beta[3]),exp(100 * beta[2] + 100^2 * beta[3]))},
  betaCurrent = c(0,0.00742949152371, -0.000014859275217,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000018443305,-0.0000000056136,0,0,-0.0000000056136,0.0000000000233,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
## female
livercancerfemale = list(disease = "Liver Cancer - WOMEN",
  RRCurrent = function(x, beta){ifelse(x < 100,exp(x * beta[2] + x^2 * beta[3]),exp(100 * beta[2] + 100^2 * beta[3]))},
  betaCurrent = c(0,0.00742949152371, -0.000014859275217,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000018443305,-0.0000000056136,0,0,-0.0000000056136,0.0000000000233,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

######## Larynx Cancer #########
#### male ####
larynxcancermale = list(disease = "Larynx Cancer - MEN",
  RRCurrent = function (x, beta) {ifelse(x < 100,exp(x * beta[2] + x^3 * beta[4]),exp(100 * beta[2] + 100^3 * beta[4]))},
  betaCurrent = c(0,0.01422,0,-0.000000073),
  covBetaCurrent = matrix(c(0,0,0,0,0,4.99003046048626*10^-07,0,-6.34007214793483*10^(-12),0,0,0,0,0,-6.34007214793483*10^-12,0,1.26423773522508*10^-16),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
#### female ####
larynxcancerfemale = list(disease = "Larynx Cancer - WOMEN",
  RRCurrent = function (x, beta) {ifelse(x < 100,exp(x * beta[2] + x^3 * beta[4]),exp(100 * beta[2] + 100^3 * beta[4]))},
  betaCurrent = c(0,0.01422,0,-0.000000073), 
  covBetaCurrent = matrix(c(0,0,0,0,0,4.99003046048626*10^-07,0,-6.34007214793483*10^(-12),0,0,0,0,0,-6.34007214793483*10^-12,0,1.26423773522508*10^-16),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

####### Breast Cancer #######
#### male ####
#Place holder only DO NOT USE AS AAF
breastcancermale = list(disease = "Breast Cancer - MEN",
  RRCurrent = function (x, beta) {return(1)},
  betaCurrent = c(0,0,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1),
  varLnRRFormer = 0)
#### female ####
breastcancerfemale = list(disease = "Breast Cancer - WOMEN", 
  RRCurrent = function (x, beta) {ifelse(x < 100,exp(x * beta[2]),exp(100 * beta[2]))},
  betaCurrent = c(0,0.00879,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0000006,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)


####### Epilepsy #######
#### male ####
epilepsymale = list(disease = "Epilepsy - MEN",
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(beta[2] * (x + 0.5) / 100),exp(beta[2] * (100 + 0.5) / 100))},
  betaCurrent = c(0,1.22861,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1391974^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
#### female ####
epilepsyfemale = list(disease = "Epilepsy - WOMEN", 
  RRCurrent = function(x, beta) {ifelse(x < 100,exp(beta[2] * (x + 0.5) / 100),exp(beta[2] * (100 + 0.5) / 100))},
  betaCurrent = c(0,1.22861,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1391974^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)


####### Lower Respiratory Infections ########
#### male ####
lowerrespmale = list(disease = "Lower Respiratory Infections - MEN", 
  RRCurrent = function(x, beta){ifelse(x < 120,exp(beta[2]*((x + 0.0399999618530273) / 100)),exp(beta[2]*((120 + 0.0399999618530273) / 100)))},
  betaCurrent = c(0,0.4764038,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1922055^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2) 
#### female ####
lowerrespfemale = list(disease = "Lower Respiratory Infections - WOMEN",  
  RRCurrent = function(x, beta){ifelse(x < 120,exp(beta[2]*((x + 0.0399999618530273) / 100)),exp(beta[2]*((120 + 0.0399999618530273) / 100)))},
  betaCurrent = c(0,0.4764038,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1922055^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)


####### Hemorrhagic Stroke - Morbidity ##########
#### male ####
hemorrhagicstrokemorbiditymale = list(disease = "Hemorrhagic Stroke - Morbidity - MEN",
  RRCurrent = function(x, beta){ifelse(x >= 0,
    ifelse(x < 1, 1 + x * (exp(beta[2] * (1 + 0.0028572082519531)/ 100) - 1),
           ifelse(x < 100,exp(beta[2] * (x + 0.0028572082519531) / 100),exp(beta[2] * (100 + 0.0028572082519531) / 100))), 0)},
  betaCurrent = c(0,0.7695021,0,0), 
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1570753^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.33),
  varLnRRFormer = 0.195728^2)
#### female ####
##### remark:
##### this function is somehow special as it includes a sqrt(x)*ln(x) function.
##### Therefore, the beta2 coefficient will represent this factor and not the
##### coefficient for x^1.
## NOTE: This is the original function: to be replaced by the female mortality function below
## This is because this morbidity function plots a strong protective effect for morbidity 
## without a corresponding effect for men or for female mortality
## so we default to the female mortality RR curve

## We do this replacement in the 05_gather code   - now we're replacing both of these with the mortality, but in the analysis section of code

hemorrhagicstrokemorbidityfemale = list(disease = "Hemorrhagic Stroke - Morbidity - WOMEN",
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x < 1, 1 + x * (exp(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                               beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                               log((1 + 0.0028572082519531) / 100)) - 1),ifelse(x < 100,
           exp(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
               beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
               log((x + 0.0028572082519531) / 100)),
           exp(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                log((100 + 0.0028572082519531) / 100)))), 0)},
  betaCurrent = c(0.9396292,0.944208,0,0),
  covBetaCurrent = matrix(c(0.2571460^2, 0.01587064,0,0,0.01587064,0.1759703^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.15),
  varLnRRFormer = 0.253779^2)


####### Hemorrhagic Stroke - Mortality #########
#### male ####
hemorrhagicstrokemale = list(disease = "Hemorrhagic Stroke - Mortality - MEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 - x * (1 - exp(beta[2] * (1 + 0.0028572082519531) / 100)),
           ifelse(x < 100,exp(beta[2] * (x + 0.0028572082519531) / 100),exp(beta[2] * (100 + 0.0028572082519531) / 100))), 0)},
  betaCurrent = c(0,0.6898937,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.1141980^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.33),
  varLnRRFormer = 0.195728^2)
#### female ####
hemorrhagicstrokefemale = list(disease = "Hemorrhagic Stroke - Mortality - WOMEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 - x * (1 - exp(beta[2] * (1 + 0.0028572082519531) / 100)),
           ifelse(x < 100,exp(beta[2] * (x + 0.0028572082519531) / 100),exp(beta[2] * (100 + 0.0028572082519531) / 100))), 0)},
  betaCurrent = c(0,1.466406,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.3544172^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.15),
  varLnRRFormer = 0.253779^2)


####### Tuberculosis #######
#### remark: this is a piecewise constant function ####
#### male ####
tuberculosismale = list(disease = "Tuberculosis - MEN", 
  RRCurrent = function(x, beta){ifelse(x >= 0, ifelse(x < 40, 1, exp(beta[1])), 0)},
  betaCurrent = c(log(2.96),0,0,0),
  covBetaCurrent = matrix(c(0.133617^2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
#### female ####
tuberculosisfemale = list(disease = "Tuberculosis - WOMEN",
  RRCurrent = function(x, beta){ifelse(x >= 0, ifelse(x < 40, 1, exp(beta[1])), 0)},
  betaCurrent = c(log(2.96),0,0,0),
  covBetaCurrent =  matrix(c(0.133617^2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)


####### Diabetes Mellitus #######
#### male ####
#### remark: here beta 3 is the coefficient for x*log(x) and not x^2
diabetesmale = list(disease = "Diabetes Mellitus - MEN", 
                    RRCurrent = function(x, beta){ifelse(x >= 0,
                                                         ifelse( x >= 80, exp(beta[2] * ((80 + 0.003570556640625) / 10) +
                                                                                beta[3]*((80 + 0.003570556640625) / 10) *
                                                                                log((80 + 0.003570556640625) / 10)),
                                                                 exp(beta[2] * ((x + 0.003570556640625) / 10) +
                                                                       beta[3] * ((x + 0.003570556640625) / 10) *
                                                                       log((x + 0.003570556640625) / 10))), 0)},
                    betaCurrent = c(0,-0.109786,0.0614931,0),
                    covBetaCurrent = matrix(c(0,0,0,0,0,0.00159982,-0.00047546,0,0,-0.00047546,0.00030743,0,0,0,0,0),4,4),
                    lnRRFormer = log(1.18),
                    varLnRRFormer = 0.136542^2)
#### female ####
diabetesfemale = list(disease = "Diabetes Mellitus - WOMEN", 
                      RRCurrent = function(x, beta){ifelse(x >= 0,
                                                           ifelse(x >= 52, exp(beta[1] * sqrt((52 + 0.003570556640625) / 10) +
                                                                                 beta[2] * ((52 + 0.003570556640625) / 10)^3),
                                                                  exp(beta[1] * sqrt((x + 0.003570556640625) / 10) +
                                                                        beta[2] * ((x + 0.003570556640625) / 10)^3)), 0)},
                      betaCurrent = c(-0.4002597,0.0076968,0,0),
                      covBetaCurrent = matrix(c(0.00266329,-0.00003465,0,0, -0.00003465,0.00000355,0,0,0,0,0,0,0,0,0,0),4,4),
                      lnRRFormer = log(1.14),
                      varLnRRFormer = 0.0714483^2)



####### Hypertension #######
#### male ####
hypertensionmale = list(disease = "Hypertension - MEN",
  RRCurrent = function(x, beta){ifelse(x < 80,exp(beta[2]*(x + 0.0500001907348633)),exp(beta[2]*(80 + 0.0500001907348633)))},
  betaCurrent = c(0,0.0090635,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0009706^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1),
  varLnRRFormer = 0)
#### female ####
##### remark: this function is somehow special as it includes a sqrt(x)*ln(x) function. Therefore, the beta2 coefficient will represent
##### this factor and not the coefficient for x^1. 
hypertensionfemale = list(disease = "Hypertension - WOMEN",
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 + x * (exp(beta[1] * (1 + 0.0500001907348633)^0.5 +
             beta[2] * (1 + 0.0500001907348633)^0.5 *
             log((1 + 0.0500001907348633))) - 1),
           ifelse(x < 80,exp(beta[1] * (x + 0.0500001907348633)^0.5 +
               beta[2] * (x + 0.0500001907348633)^0.5 *
               log((x + 0.0500001907348633))),exp(beta[1] * (80 + 0.0500001907348633)^0.5 +
                                                    beta[2] * (80 + 0.0500001907348633)^0.5 *
                                                    log((80 + 0.0500001907348633))))),0)},
  betaCurrent = c(-0.298563,0.1131741,0,0),
  covBetaCurrent = matrix(c(.00124534,-.00013185,0,0,-.00013185,.00004151,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1),
  varLnRRFormer = 0)


####### Liver Cirrhosis - Morbidity #######
#### male ####
livercirrhosismorbiditymale = list(disease = "Liver Cirrhosis - Morbidity - MEN",
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 + x * (exp(beta[2] * (1 + 0.1699981689453125) / 100) - 1),
           ifelse(x < 120,exp(beta[2] * (x + 0.1699981689453125) / 100),exp(beta[2] * (120 + 0.1699981689453125) / 100))), 0)},
  betaCurrent = c(0,1.687111,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.189599^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.31),
  varLnRRFormer = 0.343816^2)
#### female ####
livercirrhosismorbidityfemale = list(disease = "Liver Cirrhosis - Morbidity - WOMEN", 
  RRCurrent = function (x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 + x * (exp(beta[1] * sqrt((1 + 0.1699981689453125) / 100)) - 1),
           ifelse(x < 120,exp(beta[1] * sqrt((x + 0.1699981689453125) / 100)),exp(beta[1] * sqrt((120 + 0.1699981689453125) / 100)))), 0)},
  betaCurrent = c(2.351821,0,0,0),
  covBetaCurrent = matrix(c(0.2240277^2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(6.5),
  varLnRRFormer = 0.54991^2)


####### Liver Cirrhosis - Mortality #######
####### Remark: The expression of the beta coefficient for this RR function is a sum of 2 coefficients which have covariance
####### Therefore, beta1 will be the first "part" of the coefficient and beta2 the second one.
#### male ####
livercirrhosismale = list(disease = "Liver Cirrhosis - Mortality - MEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 + x * (exp((beta[1] + beta[2]) * (1 + 0.1699981689453125) / 100) - 1),
           ifelse(x < 120,exp((beta[1] + beta[2]) * (x + 0.1699981689453125) / 100),exp((beta[1] + beta[2]) * (120 + 0.1699981689453125) / 100))), 0)},
  betaCurrent = c(1.687111,1.106413,0,0),
  covBetaCurrent = matrix(c(.0359478,-.0359478,0,0,-.0359478,.07174495,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.31),
  varLnRRFormer = 0.343816^2)
#### female ####
livercirrhosisfemale = list(disease = "Liver Cirrhosis - Mortality - WOMEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x <= 1, 1 + x * (exp((beta[1] + beta[2]) * sqrt((1 + 0.1699981689453125) / 100)) - 1),
           ifelse(x < 120,exp((beta[1] + beta[2]) * sqrt((x + 0.1699981689453125) / 100)),exp((beta[1] + beta[2]) * sqrt((120 + 0.1699981689453125) / 100)))), 0)},
  betaCurrent = c(2.351821,0.9002139,0,0),
  covBetaCurrent = matrix(c(.05018842,-.05018842,0,0,-.05018842,.10270352,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(6.5),
  varLnRRFormer = 0.54991^2)


####### Conduction Disorders and other Dysrythmias #######
#### male ####
conductiondisordermale = list(disease = "Conduction Disorder and other Dysrythmias - MEN",
  RRCurrent = function(x, beta){ifelse(x < 80,exp(beta[2] * (x + 0.0499992370605469) / 10),exp(beta[2] * (80 + 0.0499992370605469) / 10))},
  betaCurrent = c(0,0.0575183,0,0), 
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0100899^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
#### female ####
conductiondisorderfemale = list(disease = "Conduction Disorder and other Dysrythmias - WOMEN",
  RRCurrent = function(x, beta){ifelse(x < 80,exp(beta[2]*(x + .0499992370605469) / 10),exp(beta[2]*(80 + .0499992370605469) / 10))},
  betaCurrent = c(0,0.0575183,0,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0.0100899^2,0,0,0,0,0,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

####### Pancreatitis #######
#### male ####
pancreatitismale = list(disease = "Pancreatitis - MEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x > 150, exp(beta[3] * ((150 + 0.2900009155273438) / 100)^2),
           ifelse(x < 100, exp(beta[3] * ((x + 0.2900009155273438) / 100)^2),exp(beta[3] * ((100 + 0.2900009155273438) / 100)^2))), 0)},
  betaCurrent = c(0,0,1.496432,0),
  covBetaCurrent = matrix(c(0,0,0,0,0,0,0,0,0,0,0.1710682^2,0,0,0,0,0),4,4),
  lnRRFormer = log(1.21),
  varLnRRFormer = 0.0465106^2)
#### female ####
pancreatitisfemale = list(disease = "Pancreatitis - WOMEN", 
  RRCurrent = function(x, beta){ ifelse(x >= 0,
    ifelse(x > 150, exp(beta[3] * ((150 + 0.2900009155273438) / 100)^2),
           ifelse(x < 100,exp(beta[3] * ((x + 0.2900009155273438) / 100)^2),exp(beta[3] * ((100 + 0.2900009155273438) / 100)^2))), 0)},
  betaCurrent = c(0,0,1.496432,0),
  covBetaCurrent = matrix (c(0,0,0,0,0,0,0,0,0,0,0.1710682^2,0,0,0,0,0),4,4),
  lnRRFormer = log(1.44),
  varLnRRFormer = 0.0585138^2)

## collect all diseases in one list as before (just name the list - it makes it easier to read)
#relativeriskmale = list(oralcancer = oralcancermale, othercancer = oesophaguscancermale)
#rm(oralcancermale, oralcancerfemale, oesophaguscancermale, oesophaguscancerfemale)

#if(FALSE){
relativeriskmale = list(oralcancermale, oesophaguscancermale, coloncancermale,
  rectumcancermale, livercancermale, larynxcancermale, breastcancermale,
  epilepsymale, lowerrespmale, hemorrhagicstrokemorbiditymale, hemorrhagicstrokemale,
  tuberculosismale, diabetesmale, hypertensionmale, livercirrhosismorbiditymale,
  livercirrhosismale, conductiondisordermale, pancreatitismale)

relativeriskfemale = list(oralcancerfemale, oesophaguscancerfemale, coloncancerfemale, rectumcancerfemale,livercancerfemale, larynxcancerfemale,breastcancerfemale, epilepsyfemale,lowerrespfemale,hemorrhagicstrokemorbidityfemale,hemorrhagicstrokefemale,tuberculosisfemale, diabetesfemale, hypertensionfemale, livercirrhosismorbidityfemale, livercirrhosisfemale,conductiondisorderfemale,pancreatitisfemale)


## remove single diseases to clean up workspace
rm(oralcancermale, oesophaguscancermale, coloncancermale, rectumcancermale, livercancermale, larynxcancermale,breastcancermale, epilepsymale,lowerrespmale,hemorrhagicstrokemorbiditymale, hemorrhagicstrokemale,tuberculosismale, diabetesmale,hypertensionmale, livercirrhosismorbiditymale, livercirrhosismale,conductiondisordermale,pancreatitismale)

rm(oralcancerfemale, oesophaguscancerfemale, coloncancerfemale, rectumcancerfemale,livercancerfemale, larynxcancerfemale,breastcancerfemale, epilepsyfemale,lowerrespfemale,hemorrhagicstrokemorbidityfemale,hemorrhagicstrokefemale,tuberculosisfemale, diabetesfemale, hypertensionfemale, livercirrhosismorbidityfemale, livercirrhosisfemale,conductiondisorderfemale,pancreatitisfemale)
#}

