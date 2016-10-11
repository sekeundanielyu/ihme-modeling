


rm(list=ls()); library(foreign); library(MASS); library(scales)
if (Sys.info()[1] == 'Windows') {
  username <- "mcoates"
  root <- "J:/"
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
}

source("C:/Users//Documents/repos/drugs_alcohol/rr/sent_11_16_15/ischemicstrokeRR-1.R")
source("C:/Users//Documents/repos/drugs_alcohol/rr/sent_11_16_15/RRDiabetes-1.R")


new_diabetesfemale <- diabetesfemale
new_diabetesmale <- diabetesmale

new_ischemicfemale <- relativeriskfemale
new_ischemicmale <- relativeriskmale
rm(diabetesfemale,diabetesmale,relativeriskfemale,relativeriskmale,ischemicstrokefemale_1,ischemicstrokefemale_2,ischemicstrokefemale_3,
   ischemicstrokemale_1,ischemicstrokemale_2,ischemicstrokemale_3)


####### Diabetes Mellitus #######
#### male ####
#### remark: here beta 3 is the coefficient for x*log(x) and not x^2
diabetesmale = list(disease = "Diabetes Mellitus - MEN", 
                    RRCurrent = function(x, beta){ifelse(x >= 0,
                                                         exp(beta[2] * ((x + 0.003570556640625) / 10) +
                                                               beta[3] * ((x + 0.003570556640625) / 10) *
                                                               log((x + 0.003570556640625) / 10)), 0)},
                    betaCurrent = c(0,-0.109786,0.0614931,0),
                    covBetaCurrent = matrix(c(0,0,0,0,0,0.00159982,-0.00047546,0,0,-0.00047546,0.00030743,0,0,0,0,0),4,4),
                    lnRRFormer = log(1.18),
                    varLnRRFormer = 0.136542^2)
#### female ####
diabetesfemale = list(disease = "Diabetes Mellitus - WOMEN", 
                      RRCurrent = function(x, beta){ifelse(x >= 0,
                                                           exp(beta[1] * sqrt((x + 0.003570556640625) / 10) +
                                                                 beta[2] * ((x + 0.003570556640625) / 10)^3), 0)},
                      betaCurrent = c(-0.4002597,0.0076968,0,0),
                      covBetaCurrent = matrix(c(0.00266329,-0.00003465,0,0, -0.00003465,0.00000355,0,0,0,0,0,0,0,0,0,0),4,4),
                      lnRRFormer = log(1.14),
                      varLnRRFormer = 0.0714483^2)



######## Ischemic Stroke - Morbidity#######
##### male ages 15-34 ####

ischemicstrokemorbiditymale_1 = list(disease = "Ischemic Stroke - Morbidity - MEN - Ages 15-34",
                                     RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                          ifelse(x <= 1, 1 - x * (1 - exp(beta[3]*(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                                                                     beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                                                                     log((1 + 0.0028572082519531) / 100)))),
                                                                                 exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                                log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                                   exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                  beta[2] * (x + 0.0028572082519531) / 100))), 0)},
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
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (x + 0.0028572082519531) / 100))), 0)},
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
                                                                                 exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                                log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                                   exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                  beta[2] * (x + 0.0028572082519531) / 100))), 0)},
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
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (x + 0.0028572082519531) / 100))), 0)},
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
                                                                                 exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                                log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                                   exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                                  beta[2] * (x + 0.0028572082519531) / 100))), 0)},
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
                                                                        exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                       beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                       log((x + 0.0028572082519531) / 100)))), 0)},
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
                                                                          exp(beta[3]*(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                         beta[2] * (x + 0.0028572082519531) / 100))), 0)},
                              betaCurrent = c(-2.48768,3.7087240,0.757104,0),
                              covBetaCurrent = matrix(c(0.4875627^2, -.31633911,0,0,
                                                        -.31633911,0.6645197^2,0,0,
                                                        0,0,0.298176575203352,0,
                                                        0,0,0,0),4,4),
                              lnRRFormer = log(1.15),
                              varLnRRFormer = 0.253779^2)



relativeriskmale=list(#ischemicstrokemorbiditymale_1,
 ischemicstrokemale_1, #ischemicstrokemorbiditymale_2,
 ischemicstrokemale_2, #ischemicstrokemorbiditymale_3,
 ischemicstrokemale_3)

relativeriskfemale=list(#ischemicstrokemorbidityfemale_1,
 ischemicstrokefemale_1, #ischemicstrokemorbidityfemale_2,
 ischemicstrokefemale_2, #ischemicstrokemorbidityfemale_3,
 ischemicstrokefemale_3)


# relativeriskmale=list(ischemicstrokemorbiditymale_1, ischemicstrokemale_1,
#                       ischemicstrokemorbiditymale_2,ischemicstrokemale_2,
#                       ischemicstrokemorbiditymale_3, ischemicstrokemale_3)
# 
# relativeriskfemale=list(ischemicstrokemorbidityfemale_1, ischemicstrokefemale_1,
#                         ischemicstrokemorbidityfemale_2, ischemicstrokefemale_2,
#                         ischemicstrokemorbidityfemale_3, ischemicstrokefemale_3)




rm(ischemicstrokemorbidityfemale_1,ischemicstrokemorbidityfemale_2,ischemicstrokemorbidityfemale_3,
   ischemicstrokemorbiditymale_1,ischemicstrokemorbiditymale_2,ischemicstrokemorbiditymale_3)

