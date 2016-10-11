######################################################################
## Description: Combine various methods of DDM to get final estimates
######################################################################

  rm(list=ls())
  library(foreign); library(plyr); library(lme4); library(stringr); library(haven); library(readstata13)
  if (Sys.info()[1] == "Linux") {
    root <- "/home/j" 
    user <- Sys.getenv("USER")
    code_dir <- paste0("strPath") 
  } else {
    root <- "J:"
    user <- Sys.getenv("USERNAME")
    code_dir <- paste0("strPath")
  }

## Set local working directory (toggles by GIT user) 
source(paste0(root,"strPath/get_locations.r"))

## set parameters
  end_year <- 2015
  # if we want comparison graphs
  comparison <- T
  comp_code <- paste(code_dir, "/ddm_graphs/compare_ddm.r", sep="")

  source(paste(code_dir, "/functions/space_time.r", sep = "" ))
  
  setwd(paste(root, "/strPath", sep=""))

  codes <- get_locations(level = "estimate")
  region_map <- codes[,c("ihme_loc_id","region_name","super_region_name","level")]


  level_1 <- unique(codes$ihme_loc_id[codes$level_1 == 1]) # All nationals without subnationals
  level_2 <- unique(codes$ihme_loc_id[codes$level_2 == 1]) # All subnationals at the India state level, minus parents
  level_3 <- unique(codes$ihme_loc_id[codes$level_3 == 1]) # All subnationals at the India state/urbanicity level, minus parents 

  keep_level_2 <- unique(codes$ihme_loc_id[codes$level_1 == 0 & codes$level_2 == 1 & codes$level_3 == 0])
  keep_level_3 <- unique(codes$ihme_loc_id[codes$level_1 == 0 & codes$level_3 == 1])
  keep_level_1 <- unique(codes$ihme_loc_id[!(codes$ihme_loc_id %in% keep_level_2) & !(codes$ihme_loc_id %in% keep_level_3)])


######################
## Prep completeness data 
######################

## Read in adult and child completeness
  ddm <- read_dta("d07_child_and_adult_completeness.dta")
  ddm$year <- floor(ddm$year)
  ddm <- ddm[ddm$year >= 1950,]
  ddm <- ddm[order(ddm$iso3_sex_source, ddm$year, ddm$detailed_comp_type),]

## Drop males and females except in SAU and CHN; for all other countries we believe male and female completeness is roughly 
## similar but in SAU they may be different so we treat male-SAU and female-SAU as two different countries 
  ss <- grepl("SAU",ddm$ihme_loc_id) & grepl("VR", ddm$iso3_sex_source)
  ddm <- ddm[(grepl("both", ddm$iso3_sex_source) & !ss) | (!grepl("both", ddm$iso3_sex_source) & ss),]
  
## Drop some outliers
  ddm <- ddm[!(grepl("CHN_44533&&both&&DSP",ddm$iso3_sex_source) & ddm$comp_type == "u5" & ddm$year < 1996),]
  ddm <- ddm[!(ddm$iso3_sex_source == "DOM&&both&&VR" & ddm$comp_type == "u5" & ddm$year > 2009),]
  ddm <- ddm[!(ddm$iso3_sex_source == "MEX_4664&&both&&VR" & ddm$comp_type != "u5" & ddm$year %in% c(1988,1989)),] # Queraotaro? Local ID 2013 = XMW
  ddm <- ddm[!(ddm$iso3_sex_source %in% c("XIR&&both&&SRS","XIU&&both&&SRS") & ddm$comp_type == "u5" & ddm$year < 1990),] # India Urban and Rural? Are we still calculating these?
  ddm <- ddm[!(ddm$iso3_sex_source == "BOL&&both&&VR" & ddm$comp_type == "u5" & ddm$year %in% c(2000,2001,2002,2003)),]
  
## Put comp in log space (this make our ratio symmetric: e.g. 0.5 and 2.0, when logged, carry equal weight) 
  ddm$comp <- log(ddm$comp, 10) 
  
## Split out adult and child comp 
  child <- ddm[ddm$comp_type == "u5", c("ihme_loc_id", "iso3_sex_source", "year", "comp")]
  adult <- ddm[ddm$comp_type != "u5", c("ihme_loc_id", "iso3_sex_source", "year", "comp", "detailed_comp_type", "id")]
  names(adult)[5] <- "comp_type"

