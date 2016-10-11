## Plot the relative risk curves for various causes from alcohol

rm(list=ls())
library(foreign); library(reshape); library(lattice); library(latticeExtra); library(MASS);library(scales)


# For testing purposes, set argument values manually if in windows
if (Sys.info()["sysname"] == "Windows") {
  root <- "J:/"    
  code.dir <- "C:/Users//Documents/repos/drugs_alcohol/rr"
} else {
  root <- "/home/j/"            
  user <- Sys.getenv("USER")
  code.dir <- paste0("/ihme/code/risk/",user,"/drugs_alcohol/rr")
}

levels <- c(.25,20,40,60,80,150)

cause_cw <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/meta/cause_crosswalk.csv"),stringsAsFactors = F)


MVA_male = list ( disease= "Motor Vehicle Accidents - Morbidity - MEN",
                  RRCurrent =function(x,beta) ifelse(x>=0,ifelse(x>=20,(((exp(beta[3]*(((x-20)+ 0.0039997100830078)/100)^2)))+((exp(beta[3]*(((x+20)+ 0.0039997100830078)/100)^2))))/2,(exp(0)+((exp(beta[3]*(((x+20)+ 0.0039997100830078)/100)^2))))/2),0),
                  betaCurrent = c(0,0, 3.292589, 0.20885053),
                  covBetaCurrent = matrix(c(0,0,0,0, 0,0,0,0, 0,0,0.03021426,0,  0,0,0,0),4,4),
                  lnRRFormer= 0,
                  varLnRRFormer= 0)

## make female same as male to not break code
MVA_female = list ( disease= "Motor Vehicle Accidents - Morbidity - WOMEN",
                    RRCurrent =function(x,beta) ifelse(x>=0,ifelse(x>=20,(((exp(beta[3]*(((x-20)+ 0.0039997100830078)/100)^2)))+((exp(beta[3]*(((x+20)+ 0.0039997100830078)/100)^2))))/2,(exp(0)+((exp(beta[3]*(((x+20)+ 0.0039997100830078)/100)^2))))/2),0),
                    betaCurrent = c(0,0, 3.292589, 0.20885053),
                    covBetaCurrent = matrix(c(0,0,0,0, 0,0,0,0, 0,0,0.03021426,0,  0,0,0,0),4,4),
                    lnRRFormer= 0,
                    varLnRRFormer= 0)

####### NON-MVA morbidity #########
####### NON-MVA morbidity #########

##### MALE #######
NONMVA_male = list(disease= "NON-Motor Vehicle Accidents - Morbidity - MEN",
                   RRCurrent =function(x,beta) ifelse(x>=0,ifelse(x>=20,(exp(beta[1]*(((x-20+ 0.0039997100830078)/100)^0.5))+exp(beta[1]*(((x+20+ 0.0039997100830078)/100)^0.5)))/2,(exp(0)+exp(beta[1]*(((x+20+ 0.0039997100830078)/100)^0.5)))/2 ),0),
                   betaCurrent = c(2.187789, 0 ,0, 1),
                   covBetaCurrent = matrix(c(0.0627259,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),4,4),
                   lnRRFormer= 0,
                   varLnRRFormer= 0)

