

rm(list=ls()); library(foreign); library(MASS); library(scales)
if (Sys.info()[1== 'Windows') {
  username <- "mcoates"
  root <- "J:/"
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
}


####### Hemorrhagic Stroke - Morbidity ##########
#### male ####
hemorrhagicstrokemorbiditymale = list(disease = "Hemorrhagic Stroke - Morbidity - MEN",
                                      RRCurrent = function(x, beta){ifelse(x >= 0,
                                                                           ifelse(x < 1, 1 + x * (exp(beta[2] * (1 + 0.0028572082519531)/ 100) - 1),
                                                                                  exp(beta[2] * (x + 0.0028572082519531) / 100)), 0)},
                                      betaCurrent = c(0,0.7695021,0,0), 
                                      covBetaCurrent = matrix(c(0,0,0,0,0,0.1570753^2,0,0,0,0,0,0,0,0,0,0),4,4),
                                      lnRRFormer = log(1.33),
                                      varLnRRFormer = 0.195728^2)
#### female ####
##### remark:
##### this function includes a sqrt(x)*ln(x) function.
##### Therefore, the beta2 coefficient will represent this factor and not the
##### coefficient for x^1.


hemorrhagicstrokemorbidityfemale = list(disease = "Hemorrhagic Stroke - Morbidity - WOMEN",
                                        RRCurrent = function(x, beta){ ifelse(x >= 0,
                                                                              ifelse(x < 1, 1 + x * (exp(beta[1] * ((1 + 0.0028572082519531) / 100)^0.5 +
                                                                                                           beta[2] * ((1 + 0.0028572082519531) / 100)^0.5 *
                                                                                                           log((1 + 0.0028572082519531) / 100)) - 1),
                                                                                     exp(beta[1] * ((x + 0.0028572082519531) / 100)^0.5 +
                                                                                           beta[2] * ((x + 0.0028572082519531) / 100)^0.5 *
                                                                                           log((x + 0.0028572082519531) / 100))), 0)},
                                        betaCurrent = c(0.9396292,0.944208,0,0),
                                        covBetaCurrent = matrix(c(0.2571460^2, 0.01587064,0,0,0.01587064,0.1759703^2,0,0,0,0,0,0,0,0,0,0),4,4),
                                        lnRRFormer = log(1.15),
                                        varLnRRFormer = 0.253779^2)


####### Hemorrhagic Stroke - Mortality #########
#### male ####
hemorrhagicstrokemale = list(disease = "Hemorrhagic Stroke - Mortality - MEN", 
                             RRCurrent = function(x, beta){ ifelse(x >= 0,
                                                                   ifelse(x <= 1, 1 - x * (1 - exp(beta[2] * (1 + 0.0028572082519531) / 100)),
                                                                          exp(beta[2] * (x + 0.0028572082519531) / 100)), 0)},
                             betaCurrent = c(0,0.6898937,0,0),
                             covBetaCurrent = matrix(c(0,0,0,0,0,0.1141980^2,0,0,0,0,0,0,0,0,0,0),4,4),
                             lnRRFormer = log(1.33),
                             varLnRRFormer = 0.195728^2)
#### female ####
hemorrhagicstrokefemale = list(disease = "Hemorrhagic Stroke - Mortality - WOMEN", 
                               RRCurrent = function(x, beta){ ifelse(x >= 0,
                                                                     ifelse(x <= 1, 1 - x * (1 - exp(beta[2] * (1 + 0.0028572082519531) / 100)),
                                                                            exp(beta[2] * (x + 0.0028572082519531) / 100)), 0)},
                               betaCurrent = c(0,1.466406,0,0),
                               covBetaCurrent = matrix(c(0,0,0,0,0,0.3544172^2,0,0,0,0,0,0,0,0,0,0),4,4),
                               lnRRFormer = log(1.15),
                               varLnRRFormer = 0.253779^2)


RRlist <- list(hemorrhagicstrokemale=hemorrhagicstrokemale,hemorrhagicstrokefemale=hemorrhagicstrokefemale,hemorrhagicstrokemorbiditymale=hemorrhagicstrokemorbiditymale,
               hemorrhagicstrokemorbidityfemale=hemorrhagicstrokemorbidityfemale)

pdf(paste(root,"/WORK/05_risk/risks/drugs_alcohol/diagnostics/plot_hemorrhagic_RRs_fix",Sys.Date(),".pdf",sep = ""), width=10, height=7)
for (i in RRlist) {
  cat(paste(i$disease)); flush.console()
  ## get draws
  B <- 1000
  
  set.seed(12345)
  beta1 <- mvrnorm(B, mu = i$betaCurrent, Sigma = i$covBetaCurrent)

  ## draw random sample of log relative risk for former drinkers
  set.seed(12345)
  lnRR1 <- rnorm(B, mean = i$lnRRFormer, sd = sqrt(i$varLnRRFormer))

  ## get upper and lower
  CI <- data.frame(x=c(0:150), upper1 = rep(NA,151), lower1=rep(NA,151))
  for (j in 0:150) {
    CI$upper1[j+1] <- quantile((apply(beta1, 1, function(x) {i$RRCurrent(j,beta=x)} )), c(.975))
    CI$lower1[j+1] <- quantile((apply(beta1, 1, function(x) {i$RRCurrent(j,beta=x)} )), c(.025))
  }
  
  ## point estimates
  RRfunc1 <- function(x) {
    i$RRCurrent(x, beta = i$betaCurrent)
  }
  
  RRformer1 <- exp(i$lnRRFormer)

  
  point1 <- "blue"
  shade1 <- alpha(point1, .2)

  
  
  from <- .01
  to <- 150
  ymax = max(unlist(CI[,2:3]))
  if (ymax > 80) {
    ymax <- 80
    real_ymax <- max(unlist(CI[,2:3]))
  } 
  
  curve(RRfunc1,from=from,to=to,main=paste0(i$disease, " Relative Risks from Alcohol"),xlab="Alcohol (g/day)",
        ylab="Relative Risk",col=point1,lwd=2,ylim=c(.8,ymax))
  par(new=T)
  abline(h=1,lty=2)
  abline(h=RRformer1,lty=2,lwd=2,col=point1)
  polygon(c(CI$x, rev(CI$x)), c(CI$upper1, rev(CI$lower1)),
          col = shade1, border = NA)
}

dev.off()