## Use loess to generate a full time series of child comp
  years <- 1950:end_year
  child_loess <- ddply(child, c("ihme_loc_id", "iso3_sex_source"),
                       function(x) {
                         cat(paste(x$iso3_sex_source[1], "\n")); flush.console()
                         if (nrow(x) <= 3) { 
                           p <- rep(mean(x$comp), length(years))
                         } else {
                           gaps <- (x$year[-1] - x$year[-length(x$year)])
                           #alpha = max(gaps)*5
                           alpha <- ifelse(grepl("PAN", x$iso3_sex_source[1]), 1, 5)
                           m <- loess(comp ~ year, data=x, control=loess.control(surface="direct"), span=alpha, model=T)
                           p <- rep(NA, length(years))
                           p[years >= min(x$year) & years <= max(x$year)] <- predict(m, newdata=data.frame(year=min(x$year):max(x$year)))
                           p[years < min(x$year)] <- p[years==min(x$year)]
                           p[years > max(x$year)] <- p[years==max(x$year)]  
                           for (ii in which(gaps>=5)) {
                             int <- (years >= x$year[ii] & years <= x$year[ii+1])
                             p[int] <- approx(c(x$year[ii], x$year[ii+1]), c(p[years==x$year[ii]],p[years==x$year[ii+1]]), n=sum(int))$y
                           } 
                         }
                         data.frame(year=years, u5_comp_pred=p)
                       })
  child_loess <- merge(child_loess, child, all=T)
  names(child_loess)[names(child_loess)=="comp"] <- "u5_comp"
  write.csv(child_loess,paste0(root,"/strPath/d08_child_loess.csv"),row.names=F)
                       
## Make adult a square data frame
  square <- data.frame(iso3_sex_source = rep(unique(ddm$iso3_sex_source), length(1950:end_year)), 
                       year = rep(1950:end_year, each=length(unique(ddm$iso3_sex_source))), stringsAsFactors=F)
  # Pull out ihme_loc_id from iso3_sex_source
  locnames <- data.frame(str_split_fixed(square$iso3_sex_source,"&&",3), stringsAsFactors =FALSE)
  square$ihme_loc_id <- locnames$X1
  
  square <- merge(square, codes, all.x=T)
  adult <- merge(square, adult, all=T)

## Merge child comp onto the adult comp
  adult <- merge(adult, child_loess, by=c("iso3_sex_source", "ihme_loc_id", "year"), all=T)
  adult$u5_comp_pred[is.na(adult$u5_comp_pred)] <- 0 
  adult_all <- adult[order(adult$iso3_sex_source, adult$year, adult$comp_type),]

