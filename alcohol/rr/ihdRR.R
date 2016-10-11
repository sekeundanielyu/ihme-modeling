
## the relative risk function here is a piecewise function, different for men and women:
##
## For men we have:
## from 0-60: The normal IHD function (adjusted for the 3 main age groups). 
## from 60-100: RR of 1 with its relative risk
## from 100-150: another RR function. 
## For women we have: 
## 0-crossing (where RR function goes to 1 again): normal function
## crossing-150: another exponential function (lnRR is linear)
## For the Monte Carlo simulations, the sections are independently sampled
## and the function made "reasonable" by maintaining the same difference
## between the intersections. So in most cases, the (i+1) part will start
## where the ith part stopped, done by adding the required offsets.
## For males, the offset between <60 and >60 is a given value that leads to the 
## RR between 60 and 100 to be exactly 1 for the point estimate. 

#### Mortality ####
### male ###
IHDmaleMORT_1 = list(disease = "IHD - MEN - Mortality - Age_15-34",
                     RRCurrent = function(x, beta){ifelse(x>=0,
                                                          ifelse(x<60,
                                                          exp(beta[3] * (beta[1] * sqrt((x + 0.0099999997764826) / 100) +
                                                          beta[4] * ((x + 0.0099999997764826) / 100)^3)),
                                                          
                                                          ifelse(x<100,
                                                                 0.04571551+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                  beta[4] * ((60 + 0.0099999997764826) / 100)^3)),
                                                          ## x>=100
                                                          exp(beta[5]*(x-100))-1+0.04571551+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                                           beta[4] * ((60 + 0.0099999997764826) / 100)^3))
                                                          )),1)},
                     betaCurrent = c(-0.4870068,0,1.111874,1.550984,0.012),
                     covBetaCurrent = matrix (c(0.0797491^2,0,0,0,0,
                                                0,0,0,0,0,
                                                0,0,0.446999664429404,0,0,
                                                0,0,0,0.2822218^2,0,
                                                0,0,0,0,0.0025^2),5,5),
                     lnRRFormer = log(1.21),
                     varLnRRFormer = 0.04612728^2)

IHDmale_1 <- IHDmaleMORT_1
IHDmale_1$disease <- "IHD - MEN - Morbidity - Age_15-34"


### female ###
IHDfemaleMORT_1 = list(disease = "IHD - WOMEN - Mortality - Age_15-34",
                       RRCurrent = function(x, beta){ifelse(x>=0,
                                                            ifelse(x<30.3814,
                                                                   exp(beta[3] * (beta[1] * (x + 0.0099999997764826) / 100 +
                                                                                    beta[4] * (x + 0.0099999997764826) / 100 *
                                                                                    log((x + 0.0099999997764826)/100))),
                                                                   #else
                                                                   exp(beta[5]*(x-30.3814)-1+exp(beta[3] * (beta[1] * (30.3814 + 0.0099999997764826) / 100 +
                                                                                                              beta[4] * (30.3814 + 0.0099999997764826) / 100 *
                                                                                                              log((30.3814 + 0.0099999997764826)/100))))
                                                                   ),1)},
                       betaCurrent = c(1.832441,0,1.111874,1.538557,0.01),
                       covBetaCurrent = matrix(c(0.3878794^2,0,0,0,0, 
                                                 0,0,0,0,0, 
                                                 0,0,0.446999664429404,0,0,
                                                 0,0,0,0.338688^2,0,
                                                 0,0,0,0,0.0034^2),5,5),
                       lnRRFormer = log(1.36),
                       varLnRRFormer = 0.08203664^2)
                       
IHDfemale_1 <- IHDfemaleMORT_1
IHDfemale_1$disease <- "IHD - WOMEN - Morbidity - Age_15-34"


#### Mortality #### 
### male ###
IHDmaleMORT_2 = list(disease = "IHD - MEN - Mortality - Age_35-64",
                     RRCurrent = function(x, beta){ifelse(x>=0,
                                                          ifelse(x<60,
                                                                 exp(beta[3] * (beta[1] * sqrt((x + 0.0099999997764826) / 100) +
                                                                                  beta[4] * ((x + 0.0099999997764826) / 100)^3)),
                                                                 
                                                                 ifelse(x<100,
                                                                        0.0426483+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                                    beta[4] * ((60 + 0.0099999997764826) / 100)^3)),
                                                                        ## x>=100
                                                                        exp(beta[5]*(x-100))-1+0.0426483+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                                                           beta[4] * ((60 + 0.0099999997764826) / 100)^3))
                                                                 )),1)},
                     betaCurrent = c(-0.4870068,0,1.035623,1.550984,0.012),
                     covBetaCurrent = matrix (c(0.0797491^2,0,0,0,0,
                                                0,0.183673^2,0,0,0,
                                                0,0,0.107980600109464,0,0,
                                                0,0,0,0.2822218^2,0,
                                                0,0,0,0,0.0025^2),5,5),
                     lnRRFormer = log(1.21),
                     varLnRRFormer = 0.04612728^2)

IHDmale_2 <- IHDmaleMORT_2
IHDmale_2$disease <- "IHD - MEN - Morbidity - Age_35-64"
  
