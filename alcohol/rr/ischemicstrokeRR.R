
######## Ischemic Stroke - Morbidity#######
##### male ages 15-34 ####

ischemicstrokemorbiditymale_1 = list(disease = "Ischemic Stroke - Morbidity - MEN - Ages 15-34",
                          RRCurrent = function(x, beta){ifelse(x >= 0,
                                                               ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                 beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                 log((1 + 0.0028572082519531) / 100)))),
                                                                 ifelse(x < 100,
                                                                      exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                        beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                        log((x + 0.0028572082519531) / 100))),
                                                                      exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                         beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                         log((100 + 0.0028572082519531) / 100))))), 0)},
                          betaCurrent = c(0.4030081,0.3877538,1.111874 ,0),
                          covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                    0.00201768,0.0594888^2,0,0,
                                                    0,0,0.446999664429404,0,
                                                    0,0,0,0),4,4),
                          lnRRFormer = log(1.33),
                          varLnRRFormer = 0.195728^2)


#### female ages 15-34 ####
ischemicstrokemorbidityfemale_1 = list(disease = "Ischemic Stroke - Morbidity - WOMEN - Ages 15-34",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * (x + 0.0028572082519531) / 100)),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * (100 + 0.0028572082519531) / 100))
                                                                        )), 0)},
                            betaCurrent = c(-2.48768,3.7087240,1.111874 ,0),
                            covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                      -.31633911,0.6645197^2,0,0,
                                                      0,0,0.446999664429404,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.15),
                            varLnRRFormer = 0.253779^2)

######## Ischemic Stroke - Mortality #######
##### male ages 15-34 ####

ischemicstrokemale_1 = list(disease = "Ischemic Stroke - MEN - Ages 15-34",
                          RRCurrent = function(x, beta){ifelse(x >= 0,
                                                               ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                 beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                 log((1 + 0.0028572082519531) / 100)))),
                                                                 ifelse(x < 100,
                                                                      exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                        beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                        log((x + 0.0028572082519531) / 100))),
                                                                      exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                         beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                         log((100 + 0.0028572082519531) / 100))))), 0)},
                          betaCurrent = c(0.4030081,0.3877538,1.111874 ,0),
                          covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                    0.00201768,0.0594888^2,0,0,
                                                    0,0,0.446999664429404,0,
                                                    0,0,0,0),4,4),
                          lnRRFormer = log(1.33),
                          varLnRRFormer = 0.195728^2)


#### female ages 15-34 ####
ischemicstrokefemale_1 = list(disease = "Ischemic Stroke - WOMEN - Ages 15-34",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * (x + 0.0028572082519531) / 100)),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * (100 + 0.0028572082519531) / 100))
                                                                        )), 0)},
                            betaCurrent = c(-2.48768,3.7087240,1.111874 ,0),
                            covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                      -.31633911,0.6645197^2,0,0,
                                                      0,0,0.446999664429404,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.15),
                            varLnRRFormer = 0.253779^2)
                            
                            
######## Ischemic Stroke - Morbidity #######
##### male ages 35-64 ####

ischemicstrokemorbiditymale_2 = list(disease = "Ischemic Stroke - Morbidity - MEN - Ages 35-64",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                   log((1 + 0.0028572082519531) / 100)))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                          log((x + 0.0028572082519531) / 100))),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((100 + 0.0028572082519531) / 100)))
                                                                        )), 0)},
                            betaCurrent = c(0.4030081,0.3877538,1.035623 ,0),
                            covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                      0.00201768,0.0594888^2,0,0,
                                                      0,0,0.107980600109464,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.33),
                            varLnRRFormer = 0.195728^2)


#### female ages 35-64 ####
ischemicstrokemorbidityfemale_2 = list(disease = "Ischemic Stroke - Morbidity - WOMEN - Ages 35-64",
                              RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                   ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                     beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                     ifelse(x < 100,
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                            beta[2] * (x + 0.0028572082519531) / 100)),
                                                                          exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (100 + 0.0028572082519531) / 100))
                                                                          )), 0)},
                              betaCurrent = c(-2.48768,3.7087240,1.035623 ,0),
                              covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                        -.31633911,0.6645197^2,0,0,
                                                        0,0,0.107980600109464,0,
                                                        0,0,0,0),4,4),
                              lnRRFormer = log(1.15),
                              varLnRRFormer = 0.253779^2)


######## Ischemic Stroke - Mortality #######
##### male ages 35-64 ####