## We do this once process twice because DDM isn't meant for subnational estimates, which gives huge uncertainty that propegates thorugh 
## non-subnational estimates due to the modeling procedure
##    (1) Drop subnational to get all national-level results
##    (2) Drop national level results for countries with subnational estimates to get subnational results
  save_subnational_1 <- list()
  save_subnational_2 <- list()
  save_subnational_3 <- list()
  length(save_subnational_1) <- 2
  length(save_subnational_2) <- 2
  length(save_subnational_3) <- 2
  save_all <- list()

  for (level in c(1:3)) {
    save_all[[level]] <- list()
    total_list <- get(paste0("level_",level))
    keep_list <- get(paste0("keep_level_",level))
   
    ## load data
    adult <- adult_all[adult_all$ihme_loc_id %in% total_list,] 
      
    ######################
    ## First stage 
    ######################
    
    ## Determine data to exclude (for each set of three, drop the point furthest from one)
      adult$id[is.na(adult$id)] <- 999 
      adult <- ddply(adult, c("iso3_sex_source", "year", "id"), 
                     function(x) { 
                       x$exclude <- 0 
                       if (sum(!is.na(x$comp))>=3) x$exclude[which.max(abs(x$comp))] <- 1 
                       x
                     })
                     
    ## Combine the South and East Asia super-regions (South Asia only has a few countries and is dominated by SRS, making the VR in India pretty weird)
      adult$super_region_name[adult$super_region_name %in% c("South Asia", "East Asia")] <- "South & East Asia/Pacific" 
    
    ## Put Mauritius and Seychelles into the South & East Asia Pacific super region, since their region is South Asia but their super region is Southeast Asia, East Asia, and Oceania
      adult$super_region_name[adult$ihme_loc_id %in% c("MUS","SYC")] <- "South & East Asia/Pacific" 
    ## Split the data by type (VR/SRS/DSP are analyzed separately) 
      data <-  NULL
      data[[1]] <- adult[grepl("VR|SRS|DSP", adult$iso3_sex_source),]
      data[[2]] <- adult[!grepl("VR|SRS|DSP", adult$iso3_sex_source),]
     
    ## Fit the first stage prediction model for SRS/VR 
      m <- lmer(comp ~ u5_comp_pred + (1+u5_comp_pred|super_region_name) + (1+u5_comp_pred|region_name) + (1|iso3_sex_source), data=data[[1]][data[[1]]$exclude==0,])
      coefs <- NULL 
      for (rr in unique(data[[1]]$region_name)) {
        cat(paste(rr,"\n")); flush.console()
        sr <- unique(data[[1]]$super_region_name[data[[1]]$region_name==rr])
        coefs[[rr]] <- rep(NA, 2)
        coefs[[rr]][1] <- fixef(m)[1] + ifelse(rr %in% rownames(ranef(m)$region_name), ranef(m)$region_name[rr,1], 0) + ranef(m)$super_region_name[sr,1]
        coefs[[rr]][2] <- fixef(m)[2] + ifelse(rr %in% rownames(ranef(m)$region_name), ranef(m)$region_name[rr,2], 0) + ranef(m)$super_region_name[sr,2]
    
        ii <- (data[[1]]$region_name == rr)
        data[[1]]$pred.1[ii] <- coefs[[rr]][1] + coefs[[rr]][2]*data[[1]]$u5_comp_pred[ii]
      }
      data[[1]]$resid <- data[[1]]$comp - data[[1]]$pred.1
      data[[1]]$resid[data[[1]]$exclude == 1] <- NA
      
    ## For other, assume 1 as the first stage prediction
      data[[2]]$pred.1 <- 0
      data[[2]]$resid <- data[[2]]$comp - data[[2]]$pred.1
      data[[2]]$resid[data[[2]]$exclude == 1] <- NA
      
    ## Save the first stage model 
      save(coefs, file=paste("d08_first_stage_regression_level",level,".rdata",sep=""))
      write.dta(data[[1]],file = paste0("predict_results_1",level,".dta"))
      write.dta(data[[2]],file = paste0("predict_results_2",level,".dta"))  
    
    ######################
    ## Second stage 
    ######################
    
    ## Apply space-time to the residuals (separately for VR/SRS and other)
      for (ii in 1:2) {
        temp <- resid_space_time(data[[ii]], lambda=2, zeta=0.95)
        data[[ii]] <- merge(data[[ii]], temp)
        data[[ii]]$pred.2.raw <- data[[ii]]$pred.1 + data[[ii]]$pred.resid
        data[[ii]] <- loess_resid(data[[ii]])
      }
    
    ### Save dataset
      for (ii in 1:2) {
        save_all[[level]][[ii]] <- data[[ii]][order(data[[ii]]$region_name, data[[ii]]$iso3_sex_source, data[[ii]]$year, data[[ii]]$comp_type),]
      }
     
  } # end subnational loop
      
## combine data
  for (ii in 1:2) {
    data[[ii]] <- rbind(save_all[[1]][[ii]][save_all[[1]][[ii]]$ihme_loc_id %in% keep_level_1,],
                        save_all[[2]][[ii]][save_all[[2]][[ii]]$ihme_loc_id %in% keep_level_2,],
                        save_all[[3]][[ii]][save_all[[3]][[ii]]$ihme_loc_id %in% keep_level_3,])
  }
  

######################
## Uncertainty 
######################

## Calculate raw standard deviation
  for (ii in 1:2) {
    data[[ii]]$region_name[grepl("Sub-Saharan", data[[ii]]$region_name)] <- "Sub-Saharan Africa"
    if (ii == 2) data[[ii]]$region_name[grepl("Latin America", data[[ii]]$region_name)] <- "Latin America"
    data[[ii]]$resid <- data[[ii]]$comp - data[[ii]]$pred.2.final
    data[[ii]]$resid[data[[ii]]$exclude==1] <- NA 
    sd <- tapply(data[[ii]]$resid, data[[ii]]$region_name, function(x) 1.4826*median(abs(x), na.rm=T))
    for (rr in names(sd)) data[[ii]]$sd[data[[ii]]$region_name == rr] <- sd[rr] 
  }
  