### female ###
IHDfemaleMORT_2 = list(disease = "IHD - WOMEN - Mortality - Age_35-64",
                       RRCurrent = function(x, beta){ifelse(x>=0,
                                                            ifelse(x<30.3814,
                                                                   exp(beta[3] * (beta[1] * (x + 0.0099999997764826) / 100 +
                                                                                    beta[4] * (x + 0.0099999997764826) / 100 *
                                                                                    log((x + 0.0099999997764826)/100))),
                                                                   #else
                                                                   exp(beta[5]*(x-30.3814)-1+exp(beta[3] * (beta[1] * (30.3814 + 0.0099999997764826) / 100 +
                                                                                                              beta[4] * (30.3814 + 0.0099999997764826) / 100 *
                                                                                                              log((30.3814 + 0.0099999997764826)/100))))
                                                            ),1)},
                       betaCurrent = c(1.832441,0,1.035623,1.538557,0.0093),
                       covBetaCurrent = matrix(c(0.3878794^2,0,0,0,0, 
                                                 0,0,0,0,0, 
                                                 0,0,0.107980600109464,0,0,
                                                 0,0,0,0.338688^2,0,
                                                 0,0,0,0,0.0006^2),5,5),
                       lnRRFormer = log(1.36),
                       varLnRRFormer = 0.08203664^2)

IHDfemale_2 <- IHDfemaleMORT_2
IHDfemale_2$disease <- "IHD - WOMEN - Morbidity - Age_35-64"

#### Mortality #### 
### male ###
IHDmaleMORT_3 = list(disease = "IHD - MEN - Mortality - Age 65 +",
                     RRCurrent = function(x, beta){ifelse(x>=0,
                                                          ifelse(x<60,
                                                                 exp(beta[3] * (beta[1] * sqrt((x + 0.0099999997764826) / 100) +
                                                                                  beta[4] * ((x + 0.0099999997764826) / 100)^3)),
                                                                 
                                                                 ifelse(x<100,
                                                                        0.0313606+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                                   beta[4] * ((60 + 0.0099999997764826) / 100)^3)),
                                                                        ## x>=100
                                                                        exp(beta[5]*(x-100))-1+0.0313606+exp(beta[3] * (beta[1] * sqrt((60 + 0.0099999997764826) / 100) +
                                                                                                                          beta[4] * ((60 + 0.0099999997764826) / 100)^3))
                                                                 )),1)},
                     betaCurrent = c(-0.4870068,0,0.757104,1.550984,0.012),
                     covBetaCurrent = matrix (c(0.0797491^2,0,0,0,0,
                                                0,0.183673^2,0,0,0,
                                                0,0,0.298176575203352,0,0,
                                                0,0,0,0.2822218^2,0,
                                                0,0,0,0,0.0025^2),5,5),
                     lnRRFormer = log(1.21),
                     varLnRRFormer = 0.04612728^2)
                     
IHDmale_3 <- IHDmaleMORT_3
IHDmale_3$disease <- "IHD - MEN - Morbidity - Age 65 +"

### female ###
IHDfemaleMORT_3 = list(disease = "IHD - WOMEN - Mortality - Age 65 +",
                       RRCurrent = function(x, beta){ifelse(x>=0,
                                                            ifelse(x<30.3814,
                                                                   exp(beta[3] * (beta[1] * (x + 0.0099999997764826) / 100 +
                                                                                    beta[4] * (x + 0.0099999997764826) / 100 *
                                                                                    log((x + 0.0099999997764826)/100))),
                                                                   #else
                                                                   exp(beta[5]*(x-30.3814)-1+exp(beta[3] * (beta[1] * (30.3814 + 0.0099999997764826) / 100 +
                                                                                                              beta[4] * (30.3814 + 0.0099999997764826) / 100 *
                                                                                                              log((30.3814 + 0.0099999997764826)/100))))
                                                            ),1)},
                       betaCurrent = c(1.832441,0,0.757104,1.538557,0.0068),
                       covBetaCurrent = matrix(c(0.3878794^2,0,0,0,0, 
                                                 0,0,0,0,0, 
                                                 0,0,0.298176575203352,0,0,
                                                 0,0,0,0.338688^2,0,
                                                 0,0,0,0,0.0003^2),5,5),
                       lnRRFormer = log(1.36),
                       varLnRRFormer = 0.08203664^2)
                       
IHDfemale_3 <- IHDfemaleMORT_3
IHDfemale_3$disease <- "IHD - WOMEN - Morbidity - Age 65 +"
  

##### Creating a list of the diseases #####
#relativeriskmale <- list(#IHDmale_1,
#  IHDmaleMORT_1,
#  #IHDmale_2,
#  IHDmaleMORT_2,
#  #IHDmale_3,
#  IHDmaleMORT_3)
#relativeriskfemale <- list(#IHDfemale_1,
#  IHDfemaleMORT_1,
#  #IHDfemale_2,
#  IHDfemaleMORT_2,
#  #IHDfemale_3,
#  IHDfemaleMORT_3)


#### Creating a list of the diseases #####
relativeriskmale <- list(IHDmale_1, IHDmaleMORT_1, IHDmale_2, IHDmaleMORT_2,
                         IHDmale_3, IHDmaleMORT_3)
relativeriskfemale <- list(IHDfemale_1, IHDfemaleMORT_1, IHDfemale_2, IHDfemaleMORT_2,
                         IHDfemale_3, IHDfemaleMORT_3)





