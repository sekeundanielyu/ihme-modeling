
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



  ####### MVA morbidity #########
  ####### MVA morbidity #########
  
  RRcap <- 85
  
  ##### MALE #######
  
  RRmvama =function(x,beta1,beta2,beta3,beta4) ifelse(x>=0,ifelse(x>=20,(((exp(beta3*(((x-20)+ 0.0039997100830078)/100)^2)))+((exp(beta3*(((x+20)+ 0.0039997100830078)/100)^2))))/2,(exp(0)+((exp(beta3*(((x+20)+ 0.0039997100830078)/100)^2))))/2),0)
  mvamabetas = c(0,0, 3.292589, 0.20885053)
  mvamacovar = matrix(c(0,0,0,0, 0,0,0,0, 0,0,0.03021426,0,  0,0,0,0),4,4)
  lnRRmvamaform= 0
  lnRRmvamaformvar= 0
  MVA_male = list ("Motor Vehicle Accidents - Morbidity - MEN", RRmvama, mvamabetas, mvamacovar,lnRRmvamaform,lnRRmvamaformvar)
  
  RRmvamacap = function(x,beta1,beta2,beta3,beta4) {ifelse(x<RRcap,RRmvama(x,beta1,beta2,beta3,beta4),RRmvama(RRcap,beta1,beta2,beta3,beta4)) }
  MVA_male = list ("Motor Vehicle Accidents - Morbidity - MEN", RRmvamacap, mvamabetas, mvamacovar,lnRRmvamaform,lnRRmvamaformvar)
  names(MVA_male) <- c("disease","RRCurrent","betaCurrent","covBetaCurrent","lnRRFormer","varLnRRFormer")
  ##### FEMALE ######
  ## Note: This is an IHME addition: Use the same RR for male and female morbidity, as opposed to 
  ## using the PCA ratio between males and females to retroactively scale AAFs after the fact
  
  RRmvafe =function(x,beta1,beta2,beta3,beta4) ifelse(x>=0,ifelse(x>=20,(((exp(beta3*(((x-20)+ 0.0039997100830078)/100)^2)))+((exp(beta3*(((x+20)+ 0.0039997100830078)/100)^2))))/2,(exp(0)+((exp(beta3*(((x+20)+ 0.0039997100830078)/100)^2))))/2),0)
  mvafebetas = c(0,0, 3.292589, 0.20885053)
  mvafecovar = matrix(c(0,0,0,0, 0,0,0,0, 0,0,0.03021426,0,  0,0,0,0),4,4)
  lnRRmvafeform= 0
  lnRRmvafeformvar= 0
  MVA_female = list ("Motor Vehicle Accidents - Morbidity - WOMEN", RRmvafe, mvafebetas, mvafecovar,lnRRmvafeform,lnRRmvafeformvar)
  
  RRmvafecap = function(x,beta1,beta2,beta3,beta4) {ifelse(x<RRcap,RRmvafe(x,beta1,beta2,beta3,beta4),RRmvafe(RRcap,beta1,beta2,beta3,beta4)) }
  MVA_female = list ("Motor Vehicle Accidents - Morbidity - WOMEN", RRmvafecap, mvafebetas, mvafecovar,lnRRmvafeform,lnRRmvafeformvar)
  names(MVA_female) <- c("disease","RRCurrent","betaCurrent","covBetaCurrent","lnRRFormer","varLnRRFormer")
  
  
  ####### NON-MVA morbidity #########
  ####### NON-MVA morbidity #########
  
  ##### MALE #######
  
  RRnonmvama =function(x,beta1,beta2,beta3,beta4) ifelse(x>=0,ifelse(x>=20,(exp(beta1*(((x-20+ 0.0039997100830078)/100)^0.5))+exp(beta1*(((x+20+ 0.0039997100830078)/100)^0.5)))/2,(exp(0)+exp(beta1*(((x+20+ 0.0039997100830078)/100)^0.5)))/2 ),0)
  nonmvamabetas = c(2.187789, 0 ,0, 1)
  nonmvamacovar = matrix(c(0.0627259,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),4,4)
  lnRRnonmvamaform= 0
  lnRRnonmvamaformvar= 0
  
  RRnonmvamacap = function(x,beta1,beta2,beta3,beta4) {ifelse(x<RRcap,RRnonmvama(x,beta1,beta2,beta3,beta4),RRnonmvama(RRcap,beta1,beta2,beta3,beta4)) }
  
  NONMVA_male = list ("NON-Motor Vehicle Accidents - Morbidity - MEN", RRnonmvamacap, nonmvamabetas, nonmvamacovar,lnRRnonmvamaform,lnRRnonmvamaformvar)
  names(NONMVA_male) <- c("disease","RRCurrent","betaCurrent","covBetaCurrent","lnRRFormer","varLnRRFormer")
  
  #### FEMALE ####
  
  RRnonmvafe =function(x,beta1,beta2,beta3,beta4) ifelse(x>=0,ifelse(x>=20,(exp(beta1*((((x*1.5)-20+ 0.0039997100830078)/100)^0.5))+exp(beta1*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2,(exp(0)+exp(beta1*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2 ),0)
  nonmvafebetas = c(2.187789, 0 ,0, 1)
  nonmvafecovar = matrix(c(0.0627259,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),4,4)
  lnRRnonmvafeform= 0
  lnRRnonmvafeformvar= 0
  
  RRnonmvafecap = function(x,beta1,beta2,beta3,beta4) {ifelse(x<RRcap,RRnonmvafe(x,beta1,beta2,beta3,beta4),RRnonmvafe(RRcap,beta1,beta2,beta3,beta4)) }
  
  NONMVA_female = list ("NON-Motor Vehicle Accidents - Morbidity - WOMEN", RRnonmvafecap, nonmvafebetas, nonmvafecovar,lnRRnonmvafeform,lnRRnonmvafeformvar)
  names(NONMVA_female) <- c("disease","RRCurrent","betaCurrent","covBetaCurrent","lnRRFormer","varLnRRFormer")
  

################ Creating a list of all the diseases ####################

inj_relativeriskmale = list(MVA_male ,  NONMVA_male  )

inj_relativeriskfemale = list(MVA_female,NONMVA_female  )




	## Loop through the different relative risk code files
  causes <- c("chronic","ihd","ischemicstroke","inj","russia","Russia_RR_IHD","Russia_RR_ISC_STROKE")
 # causes <- c("inj")

    #pdf(paste(root,"WORK/05_risk/risks/drugs_alcohol/diagnostics/RR_plots_",Sys.Date(),".pdf",sep = ""), width=10, height=7)
  pdf(paste("C:/Users/strUser/Desktop/RR_plots_",Sys.Date(),".pdf",sep = ""), width=10, height=7)
  
  
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
    

        ## get draws
        B <- 1000

        betam <- mvrnorm(B, mu = relativeriskmale[[i]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
        betaf <- mvrnorm(B, mu = relativeriskfemale[[i]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)

        ## draw random sample of log relative risk for former drinkers
        if (ccc == "inj") {
          lnRRm <- lnRRf <- rep(1,B)
        } else {
          lnRRm <- rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer))
          lnRRf <- rnorm(B,mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer))
        }
        
        ## get upper and lower
        CI <- data.frame(x=c(0:150), upperm = rep(NA,151), lowerm=rep(NA,151), upperf = rep(NA,151), lowerf = rep(NA,151))
        for (j in 0:150) {
          if (ccc == "inj") {
            CI$upperm[j+1] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(j,beta1=x[1],beta2=x[2],beta3=x[3],beta4=x[4])} )), c(.975))
            CI$upperf[j+1] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(j,beta1=x[1],beta2=x[2],beta3=x[3],beta4=x[4])} )), c(.975))
            CI$lowerm[j+1] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(j,beta1=x[1],beta2=x[2],beta3=x[3],beta4=x[4])} )), c(.025))
            CI$lowerf[j+1] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(j,beta1=x[1],beta2=x[2],beta3=x[3],beta4=x[4])} )), c(.025))
          } else {
            CI$upperm[j+1] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(j,beta=x)} )), c(.975))
            CI$upperf[j+1] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(j,beta=x)} )), c(.975))
            CI$lowerm[j+1] <- quantile((apply(betam, 1, function(x) {relativeriskmale[[i]]$RRCurrent(j,beta=x)} )), c(.025))
            CI$lowerf[j+1] <- quantile((apply(betaf, 1, function(x) {relativeriskfemale[[i]]$RRCurrent(j,beta=x)} )), c(.025))
          }
        }

        ## get point estimate curves
        if (ccc == "inj") {
          RRfuncm <- function(x) {
            relativeriskmale[[i]]$RRCurrent(x, beta1 = relativeriskmale[[i]]$betaCurrent[1],beta2 = relativeriskmale[[i]]$betaCurrent[2],
                                            beta3 = relativeriskmale[[i]]$betaCurrent[3],beta4 = relativeriskmale[[i]]$betaCurrent[4])
          }
          RRfuncf <- function(x) {
            relativeriskfemale[[i]]$RRCurrent(x, beta1 = relativeriskfemale[[i]]$betaCurrent[1],beta2 = relativeriskfemale[[i]]$betaCurrent[2],
                                              beta3 = relativeriskfemale[[i]]$betaCurrent[3],beta4 = relativeriskfemale[[i]]$betaCurrent[4])
          }
        } else {
          RRfuncm <- function(x) {
            relativeriskmale[[i]]$RRCurrent(x, beta = relativeriskmale[[i]]$betaCurrent)
          }
          RRfuncf <- function(x) {
            relativeriskfemale[[i]]$RRCurrent(x, beta = relativeriskfemale[[i]]$betaCurrent)
          }
        }


        if (paste0(sub(" - MEN","",relativeriskmale[[i]]$disease)) != "Breast Cancer") {
        RRformerm <- exp(relativeriskmale[[i]]$lnRRFormer)
        }

        RRformerf <- exp(relativeriskfemale[[i]]$lnRRFormer)
        

        RRformerflower <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer)),c(.025)),2))
        RRformerfupper <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[i]]$lnRRFormer, sd = sqrt(relativeriskfemale[[i]]$varLnRRFormer)),c(.975)),2))
        RRformermupper <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer)),c(.975)),2))
        RRformermlower <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[i]]$lnRRFormer, sd = sqrt(relativeriskmale[[i]]$varLnRRFormer)),c(.025)),2))

        
  ihmemalepoint <- "blue"
  ihmefemalepoint <- "red"
  maleshade <- alpha(ihmemalepoint, .2)
  femaleshade <- alpha(ihmefemalepoint, .2)
  maleshade2 <- alpha(ihmemalepoint,.1)
  femaleshade2 <- alpha(ihmefemalepoint,.1)
        
        from <- .01
        to <- 150
        ymax <- max(RRfuncm(to),RRfuncf(to),CI$upperm,CI$upperf,RRformermupper,RRformerfupper)*1.1
        if (paste0(sub(" - MEN","",relativeriskmale[[i]]$disease)) != "Breast Cancer") {
          curve(RRfuncm,from=from,to=to,main=paste0(sub("- MEN","",relativeriskmale[[i]]$disease), " Relative Risks from Alcohol"),xlab="Alcohol (g/day)",
              ylab="Relative Risk",col="blue",lwd=2,ylim=c(.8,ymax))
          par(new=T)
          curve(RRfuncf,from=from,to=to,col="red",lwd=2,main=paste0(sub("- MEN","",relativeriskmale[[i]]$disease)," Relative Risks from Alcohol"),xlab="Alcohol (g/day)",
              ylab="Relative Risk",ylim=c(.8,ymax))
          abline(h=1,lty=2)
          abline(h=RRformerf,lty=2,lwd=2,col="red")
          abline(h=RRformerm,lty=2,lwd=2,col="blue")
          polygon(c(CI$x, rev(CI$x)), c(CI$upperm, rev(CI$lowerm)),
               col = maleshade, border = NA)
          polygon(c(CI$x, rev(CI$x)), c(CI$upperf, rev(CI$lowerf)),
               col = femaleshade, border = NA)
          polygon(c(c(0,150), c(150,0)), c(RRformerfupper, rev(RRformerflower)),
                  col = femaleshade2, border = NA)
          polygon(c(c(0,150), c(150,0)), c(RRformermupper, rev(RRformermlower)),
                  col = maleshade2, border = NA)
          legend(x=.01,y=ymax,c(paste0(relativeriskmale[[i]]$disease),paste0(relativeriskfemale[[i]]$disease),
          paste0(relativeriskmale[[i]]$disease," Former"),paste0(relativeriskfemale[[i]]$disease," Former")),
              col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
          
          if (max(CI$upperm,CI$upperf) > 50) {
            ymax <- 20
            curve(RRfuncm,from=from,to=to,main=paste0(sub("- MEN","",relativeriskmale[[i]]$disease), " Relative Risks from Alcohol","\n rescaled due to high upper bound"),xlab="Alcohol (g/day)",
                  ylab="Relative Risk",col="blue",lwd=2,ylim=c(.8,ymax))
            par(new=T)
            curve(RRfuncf,from=from,to=to,col="red",lwd=2,main=paste0(sub("- MEN","",relativeriskmale[[i]]$disease)," Relative Risks from Alcohol","\n rescaled due to high upper bound"),xlab="Alcohol (g/day)",
                  ylab="Relative Risk",ylim=c(.8,ymax))
            abline(h=1,lty=2)
            abline(h=RRformerf,lty=2,lwd=2,col="red")
            abline(h=RRformerm,lty=2,lwd=2,col="blue")
            polygon(c(CI$x, rev(CI$x)), c(CI$upperm, rev(CI$lowerm)),
                    col = maleshade, border = NA)
            polygon(c(CI$x, rev(CI$x)), c(CI$upperf, rev(CI$lowerf)),
                    col = femaleshade, border = NA)
            polygon(c(c(0,150), c(150,0)), c(RRformerfupper, rev(RRformerflower)),
                    col = femaleshade2, border = NA)
            polygon(c(c(0,150), c(150,0)), c(RRformermupper, rev(RRformermlower)),
                    col = maleshade2, border = NA)
            legend(x=.01,y=ymax,c(paste0(relativeriskmale[[i]]$disease),paste0(relativeriskfemale[[i]]$disease),
                                  paste0(relativeriskmale[[i]]$disease," Former"),paste0(relativeriskfemale[[i]]$disease," Former")),
                   col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
          }

        }

         if (paste0(sub(" - MEN","",relativeriskmale[[i]]$disease)) == "Breast Cancer") {
          curve(RRfuncf,from=from,to=to,main=paste0(sub("- MEN","",relativeriskmale[[i]]$disease)),xlab="Alcohol (g/day)",
              ylab="Relative Risk",col="red",lwd=2,ylim=c(.8,2.7))
          polygon(c(CI$x, rev(CI$x)), c(CI$upperf, rev(CI$lowerf)),
                   col = femaleshade, border = NA)
          abline(h=1,lty=2)
          abline(h=RRformerf,lty=2,lwd=2,col="red")
          legend(x=.01,y=2.5,c("No RR for Males",paste0(relativeriskfemale[[i]]$disease),paste0(relativeriskfemale[[i]]$disease," Former")),
              col=c("blue","red","red"),lwd=c(2,2,2),lty=c(1,1,2))
        }
        
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

        RR_fmr_m_mt <- exp(relativeriskmale[[2+2*(i-1)]]$lnRRFormer)
        RR_fmr_m_mb <- exp(relativeriskmale[[1+2*(i-1)]]$lnRRFormer)
        RR_fmr_f_mt <- exp(relativeriskfemale[[2+2*(i-1)]]$lnRRFormer)
        RR_fmr_f_mb <- exp(relativeriskfemale[[1+2*(i-1)]]$lnRRFormer)
        
        B <- 1000
        
        beta_m_mt <- mvrnorm(B, mu = relativeriskmale[[2+2*(i-1)]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
        beta_m_mb <- mvrnorm(B, mu = relativeriskmale[[1+2*(i-1)]]$betaCurrent, Sigma = relativeriskmale[[i]]$covBetaCurrent)
        
        beta_f_mt <- mvrnorm(B, mu = relativeriskfemale[[2+2*(i-1)]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)
        beta_f_mb <- mvrnorm(B, mu = relativeriskfemale[[1+2*(i-1)]]$betaCurrent, Sigma = relativeriskfemale[[i]]$covBetaCurrent)
        
        CI <- data.frame(x=c(0:150), upper_m_mb = rep(NA,151), lower_m_mb=rep(NA,151), upper_m_mt = rep(NA,151), lower_m_mt = rep(NA,151), 
                         upper_f_mb = rep(NA,151), lower_f_mb = rep(NA,151), upper_f_mt = rep(NA,151), lower_f_mt = rep(NA,151))
        for (j in 0:150) {
          CI$upper_m_mb[j+1] <- quantile((apply(beta_m_mb, 1, function(x) {relativeriskmale[[1+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.975))
          CI$lower_m_mb[j+1] <- quantile((apply(beta_m_mb, 1, function(x) {relativeriskmale[[1+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.025))
   
          CI$upper_m_mt[j+1] <- quantile((apply(beta_m_mt, 1, function(x) {relativeriskmale[[2+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.975))
          CI$lower_m_mt[j+1] <- quantile((apply(beta_m_mt, 1, function(x) {relativeriskmale[[2+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.025))
         
          CI$upper_f_mb[j+1] <- quantile((apply(beta_f_mb, 1, function(x) {relativeriskfemale[[1+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.975))
          CI$lower_f_mb[j+1] <- quantile((apply(beta_f_mb, 1, function(x) {relativeriskfemale[[1+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.025))
          
          CI$upper_f_mt[j+1] <- quantile((apply(beta_f_mt, 1, function(x) {relativeriskfemale[[2+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.975))
          CI$lower_f_mt[j+1] <- quantile((apply(beta_f_mt, 1, function(x) {relativeriskfemale[[2+2*(i-1)]]$RRCurrent(j,beta=x)} )), c(.025))
        }

        fmr_upper_m_mb <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[1+2*(i-1)]]$varLnRRFormer)),c(.975)),2))
        fmr_lower_m_mb <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[1+2*(i-1)]]$varLnRRFormer)),c(.025)),2))
        fmr_upper_m_mt <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[2+2*(i-1)]]$varLnRRFormer)),c(.975)),2))
        fmr_lower_m_mt <- exp(rep(quantile(rnorm(B, mean = relativeriskmale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskmale[[2+2*(i-1)]]$varLnRRFormer)),c(.025)),2))
        fmr_upper_f_mb <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[1+2*(i-1)]]$varLnRRFormer)),c(.975)),2))
        fmr_lower_f_mb <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[1+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[1+2*(i-1)]]$varLnRRFormer)),c(.025)),2))
        fmr_upper_f_mt <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[2+2*(i-1)]]$varLnRRFormer)),c(.975)),2))
        fmr_lower_f_mt <- exp(rep(quantile(rnorm(B, mean = relativeriskfemale[[2+2*(i-1)]]$lnRRFormer, sd = sqrt(relativeriskfemale[[2+2*(i-1)]]$varLnRRFormer)),c(.025)),2))
        
        
        
        from <- .01
        to <- 150
        ymin <- 0.35
        
        ihmemalepoint <- "blue"
        ihmefemalepoint <- "red"
        maleshade <- alpha(ihmemalepoint, .2)
        femaleshade <- alpha(ihmefemalepoint, .2)
        maleshade2 <- alpha(ihmemalepoint, .1)
        femaleshad2 <- alpha(ihmefemalepoint, .1)
        
        
        ## mortality
        curve(RRfunc_m_mt,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[2+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[2+2*(i-1)]]$disease),"",", Mortality"))),xlab="Alcohol (g/day)",
              ylab="Relative Risk",col=ihmemalepoint,lwd=2,lty=1,ylim=c(ymin,max(CI$upper_m_mt,RR_fmr_m_mt,CI$upper_f_mt,RR_fmr_f_mt)))
        par(new=T)
        curve(RRfunc_f_mt,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[2+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[2+2*(i-1)]]$disease),"",", Mortality"))),xlab="Alcohol (g/day)",
              ylab="Relative Risk", col=ihmefemalepoint,lwd=2,lty=1,ylim=c(ymin,max(CI$upper_m_mt,RR_fmr_m_mt,CI$upper_f_mt,RR_fmr_f_mt)))
        polygon(c(CI$x, rev(CI$x)), c(CI$upper_m_mt, rev(CI$lower_m_mt)),
                col = maleshade, border = NA)
        polygon(c(CI$x, rev(CI$x)), c(CI$upper_f_mt, rev(CI$lower_f_mt)),
                col = femaleshade, border = NA)
        abline(h=1,lty=2)
        abline(h=RR_fmr_m_mt,lty=2,lwd=2,col=ihmemalepoint)
        polygon(c(c(0,150), c(150,0)), c(fmr_upper_m_mt, rev(fmr_lower_m_mt)),
                col = maleshade2, border = NA)
        abline(h=RR_fmr_f_mt,lty=2,lwd=2,col=ihmefemalepoint)
        polygon(c(c(0,150), c(150,0)), c(fmr_upper_f_mt, rev(fmr_lower_f_mt)),
                col = femaleshade2, border = NA)
        legend("topleft",c(paste0(relativeriskmale[[2+2*(i-1)]]$disease),paste0(relativeriskfemale[[2+2*(i-1)]]$disease),
                              paste0(relativeriskmale[[2+2*(i-1)]]$disease," Former"),paste0(relativeriskfemale[[2+2*(i-1)]]$disease," Former")),
               col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
        
        if (max(CI$upper_m_mt,RR_fmr_m_mt,CI$upper_f_mt,RR_fmr_f_mt) > 40) {
          curve(RRfunc_m_mt,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[2+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[2+2*(i-1)]]$disease),"",", Mortality"),"\n rescaled due to high upper bound")),xlab="Alcohol (g/day)",
                ylab="Relative Risk",col=ihmemalepoint,lwd=2,lty=1,ylim=c(ymin,20))
          par(new=T)
          curve(RRfunc_f_mt,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[2+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[2+2*(i-1)]]$disease),"",", Mortality"),"\n rescaled due to high upper bound")),xlab="Alcohol (g/day)",
                ylab="Relative Risk", col=ihmefemalepoint,lwd=2,lty=1,ylim=c(ymin,20))
          polygon(c(CI$x, rev(CI$x)), c(CI$upper_m_mt, rev(CI$lower_m_mt)),
                  col = maleshade, border = NA)
          polygon(c(CI$x, rev(CI$x)), c(CI$upper_f_mt, rev(CI$lower_f_mt)),
                  col = femaleshade, border = NA)
          abline(h=1,lty=2)
          abline(h=RR_fmr_m_mt,lty=2,lwd=2,col=ihmemalepoint)
          polygon(c(c(0,150), c(150,0)), c(fmr_upper_m_mt, rev(fmr_lower_m_mt)),
                  col = maleshade2, border = NA)
          abline(h=RR_fmr_f_mt,lty=2,lwd=2,col=ihmefemalepoint)
          polygon(c(c(0,150), c(150,0)), c(fmr_upper_f_mt, rev(fmr_lower_f_mt)),
                  col = femaleshade2, border = NA)
          legend("topleft",c(paste0(relativeriskmale[[2+2*(i-1)]]$disease),paste0(relativeriskfemale[[2+2*(i-1)]]$disease),
                             paste0(relativeriskmale[[2+2*(i-1)]]$disease," Former"),paste0(relativeriskfemale[[2+2*(i-1)]]$disease," Former")),
                 col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
          
        }
        
        
        ## morbidity
        curve(RRfunc_m_mb,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[1+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[1+2*(i-1)]]$disease),"",", Mortality"))),xlab="Alcohol (g/day)",
              ylab="Relative Risk",col=ihmemalepoint,lwd=2,lty=1,ylim=c(ymin,max(CI$upper_m_mb,RR_fmr_m_mb,CI$upper_f_mb,RR_fmr_f_mb)))
        par(new=T)
        curve(RRfunc_f_mb,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[1+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[1+2*(i-1)]]$disease),"",", Mortality"))),xlab="Alcohol (g/day)",
              ylab="Relative Risk", col=ihmefemalepoint,lwd=2,lty=1,ylim=c(ymin,max(CI$upper_m_mb,RR_fmr_m_mb,CI$upper_f_mb,RR_fmr_f_mb)))
        polygon(c(CI$x, rev(CI$x)), c(CI$upper_m_mb, rev(CI$lower_m_mb)),
                col = maleshade, border = NA)
        polygon(c(CI$x, rev(CI$x)), c(CI$upper_f_mb, rev(CI$lower_f_mb)),
                col = femaleshade, border = NA)
        abline(h=1,lty=2)
        abline(h=RR_fmr_m_mb,lty=2,lwd=2,col=ihmemalepoint)
        polygon(c(c(0,150), c(150,0)), c(fmr_upper_m_mb, rev(fmr_lower_m_mb)),
                col = maleshade2, border = NA)
        abline(h=RR_fmr_f_mb,lty=2,lwd=2,col=ihmefemalepoint)
        polygon(c(c(0,150), c(150,0)), c(fmr_upper_f_mb, rev(fmr_lower_f_mb)),
                col = femaleshade2, border = NA)
        legend("topleft",c(paste0(relativeriskmale[[1+2*(i-1)]]$disease),paste0(relativeriskfemale[[1+2*(i-1)]]$disease),
                           paste0(relativeriskmale[[1+2*(i-1)]]$disease," Former"),paste0(relativeriskfemale[[1+2*(i-1)]]$disease," Former")),
               col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
        
        if (max(CI$upper_m_mb,RR_fmr_m_mb,CI$upper_f_mb,RR_fmr_f_mb) > 40) {
          curve(RRfunc_m_mb,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[1+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[1+2*(i-1)]]$disease),"",", Mortality"),"\n rescaled due to high upper bound")),xlab="Alcohol (g/day)",
                ylab="Relative Risk",col=ihmemalepoint,lwd=2,lty=1,ylim=c(ymin,20))
          par(new=T)
          curve(RRfunc_f_mb,from=from,to=to,main=sub("- MEN","",paste0(relativeriskmale[[1+2*(i-1)]]$disease,ifelse(grepl("Morbidity",relativeriskmale[[1+2*(i-1)]]$disease),"",", Mortality"),"\n rescaled due to high upper bound")),xlab="Alcohol (g/day)",
                ylab="Relative Risk", col=ihmefemalepoint,lwd=2,lty=1,ylim=c(ymin,20))
          polygon(c(CI$x, rev(CI$x)), c(CI$upper_m_mb, rev(CI$lower_m_mb)),
                  col = maleshade, border = NA)
          polygon(c(CI$x, rev(CI$x)), c(CI$upper_f_mb, rev(CI$lower_f_mb)),
                  col = femaleshade, border = NA)
          abline(h=1,lty=2)
          abline(h=RR_fmr_m_mb,lty=2,lwd=2,col=ihmemalepoint)
          polygon(c(c(0,150), c(150,0)), c(fmr_upper_m_mb, rev(fmr_lower_m_mb)),
                  col = maleshade2, border = NA)
          abline(h=RR_fmr_f_mb,lty=2,lwd=2,col=ihmefemalepoint)
          polygon(c(c(0,150), c(150,0)), c(fmr_upper_f_mb, rev(fmr_lower_f_mb)),
                  col = femaleshade2, border = NA)
          legend("topleft",c(paste0(relativeriskmale[[1+2*(i-1)]]$disease),paste0(relativeriskfemale[[1+2*(i-1)]]$disease),
                             paste0(relativeriskmale[[1+2*(i-1)]]$disease," Former"),paste0(relativeriskfemale[[1+2*(i-1)]]$disease," Former")),
                 col=c("blue","red","blue","red"),lwd=c(2,2,2,2),lty=c(1,1,2,2))
          
        }
      
      }
    }
}
  dev.off()