## Simulate from the original mean and variance; truncate these distributions and recalculate the mean, variance, and confidence bounds
  set.seed(4463)
  nsims <- 10000
  for (ii in 1:2) { 
    sims <- matrix(NA, nrow=nrow(data[[ii]]), ncol=nsims)
    for (jj in 1:nrow(sims)) sims[jj,] <- rnorm(n=nsims, mean=data[[ii]]$pred.2.final[jj], sd=data[[ii]]$sd[jj])
    
    ## calculate non-truncated, anti-logged mean and confidence intervals 
    data[[ii]]$pred <- apply(sims, 1, function(x) mean(10^(x)))
    data[[ii]]$lower <- apply(sims, 1, function(x) quantile(10^(x), 0.025, na.rm = TRUE))    
    data[[ii]]$upper <- apply(sims, 1, function(x) quantile(10^(x), 0.975, na.rm = TRUE))   

    ## calculate truncated, anti-logged mean, sd, and confidence intervals 
    for (jj in 1:nrow(sims)) sims[jj,][sims[jj,]>0] <- 0 
    data[[ii]]$trunc_sd <- apply(sims, 1, function(x) sd(x))
    data[[ii]]$trunc_pred <- apply(sims, 1, function(x) mean(10^(x)))
    data[[ii]]$trunc_lower <- apply(sims, 1, function(x) quantile(10^(x), 0.025, na.rm = TRUE))    
    data[[ii]]$trunc_upper <- apply(sims, 1, function(x) quantile(10^(x), 0.975, na.rm = TRUE)) 
    
    # write out sim file for regional and global completeness calculations (will be truncated)
    if (ii == 1) {
      temp <- cbind(data[[ii]][,c("iso3_sex_source","year","ihme_loc_id","region_name","comp_type","u5_comp_pred")], sims)
      write.table(temp,file=ifelse(root=="J:",
                                   paste(root,"/strPath/sims",ii,".txt",sep=""),
                                   paste("/strPath/sim_",ii,".txt",sep="")),
                  row.names=F,col.names=T,sep="\t")
    }
  } 
  
### Remove from log space
  all <- rbind(data[[1]], data[[2]])
  all <- all[,c("region_name", "location_name", "location_id", "ihme_loc_id", "iso3_sex_source", "year", "u5_comp", "u5_comp_pred", "comp_type", "comp", "pred.1", "pred.2.final",
                "sd", "pred", "lower", "upper", "exclude", "trunc_sd", "trunc_pred", "trunc_lower", "trunc_upper")]
  names(all)[names(all)=="pred.1"] <- "pred1"
  names(all)[names(all)=="pred.2.final"] <- "pred2"

  for (var in c("u5_comp", "u5_comp_pred", "comp", "pred1", "pred2")) {
    all[,var] <- 10^(all[,var])
  }

### Make the regions proper again
  all <- all[,!names(all) %in% c("region_name", "super_region_name", "location_name", "location_id")]
  all <- merge(all, codes, all.x=T)    


###################
## Save and plot
###################

## save normal file
  write.dta(all, file="d08_smoothed_completeness.dta")

## Plot results
## get colors and symbols 
  all <- merge(all, data.frame(comp_type=c("ggb", "seg", "ggbseg"), pch=c(24,25,23), col=c("green", "blue", "purple"), stringsAsFactors=F), all.x=T)
  all <- all[order(all$region_name, all$iso3_sex_source, all$year, all$comp_type),]

## find years that we have census populations for DDM
  pop <- read_dta("d05_formatted_ddm.dta")
  pop$source_type[grepl("SRS", pop$source_type)] <- "SRS"
  pop$source_type[grepl("DSP", pop$source_type)] <- "DSP"
  pop$source_type[grepl("SSPC|DC", pop$source_type)] <- "SSPC-DC"
  pop$source_type[grepl("VR", pop$source_type) & pop$iso3 != "TUR"] <- "VR"
  pop$iso3_sex_source <- paste(pop$iso3, pop$sex, pop$source_type, sep="&&")
  pop <- pop[pop$sex == "both",]
  years <- do.call("rbind", strsplit(pop$pop_years, " "))
  for (ii in 1:2) years[,ii] <- substr(years[,ii],nchar(years[,ii])-3,nchar(years[,ii]))
  pop <- data.frame(unique(rbind(cbind(pop[,"iso3_sex_source"], years[,1]),cbind(pop[,"iso3_sex_source"], years[,2]))))
  names(pop) <- c("iso3_sex_source", "year")
  pop$year <- as.numeric(as.character(pop$year))