rm(ischemicstrokefemale_1,ischemicstrokefemale_2,ischemicstrokefemale_3,
   ischemicstrokemale_1,ischemicstrokemale_2,ischemicstrokemale_3)

comparelist <- list(diabetes_male=list(new_diabetesmale,diabetesmale),diabetes_female=list(new_diabetesfemale,diabetesfemale),is_male_1=list(new_ischemicmale[[1]],relativeriskmale[[1]]),
                    is_male_2=list(new_ischemicmale[[2]],relativeriskmale[[2]]),is_male_3=list(new_ischemicmale[[3]],relativeriskmale[[3]]),is_female_1=list(new_ischemicfemale[[1]],relativeriskfemale[[1]]),
                    is_female_2=list(new_ischemicfemale[[2]],relativeriskfemale[[2]]),is_female_3=list(new_ischemicfemale[[3]],relativeriskfemale[[3]]))


pdf(paste(root,"/WORK/05_risk/risks/drugs_alcohol/diagnostics/compare_new_diabetes_ischstroke",Sys.Date(),".pdf",sep = ""), width=10, height=7)
for (i in comparelist) {
  cat(paste(i[[1]]$disease)); flush.console()
  ## get draws
  B <- 1000
  
  set.seed(12345)
  beta1 <- mvrnorm(B, mu = i[[1]]$betaCurrent, Sigma = i[[1]]$covBetaCurrent)
  set.seed(12345)
  beta2 <- mvrnorm(B, mu = i[[2]]$betaCurrent, Sigma = i[[2]]$covBetaCurrent)
  
  ## draw random sample of log relative risk for former drinkers
  set.seed(12345)
  lnRR1 <- rnorm(B, mean = i[[1]]$lnRRFormer, sd = sqrt(i[[1]]$varLnRRFormer))
  set.seed(12345)
  lnRR2 <- rnorm(B, mean = i[[2]]$lnRRFormer, sd = sqrt(i[[2]]$varLnRRFormer))
  
  ## get upper and lower
  CI <- data.frame(x=c(0:150), upper1 = rep(NA,151), lower1=rep(NA,151), upper2 = rep(NA,151), lower2 = rep(NA,151))
  for (j in 0:150) {
    CI$upper1[j+1] <- quantile((apply(beta1, 1, function(x) {i[[1]]$RRCurrent(j,beta=x)} )), c(.975))
    CI$upper2[j+1] <- quantile((apply(beta2, 1, function(x) {i[[2]]$RRCurrent(j,beta=x)} )), c(.975))
    CI$lower1[j+1] <- quantile((apply(beta1, 1, function(x) {i[[1]]$RRCurrent(j,beta=x)} )), c(.025))
    CI$lower2[j+1] <- quantile((apply(beta2, 1, function(x) {i[[2]]$RRCurrent(j,beta=x)} )), c(.025))
  }
  
  ## point estimates
  RRfunc1 <- function(x) {
    i[[1]]$RRCurrent(x, beta = i[[1]]$betaCurrent)
  }
  RRfunc2 <- function(x) {
    i[[2]]$RRCurrent(x, beta = i[[2]]$betaCurrent)
  }
  
  RRformer1 <- exp(i[[1]]$lnRRFormer)
  RRformer2 <- exp(i[[2]]$lnRRFormer)
  
  
  point1 <- "blue"
  point2 <- "red"
  shade1 <- alpha(point1, .2)
  shade2 <- alpha(point2, .2)
  
  
  
  from <- .01
  to <- 150
  ymax = max(unlist(CI[,2:5]))
  if (ymax > 80) {
    ymax <- 80
    real_ymax <- max(unlist(CI[,2:5]))
  } 

  curve(RRfunc1,from=from,to=to,main=paste0("New ",i[[2]]$disease, " Relative Risks from Alcohol"),xlab="Alcohol (g/day)",
        ylab="Relative Risk",col=point1,lwd=2,ylim=c(.8,ymax))
  par(new=T)
  curve(RRfunc2,from=from,to=to,main=paste0("New ",i[[2]]$disease, " Relative Risks from Alcohol"),xlab="Alcohol (g/day)",
        ylab="Relative Risk",col=point2,lwd=2,ylim=c(.8,ymax))
  abline(h=1,lty=2)
  abline(h=RRformer1,lty=2,lwd=2,col=point1)
  abline(h=RRformer2,lty=2,lwd=2,col=point2)
  polygon(c(CI$x, rev(CI$x)), c(CI$upper1, rev(CI$lower1)),
          col = shade1, border = NA)
  polygon(c(CI$x, rev(CI$x)), c(CI$upper2, rev(CI$lower2)),
          col = shade2, border = NA)
  ifelse(ymax < 80, 
         legend(x=.01,y=ymax,c(paste0(i[[1]]$disease," New"),paste0(i[[2]]$disease),
                        paste0(i[[1]]$disease," Former New"),paste0(i[[2]]$disease," Former")),
         col=c(point1,point2,point1,point2),lwd=c(2,2,2,2),lty=c(1,1,2,2)),
         legend(x=.01,y=ymax,c(paste0(i[[1]]$disease," New"),paste0(i[[2]]$disease),
                               paste0(i[[1]]$disease," Former New"),paste0(i[[2]]$disease," Former"),
                               paste0("Upper bound is ",real_ymax)),
                col=c(point1,point2,point1,point2,NA),lwd=c(2,2,2,2,NA),lty=c(1,1,2,2,NA))
  )
  
  
}## end loop over causes to compare

dev.off()