ischemicstrokemale_2 = list(disease = "Ischemic Stroke - MEN - Ages 35-64",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                   log((1 + 0.0028572082519531) / 100)))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                          log((x + 0.0028572082519531) / 100))),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((100 + 0.0028572082519531) / 100)))
                                                                        )), 0)},
                            betaCurrent = c(0.4030081,0.3877538,1.035623 ,0),
                            covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                      0.00201768,0.0594888^2,0,0,
                                                      0,0,0.107980600109464,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.33),
                            varLnRRFormer = 0.195728^2)


#### female ages 35-64 ####
ischemicstrokefemale_2 = list(disease = "Ischemic Stroke - WOMEN - Ages 35-64",
                              RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                   ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                     beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                     ifelse(x < 100,
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                            beta[2] * (x + 0.0028572082519531) / 100)),
                                                                          exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (100 + 0.0028572082519531) / 100))
                                                                          )), 0)},
                              betaCurrent = c(-2.48768,3.7087240,1.035623 ,0),
                              covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                        -.31633911,0.6645197^2,0,0,
                                                        0,0,0.107980600109464,0,
                                                        0,0,0,0),4,4),
                              lnRRFormer = log(1.15),
                              varLnRRFormer = 0.253779^2)


####### Ischemic Stroke - Morbidity #######
#### male ages 65+ ####

ischemicstrokemorbiditymale_3 = list(disease = "Ischemic Stroke - Morbidity - MEN - Ages 65+",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                   log((1 + 0.0028572082519531) / 100)))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                          log((x + 0.0028572082519531) / 100))),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((100 + 0.0028572082519531) / 100)))
                                                                        )), 0)},
                            betaCurrent = c(0.4030081,0.3877538,0.757104,0),
                            covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                      0.00201768,0.0594888^2,0,0,
                                                      0,0,0.298176575203352,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.33),
                            varLnRRFormer = 0.195728^2)


#### female ages 65+ ####
ischemicstrokemorbidityfemale_3 = list(disease = "Ischemic Stroke - Morbidity - WOMEN - Ages 65+",
                              RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                   ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                     beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                     ifelse(x < 100,
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                            beta[2] * (x + 0.0028572082519531) / 100)),
                                                                          exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (100 + 0.0028572082519531) / 100))
                                                                          )), 0)},
                              betaCurrent = c(-2.48768,3.7087240,0.757104,0),
                              covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                        -.31633911,0.6645197^2,0,0,
                                                        0,0,0.298176575203352,0,
                                                        0,0,0,0),4,4),
                              lnRRFormer = log(1.15),
                              varLnRRFormer = 0.253779^2)



####### Ischemic Stroke - Mortality #######
#### male ages 65+ ####

ischemicstrokemale_3 = list(disease = "Ischemic Stroke - MEN - Ages 65+",
                            RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                 ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                   beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                   log((1 + 0.0028572082519531) / 100)))),
                                                                   ifelse(x < 100,
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                          beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                          log((x + 0.0028572082519531) / 100))),
                                                                        exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((100 + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((100 + 0.0028572082519531) / 100)))
                                                                        )), 0)},
                            betaCurrent = c(0.4030081,0.3877538,0.757104,0),
                            covBetaCurrent = matrix(c(0.0609985^2, 0.00201768,0,0,
                                                      0.00201768,0.0594888^2,0,0,
                                                      0,0,0.298176575203352,0,
                                                      0,0,0,0),4,4),
                            lnRRFormer = log(1.33),
                            varLnRRFormer = 0.195728^2)


#### female ages 65+ ####
ischemicstrokefemale_3 = list(disease = "Ischemic Stroke - WOMEN - Ages 65+",
                              RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                   ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                     beta[2] * (1 + 0.0028572082519531) / 100))),
                                                                     ifelse(x < 100,
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                            beta[2] * (x + 0.0028572082519531) / 100)),
                                                                          exp(beta[3]*(beta[1] * ((100 + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (100 + 0.0028572082519531) / 100))
                                                                          )), 0)},
                              betaCurrent = c(-2.48768,3.7087240,0.757104,0),
                              covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                        -.31633911,0.6645197^2,0,0,
                                                        0,0,0.298176575203352,0,
                                                        0,0,0,0),4,4),
                              lnRRFormer = log(1.15),
                              varLnRRFormer = 0.253779^2)



relativeriskmale=list(ischemicstrokemorbiditymale_1, ischemicstrokemale_1,
                      ischemicstrokemorbiditymale_2,ischemicstrokemale_2,
                      ischemicstrokemorbiditymale_3, ischemicstrokemale_3)

relativeriskfemale=list(ischemicstrokemorbidityfemale_1, ischemicstrokefemale_1,
                        ischemicstrokemorbidityfemale_2, ischemicstrokefemale_2,
                        ischemicstrokemorbidityfemale_3, ischemicstrokefemale_3)