## make plots 
  for (fixed in c(T, F)) {
    pdf(paste("ddm_graphs/ddm_plots", if(fixed) "_fixed_range.pdf" else ".pdf", sep=""), width=12, height=7)
    par(xaxs="i")
    for (sr in sort(unique(all$super_region_name))) {
      tempall <- all[all$super_region_name==sr,]
      for (rr in sort(unique(tempall$region_name))) {
        tempall2 <- tempall[tempall$region_name==rr,]
        for (cc in sort(c(unique(tempall2$iso3_sex_source[grepl("VR|SRS|DSP", tempall2$iso3_sex_source)]),unique(tempall2$iso3_sex_source[!grepl("VR|SRS|DSP", tempall2$iso3_sex_source)])))) {
          temp <- all[all$iso3_sex_source == cc,]
          if (fixed) ylim <- c(0,2) else ylim <- range(na.omit(unlist(temp[,c("comp", "pred1", "pred2", "u5_comp", "u5_comp_pred", "pred", "lower", "upper", "trunc_lower", "trunc_upper")])))
          plot(0, 0, xlim=c(1950,end_year), ylim=ylim, type="n", xlab="Year", ylab="comp")
          
          if (mean(temp$upper-temp$lower, na.rm=TRUE) > mean(temp$trunc_upper-temp$trunc_lower, na.rm=TRUE)) {
            polygon(c(temp$year, rev(temp$year)), c(temp$lower, rev(temp$upper)), col="gray60", border="gray60")
            polygon(c(temp$year, rev(temp$year)), c(temp$trunc_lower, rev(temp$trunc_upper)), col="gray80", border="gray80")
          } else {
            polygon(c(temp$year, rev(temp$year)), c(temp$trunc_lower, rev(temp$trunc_upper)), col="gray80", border="gray80")
            polygon(c(temp$year, rev(temp$year)), c(temp$lower, rev(temp$upper)), col="gray60", border="gray60")
          }
          
          lines(temp$year, temp$u5_comp_pred, col="red", lwd=2, lty=1)
          points(temp$year, temp$u5_comp, pch=19, col="red", cex=1.5)
          
          lines(temp$year, temp$pred1, col="orange", lwd=2, lty=1)
          lines(temp$year, temp$pred, col="black", lwd=4, lty=1)
          lines(temp$year, temp$trunc_pred, col="black", lwd=4, lty=2)
          
          points(temp$year, temp$comp, pch=temp$pch, col=temp$col, bg=ifelse(temp$exclude==1, NA, temp$col), cex=2)
          
          for (ii in pop$year[pop$iso3_sex_source==cc]) segments(x0=ii, y0=(ylim[1]-0.04*(ylim[2]-ylim[1])), x1=ii, y1=ylim[1], lwd=4)
          
          legend("topleft", c("child", "ggb", "seg", "ggbseg", "child", "1st", "2nd", "2nd (trunc)", "CI", "CI (trunc)"),
                 col=c("red","green","blue","purple","red","orange","black","black","gray60","gray80"),
                 pch=c(19,24,25,23,NA,NA,NA,NA,NA,NA),
                 pt.bg=c("red","green","blue","purple",NA,NA,NA,NA,NA,NA),
                 fill=c(NA,NA,NA,NA,NA,NA,NA,NA,"gray60","gray80"),
                 border=c(NA,NA,NA,NA,NA,NA,NA,NA,"gray50","gray80"),
                 lwd=c(NA,NA,NA,NA,1,1,3,3,NA,NA),
                 lty=c(NA,NA,NA,NA,1,1,1,2,NA,NA),
                 ncol=2, bg="white")
          title(main=paste(temp$iso3[1], "  -  ", temp$region_name[1], "  -  ", temp$location_name[1], "\n", gsub("_", " - ", substr(cc, 5, 27)), sep=""))
          
        }
      }
    }
    dev.off()
  }

  ## comparison plots
  source(comp_code)