#### FEMALE ####
NONMVA_female = list(disease="NON-Motor Vehicle Accidents - Morbidity - WOMEN",
                     RRCurrent =function(x,beta) ifelse(x>=0,ifelse(x>=20,(exp(beta[1]*((((x*1.5)-20+ 0.0039997100830078)/100)^0.5))+exp(beta[1]*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2,(exp(0)+exp(beta[1]*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2 ),0),
                     betaCurrent = c(2.187789, 0 ,0, 1),
                     covBetaCurrent = matrix(c(0.0627259,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),4,4),
                     lnRRFormer= 0,
                     varLnRRFormer= 0)

################ Creating a list of all the diseases ####################

inj_relativeriskmale = list(MVA_male ,  NONMVA_male  )

inj_relativeriskfemale = list(MVA_female,NONMVA_female  )




## Loop through the different relative risk code files
causes <- c("chronic","ihd","ischemicstroke","inj","russia","Russia_RR_IHD","Russia_RR_ISC_STROKE")
#causes <- c("chronic","inj","russia","Russia_RR_IHD","Russia_RR_ISC_STROKE")

d <- list()

for (ccc in causes) {
  cat(paste(ccc, "\n")); flush.console()
  
  ## GET RELATIVE RISKS
  if (ccc %in% c("russia","chronic")) source(paste0(code.dir, "/03_1_", ccc, "RR.R"))
  if (ccc == "inj") {
    relativeriskmale <- inj_relativeriskmale
    relativeriskfemale <- inj_relativeriskfemale
  }
  if (ccc %in% c("Russia_RR_IHD","Russia_RR_ISC_STROKE")) source(paste0(code.dir,"/",ccc,".R"))
  
  if (ccc %in% c("russia","chronic","inj","Russia_RR_ISC_STROKE","Russia_RR_IHD")) {
    if (ccc == "russia") {
      relativeriskmale <- relativeriskmale[1:5]
      relativeriskfemale <- relativeriskfemale[1:5]
    }
    if (ccc %in% c("russia","Russia_RR_ISC_STROKE","Russia_RR_IHD")) {
      for (i in 1:length(relativeriskmale)) {
        relativeriskmale[[i]]$disease <- paste0("Russia, ",relativeriskmale[[i]]$disease)
        relativeriskfemale[[i]]$disease <- paste0("Russia, ",relativeriskfemale[[i]]$disease)
      }
    }
    for (i in 1:length(relativeriskmale)) {
      cat(paste(i," ",relativeriskmale[[i]]$disease, "\n")); flush.console()
      a <- NULL
      if (i == 1 & (grepl("Russia, Ischemic Stroke",relativeriskmale[[i]]$disease) | grepl("Russia, IHD Mortality",relativeriskmale[[i]]$disease))) a <- "15-34"
      if (i == 2 & (grepl("Russia, Ischemic Stroke",relativeriskmale[[i]]$disease) | grepl("Russia, IHD Mortality",relativeriskmale[[i]]$disease))) a <- "35-64"
      if (i == 3 & (grepl("Russia, Ischemic Stroke",relativeriskmale[[i]]$disease) | grepl("Russia, IHD Mortality",relativeriskmale[[i]]$disease))) a <- "65+"
      
      
      
      ## get draws
      B <- 1000
      
      betam <- mvrnorm(B, mu = relativeriskmale[[i]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
      betaf <- mvrnorm(B, mu = relativeriskfemale[[i]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)
      
      ## draw random sample of log relative risk for former drinkers
      lnRRm <- rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer))
      lnRRf <- rnorm(B,mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer))
      
      ## get point estimate curves
      RRfuncm <- function(x) {
        relativeriskmale[[i]]$RRCurrent(x, beta = relativeriskmale[[i]]$betaCurrent)
      }
      RRfuncf <- function(x) {
        relativeriskfemale[[i]]$RRCurrent(x, beta = relativeriskfemale[[i]]$betaCurrent)
      }
      
      ## get upper and lower
      CI <- data.frame(alc=c(levels), meanm = rep(NA,length(levels)),meanf = rep(NA,length(levels)),upperm = rep(NA,length(levels)), lowerm=rep(NA,length(levels)), upperf = rep(NA,length(levels)), lowerf = rep(NA,length(levels)))
      for (j in 1:length(levels)) {
        CI$meanm[j] <- RRfuncm(levels[j])
        CI$meanf[j] <- RRfuncf(levels[j])
        CI$upperm[j] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$upperf[j] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$lowerm[j] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(levels[j],beta=x)} )), c(.025))
        CI$lowerf[j] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(levels[j],beta=x)} )), c(.025))
      }
    
      
      frmr <- data.frame(alc="former",
                         meanm=exp(relativeriskmale[[i]]$lnRRFormer),
                         meanf=exp(relativeriskfemale[[i]]$lnRRFormer),
                         upperm= exp(quantile(rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer)),c(.975))),
                         lowerm = exp(quantile(rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer)),c(.025))),
                         upperf = exp(quantile(rnorm(B, mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer)),c(.975))),
                         lowerf =exp(quantile(rnorm(B, mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer)),c(.025)))
                         )
      CI <- rbind(CI,frmr)
      CI$disease <- paste0(relativeriskmale[[i]]$disease)
      
      ## some formatting
      CI$mortmorb[grepl("Morbidity",CI$disease)] <- "Morbidity"
      CI$mortmorb[grepl("Mortality",CI$disease)] <- "Mortality"
      CI$disease <- gsub(" - Morbidity","",CI$disease)
      CI$disease <- gsub(" - Mortality","",CI$disease)
      CI$mortmorb[is.na(CI$mortmorb)] <- "both"
      CI <- melt(CI,id.vars=c("alc","disease","mortmorb"),variable.name="metric",value.name="rr")
      setnames(CI,c("variable","value"),c("metric","rr"))
      CI$sex[grepl("meanm",CI$metric) | grepl("lowerm",CI$metric) | grepl("upperm",CI$metric)] <- "male"
      CI$sex[grepl("meanf",CI$metric) | grepl("lowerf",CI$metric) | grepl("upperf",CI$metric)] <- "female"
      CI$metric <- as.character(CI$metric)
      for (drp in c("mean","upper","lower")) {
        CI$metric[grepl(drp,CI$metric)] <- drp
      }
      CI$disease <- gsub(" - MEN","",CI$disease)
      CI <- dcast(CI,alc + disease + mortmorb + sex ~ metric, value.var="rr")
      CI$age[!grepl("Age",CI$disease)] <- "All"
      if (!is.null(a)) CI$age <- a
      
      d[[paste0(relativeriskmale[[i]]$disease)]] <- CI
    }
  }
  
  
  ### IHD/Ischemic stroke
  if (ccc %in% c("ihd","ischemicstroke")) {
    source(paste0(code.dir,"/",ccc,"RR.R"))
    
    ages <- c(1,2,3)
    ages_long <- c("15-34","35-64","65+")
    for (i in ages) {
      cat(paste("age",i," ",ccc, "\n")); flush.console()
      
      RRfunc_m_mb <- function(x) {
        relativeriskmale[[1+2*(i-1)]]$RRCurrent(x, beta = relativeriskmale[[1+2*(i-1)]]$betaCurrent)
      }
      RRfunc_m_mt <- function(x) {
        relativeriskmale[[2+2*(i-1)]]$RRCurrent(x, beta = relativeriskmale[[2+2*(i-1)]]$betaCurrent)
      }
      RRfunc_f_mb <- function(x) {
        relativeriskfemale[[1+2*(i-1)]]$RRCurrent(x, beta = relativeriskfemale[[1+2*(i-1)]]$betaCurrent)
      }
      RRfunc_f_mt <- function(x) {
        relativeriskfemale[[2+2*(i-1)]]$RRCurrent(x, beta = relativeriskfemale[[2+2*(i-1)]]$betaCurrent)
      }
      
      
      B <- 1000
      
      beta_m_mt <- mvrnorm(B, mu = relativeriskmale[[2+2*(i-1)]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
      beta_m_mb <- mvrnorm(B, mu = relativeriskmale[[1+2*(i-1)]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
      
      beta_f_mt <- mvrnorm(B, mu = relativeriskfemale[[2+2*(i-1)]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)
      beta_f_mb <- mvrnorm(B, mu = relativeriskfemale[[1+2*(i-1)]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)
      

      CI <- data.frame(alc=c(levels), meanm_mb = rep(NA,length(levels)),meanm_mt = rep(NA,length(levels)),meanf_mb = rep(NA,length(levels)),
                       meanf_mt = rep(NA,length(levels)), upperm_mb = rep(NA,length(levels)),upperm_mt = rep(NA,length(levels)), 
                       lowerm_mb=rep(NA,length(levels)),lowerm_mt=rep(NA,length(levels)), upperf_mb = rep(NA,length(levels)),upperf_mt = rep(NA,length(levels)),
                       lowerf_mb = rep(NA,length(levels)),lowerf_mt = rep(NA,length(levels)))
      for (j in 1:length(levels)) {
        
        CI$upperm_mb[j] <- quantile((apply(beta_m_mb, 1, function(x) {relativeriskmale[[1+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$lowerm_mb[j] <- quantile((apply(beta_m_mb, 1, function(x) {relativeriskmale[[1+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.025))
        
        CI$upperm_mt[j] <- quantile((apply(beta_m_mt, 1, function(x) {relativeriskmale[[2+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$lowerm_mt[j] <- quantile((apply(beta_m_mt, 1, function(x) {relativeriskmale[[2+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.025))
        
        CI$upperf_mb[j] <- quantile((apply(beta_f_mb, 1, function(x) {relativeriskfemale[[1+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$lowerf_mb[j] <- quantile((apply(beta_f_mb, 1, function(x) {relativeriskfemale[[1+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.025))
        
        CI$upperf_mt[j] <- quantile((apply(beta_f_mt, 1, function(x) {relativeriskfemale[[2+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.975))
        CI$lowerf_mt[j] <- quantile((apply(beta_f_mt, 1, function(x) {relativeriskfemale[[2+2*(i-1)]]$RRCurrent(levels[j],beta=x)} )), c(.025))
        
        CI$meanm_mb[j] <- RRfunc_m_mb(levels[j])
        CI$meanm_mt[j] <- RRfunc_m_mt(levels[j])
          
        CI$meanf_mb[j] <- RRfunc_f_mb(levels[j])
        CI$meanf_mt[j] <- RRfunc_f_mt(levels[j])
      }

      
      frmr <- data.frame(alc="former", meanm_mb = exp(relativeriskmale[[1+2*(i-1)]]$lnRRFormer),
                         meanm_mt = exp(relativeriskmale[[2+2*(i-1)]]$lnRRFormer),
                         meanf_mb = exp(relativeriskfemale[[1+2*(i-1)]]$lnRRFormer),
                         meanf_mt = exp(relativeriskfemale[[2+2*(i-1)]]$lnRRFormer), 
                         upperm_mb = exp(quantile(rnorm(B, mean = relativeriskmale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[1+2*(i-1)]]$varLnRRFormer)),c(.975))),
                         upperm_mt = exp(quantile(rnorm(B, mean = relativeriskmale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[2+2*(i-1)]]$varLnRRFormer)),c(.975))), 
                         lowerm_mb= exp(quantile(rnorm(B, mean = relativeriskmale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[1+2*(i-1)]]$varLnRRFormer)),c(.025))),
                         lowerm_mt= exp(quantile(rnorm(B, mean = relativeriskmale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[2+2*(i-1)]]$varLnRRFormer)),c(.025))), 
                         upperf_mb = exp(quantile(rnorm(B, mean = relativeriskfemale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[1+2*(i-1)]]$varLnRRFormer)),c(.975))),
                         upperf_mt = exp(quantile(rnorm(B, mean = relativeriskfemale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[2+2*(i-1)]]$varLnRRFormer)),c(.975))),
                         lowerf_mb = exp(quantile(rnorm(B, mean = relativeriskfemale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[1+2*(i-1)]]$varLnRRFormer)),c(.025))),
                         lowerf_mt =exp(quantile(rnorm(B, mean = relativeriskfemale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[2+2*(i-1)]]$varLnRRFormer)),c(.025)))
                         )
        
      CI <- rbind(CI,frmr)
      CI$disease <- paste0(relativeriskmale[[1+2*(i-1)]]$disease)
      ## reshape so morbidity/mortality long here
      CI$disease <- gsub(" - Morbidity","",CI$disease)
      CI$disease <- gsub(" - Mortality","",CI$disease)
      CI <- melt(CI,id.vars=c("alc","disease"),variable.name="metric",value.name="rr")
      setnames(CI,c("variable","value"),c("metric","rr"))
      CI$mortmorb[grepl("_mb",CI$metric)] <- "Morbidity"
      CI$mortmorb[grepl("_mt",CI$metric)] <- "Mortality"
      CI$sex[grepl("m_",CI$metric)] <- "male"
      CI$sex[grepl("f_",CI$metric)] <- "female"
      for (drp in c("m_mb","f_mb","m_mt","f_mt")) {
        CI$metric <- gsub(drp,"",CI$metric)
      }
      CI <- dcast(CI,alc + disease + mortmorb + sex ~ metric, value.var="rr")
      CI$age <- ages_long[i]
      
      
      d[[paste0(relativeriskmale[[1+2*(i-1)]]$disease)]] <- CI
      
    } ## age loop
  } ## ihd/is loop
  
  
}

## make male breast cancer 0's, can drop later
l <- length(d)
ns <- names(d)
d <- rbindlist(d)
d <- as.data.frame(d)
d$disease <- gsub(" - MEN -","",d$disease)
d$disease <- gsub(" Age_15-34","",d$disease)
d$disease <- gsub(" Age_35-64","",d$disease)
d$disease <- gsub(" Age 65 +","",d$disease,fixed=T)
d$disease <- gsub(" Ages 15-34","",d$disease)
d$disease <- gsub(" Ages 35-64","",d$disease)
d$disease <- gsub(" Ages 65+","",d$disease,fixed=T)
d$location <- "All, unless otherwise specified"
d$location[grepl("Russia",d$disease)] <- "Russia"
d$disease[d$disease == "Russia, Stroke"] <- "Russia, Hemorrhagic Stroke"
d$disease <- gsub("Russia, ","",d$disease)
d <- d[!(d$disease=="Breast Cancer" & d$sex == "male"),]
cause_cw$cause[cause_cw$cause == "IHD "] <- "IHD"
setnames(d,"disease","cause")

d <- merge(d,cause_cw,all.x=T)

d <- d[,c("cause","acause","location","sex","age","mortmorb","alc","mean","lower","upper")]

d <- d[order(d$cause,d$acause,d$location,d$sex,d$age,d$mortmorb,as.numeric(d$alc)),]

write.csv(d,paste0(root,"/WORK/05_risk/risks/drugs_alcohol/diagnostics/RR_table_collab.csv"),row.names=F)

