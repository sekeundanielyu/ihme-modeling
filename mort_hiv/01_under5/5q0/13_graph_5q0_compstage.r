###############################################################################
## Date Created: 10 April 2012
## Description: Graph all stages of child mortality prediction, data, and other
##              pertinant information
###############################################################################

  rm(list=ls())
  library(foreign); library(lme4); library(RColorBrewer)

  if (Sys.info()[1] == "Linux") {
    username <- Sys.getenv("USER")
    root <- ""
    code_dir <- paste("",username,"",sep="") # This is the username of the person running the code 
    setwd(code_dir)
    source("get_locations.r")
    
  } else {
    username <- ""
    root <- ""
    code_dir <- ""
    source("get_locations.r")
  }

  setwd(paste(root, "", sep=""))

####################
## Load Everything
####################

  shocks <- F
  start_year <- c(1950, 1970)
  renums <- T 
  comp.old <- F
  chn.prov.only <- F
  natonly <- F
  chnonly <- F
  mexonly <- F

for (ss in start_year) {
  cat(paste("Starting year",ss,"\n")); flush.console()

  ## data and all predictions and covariates
  d1 <- read.table(ifelse(shocks, "estimated_5q0.txt", "estimated_5q0_noshocks.txt"), header=T, stringsAsFactors=F,sep=",")
  d2 <- read.csv("prediction_model_results_all_stages.txt", stringsAsFactors=F)
  d3 <- read.table("raw.5q0.unadjusted.txt", header=T, stringsAsFactors=F)
  #CHANGE
  d3$source[grepl("Rapid Mortality",d3$source)] <- "ZAF RapidMortality Report 2011 - based on VR"

  compare.gpr <- read.csv("estimated_5q0_noshocks_GBD_2013_locations.txt", header=T)
  names(compare.gpr)[3:5] <- c("q5.med","q5.lower","q5.upper")
  compare.gpr <- compare.gpr[compare.gpr$year>=ss,]
  
  compare.gpr.unicef <- read.csv(paste0(root, "unicef_data.csv"), header=T)
  names(compare.gpr.unicef)[4:6] <- c("q5.lower.unicef", "q5.med.unicef","q5.upper.unicef")
  compare.gpr.unicef <- compare.gpr.unicef[compare.gpr.unicef$year>=ss,]
  compare.gpr.unicef <- compare.gpr.unicef[order(compare.gpr.unicef$ihme_loc_id, compare.gpr.unicef$year),]
  

  if(comp.old){
  compare.old <- read.csv("mean_prerake_file.txt", header=T)
  names(compare.old)[3:5] <- c("q5.med","q5.lower","q5.upper")
  compare.old <- compare.old[compare.old$year>=ss,]
  }

  # change names of d1 file
  names(d1)[3:5] <- c("q5.med","q5.lower","q5.upper")

  d <- merge(d1, d2, all = T)
  d$reference[is.na(d$reference)] <- 0

#################
#Merging in the points shifted by the SURVEY random effect
#####################
  d3 <- merge(d3, d2[d2$data == 1,c("ptid","mort","reference")], by = "ptid",all.x=T)
  names(d3)[which(names(d3)=="mort")] <- "adj.q5"


################
#Formatting source data
####################
  ## format data
d3$type[grepl("indirect", d3$in.direct)] <- "SBH"
d3$type[d3$in.direct == "direct"] <- "CBH"
d3$type[grepl("VR|SRS|DSP", d3$source)] <- "VR/SRS/DSP"
d3$type[d3$in.direct == "hh" | (is.na(d3$type) & grepl("census|survey", tolower(d3$source)))] <- "HH"
d3$type[d3$source == "hsrc" & d3$ihme_loc_id == "ZAF"] <- "CBH"
d3$type[d3$source == "icsi" & d3$ihme_loc_id == "ZWE"] <- "SBH"
d3$type[d3$source == "indirect" & d3$ihme_loc_id == "DZA"] <- "SBH"
d3$type[is.na(d3$type)] <- "HH"


d3$graphing.source[grepl("vr|vital registration", tolower(d3$source))] <- "VR"
d3$graphing.source[grepl("srs", tolower(d3$source))] <- "SRS"
d3$graphing.source[grepl("dsp", tolower(d3$source))] <- "DSP"
d3$graphing.source[grepl("census", tolower(d3$source)) & !grepl("Intra-Census Survey",d3$source)] <- "Census"
d3$graphing.source[grepl("_IPUMS_", d3$source) & !grepl("Survey",d3$source)] <- "Census"
d3$graphing.source[(grepl("^DHS .*|DHS", d3$source) &! grepl("SP", d3$source)) | d3$source == "DHS IN"] <- "Standard_DHS"
d3$graphing.source[grepl("dhs|demographic health survey",tolower(d3$source)) & is.na(d3$graphing.source)] <- "Other_DHS"
d3$graphing.source[grepl("mics|multiple indicator cluster", tolower(d3$source))] <- "MICS"
d3$graphing.source[tolower(d3$source) %in% c("cdc", "cdc-rhs", "cdc rhs", "rhs-cdc", "reproductive health survey") | grepl("CDC-RHS|CDC RHS", d3$source)] <- "RHS"
d3$graphing.source[grepl("world fertility survey|wfs|world fertitlity survey", tolower(d3$source))] <- "WFS"
d3$graphing.source[tolower(d3$source) == "papfam" | grepl("PAPFAM", d3$source)] <- "PAPFAM"
d3$graphing.source[tolower(d3$source) == "papchild" | grepl("PAPCHILD", d3$source)] <- "PAPCHILD"
d3$graphing.source[tolower(d3$source) == "lsms" | grepl("LSMS", d3$source)] <- "LSMS"
d3$graphing.source[tolower(d3$source) == "mis" | tolower(d3$source) == "mis final report" | grepl("MIS", d3$source)] <- "MIS"
d3$graphing.source[tolower(d3$source) == "ais"  | grepl("AIS", d3$source)] <- "AIS"
d3$graphing.source[grepl("MOH",d3$source, ignore.case = T)] <- "MoH Routine Reporting"
d3$graphing.source[grepl("MCHS",d3$source)] <- "MCHS"
d3$graphing.source[grepl("ENADID", d3$source)] <- "ENADID"
d3$graphing.source[grepl("MEX_IPUMS", d3$source)] <- "Census (IPUMS)"
d3$graphing.source[grepl("MEX_IPUMS", d3$source) & substr(d3$source,14,14)==5] <- "Inter-censal Survey (IPUMS)"
d3$graphing.source[grepl("Maternal and Child", d3$source)] <- "MCHS"
d3$graphing.source[is.na(d3$graphing.source)] <- "Other"


d3 <- d3[,c("ihme_loc_id", "year", "q5", "graphing.source", "type", "outlier", "shock", "adj.q5","reference")]
names(d3)[2:4] <- c("year", "mort","source")

## get country names
codes <- get_locations()
codes <- codes[codes$level_all != 0,]
codes <- codes[,c("ihme_loc_id","location_name","region_name","super_region_name")]
codes$region_name[codes$ihme_loc_id %in% c("GUY","TTO","BLZ","JAM","ATG","BHS","BMU","BRB","DMA","GRD","VCT","LCA")] <- "CaribbeanI"
d <- merge(d, codes, all.x=T)
d <- d[,!(names(d) %in% c("gbd_region","gbd_super_region"))]
names(d)[names(d) == "region_name"] <- "gbd_region"
names(d)[names(d) == "super_region_name"] <- "gbd_super_region"

d <- d[order(d$ihme_loc_id, d$year, d$data),]

### add current parameters 

params <- read.csv(paste0(root,"selected_parameters.txt"))
d <- merge(d, params, by="ihme_loc_id")
d <- d[order(d$year),]

## add GBD 2013 parameters

params2 <- read.csv(paste0(root,"selected_parameters_2013.txt"))



####################
## Classify sources & categories
####################

## categories (Symbols)
  symbols <- c(21,24,25,23)
  names(symbols) <- c("VR/SRS/DSP", "CBH", "SBH", "HH")
  for (ii in names(symbols)) d3$pch[d3$type==ii] <- symbols[ii]

## sources (colors)
  colors <- c(VR="purple", SRS="green1", DSP="green2", Standard_DHS="orange",
              Other_DHS="red", RHS="deeppink", PAPFAM="hotpink", PAPCHILD="hotpink1",
              Census="blue", Other="chocolate4", MICS="darkgreen", WFS="mediumspringgreen", LSMS="violetred4",
              MIS="khaki4", AIS="steelblue2",MCHS = "hotpink2", "MoH Routine Reporting" = "cyan",
              "Census (IPUMS)" = "hotpink", "Inter-censal Survey (IPUMS)" = "mediumspringgreen",
              ENADID = "orange")
  for (ii in names(colors)) d3$color[d3$source == ii] <- colors[ii]

  d3$fill <- d3$color
  d3$fill[d3$outlier == 1 | d3$shock == 1] <- NA
  dorig <- d
  d3 <- d3[d3$year >= ss,]
  d <- d[d$year >= ss,]

#For plotting points adjusted by RE
makeTransparent<-function(someColor, alpha=100){
  newColor<-col2rgb(someColor)
  apply(newColor, 2, function(curcoldata){rgb(red=curcoldata[1], green=curcoldata[2],
    blue=curcoldata[3],alpha=alpha, maxColorValue=255)})
}
  d3$color2 <- makeTransparent(d3$color)
  d3$fill2 <- makeTransparent(d3$color)

####################
## Define graph functions
####################


  ###############################################################################
  ## Plot points, adjusted points, and final GPR estimates
  plot_data <- function(d,d3,compare.gpr = NULL, compare.gpr.unicef=NULL, dorig = NULL,renums=NULL,compare.old = NULL,compare.old.stages = NULL) {

    ## determine range and set up plot
    if(!is.null(compare.old)){
           ylim <- range(c(d$mort2,d$mort,d3$mort, d3$adj.q5, compare.old$q5.med, unlist(d[,c("q5.lower", "q5.upper", "q5.med","pred.1b","pred.2.final")])), na.rm=T)
    }else{
         ylim <- range(c(d$mort2,d$mort,d3$mort, d3$adj.q5, unlist(d[,c("q5.lower", "q5.upper", "q5.med","pred.1b","pred.2.final")])), na.rm=T)
    }
    plot(0,0,xlim=c(ss+0.5,2016),ylim=ylim, xlab=" ", ylab=" ", tck=1, col.ticks="gray95")

    ## plot predictions
    polygon(c(d$year, rev(d$year)), c(d$q5.lower, rev(d$q5.upper)), col="gray65", border="gray65")
    lines(d$year, d$q5.med, col="black", lty=1, lwd=3)

    ## plot stage 1 and 2
    lines(d$year, d$pred.1b, col="green", lty=1, lwd=2)
    lines(d$year, d$pred.2.final, col="blue", lty=1, lwd=2)

    ## plot previous version of predictions
    if(!is.null(compare.old)){
      lines(compare.old$year, compare.old$q5.med, col="purple", lty = 1, lwd = 2)
      lines(compare.old$year, compare.old$q5.lower, col="purple", lty=2, lwd=1)
      lines(compare.old$year, compare.old$q5.upper, col="purple", lty=2, lwd=1)

    }

    ## plot GBD2010 estimates
    lines(compare.gpr$year, compare.gpr$q5.med, col = "red", lty = 1, lwd = 2)
    lines(compare.gpr$year, compare.gpr$q5.lower, col="black", lty=2, lwd=1)
    lines(compare.gpr$year, compare.gpr$q5.upper, col="black", lty=2, lwd=1)
    
    # plot unicef estimates
    lines(compare.gpr.unicef$year, compare.gpr.unicef$q5.med.unicef, col = "purple", lty = 1, lwd = 2)

    ## plot data w/ and w/out survey RE
    points(d3$year,d3$mort,pch=d3$pch,col=d3$color,bg=d3$fill)
    points(d3$year,d3$adj.q5,pch=d3$pch,col=d3$color2,bg=d3$fill2)

    ## plot black circles around reference data
    points(d3$year[d3$reference == 1], d3$mort[d3$reference == 1], col = "black", pch = 1, cex = 2, lwd = 1.5)

    if (d$ihme_loc_id[1] == "KOR") leg.loc <- "topright" else leg.loc <- "bottomleft"

    if(!is.null(compare.old)){
      legend(leg.loc,
           legend=c("New estimates", "GBD 2013", "Prerake", "Stage 1: Regression", "Stage 2: Space-time",
                    "VR/SRS/DSP", "CBH", "SBH", "HH", "Transparent points are","mixed effects adjusted","Hollow = outlier or shock"),
           col=c("black","red","purple","green","blue",
                 "black", "black", "black", "black", NA, NA, NA),
           lty=c(2,1,1,1,1,rep(NA,7)), lwd=c(2,2,2,2,2,rep(NA,7)),
           pch=c(NA,NA,NA,NA,NA,symbols,NA,NA,NA),pt.bg=c(NA,NA,NA,NA,NA,rep("black",4),NA,NA,NA),
           bg="white", ncol=2, cex = 0.5)
    }else{
      legend(leg.loc,
             legend=c("GPR", "GPR 2013", "UNICEF", "Stage 1: Regression", "Stage 2: Space-time",
                      "VR/SRS/DSP", "CBH", "SBH", "HH", "Transparent points are", "mixed effects adjusted", "Hollow = outlier or shock"),
             col=c("black", "red","purple","green","blue",
                   "black", "black", "black", "black", NA, NA, NA),
             lty=c(1,1,1,1,1,rep(NA,7)), lwd=c(2,1,1,2,2,rep(NA,7)),
             pch=c(NA,NA,NA,NA,NA,symbols,NA,NA,NA),pt.bg=c(NA,NA,NA,NA,NA,rep("black",4),NA,NA,NA),
             bg="white", ncol=2, cex = 0.5)
    
    }

    if (sum(d$data)>0) legend("top",
                              legend=gsub("_", " ", names(colors)[names(colors) %in% d3$source]),
                              fill=colors[names(colors) %in% d3$source],
                              border=colors[names(colors) %in% d3$source],
                              horiz=T, bg="white",cex=0.6)


    #show survey RE
    if(renums){
      inds <- (!duplicated(dorig$source1)& !is.na(dorig$source1))
      inds <- inds[1:length(inds)]
      str1 <- "Mixed Effects Adjustment Factor: \n"
      for(i in which(inds)){
        sourcen <- dorig$source1[i]
        st <- 30
        ind <- regexec(" ",substring(sourcen,31))[[1]][1]
        while(ind != -1){
          bk <- st+ind
          sourcen <- paste(substring(sourcen,1,bk-1),"\n\t\t\t",substring(sourcen,bk),sep = "")
          st <- bk+30
          ind <- regexec(" ",substring(sourcen, st))[[1]][1]
        }
        str1 <- paste(str1, toString(sourcen),":",toString(round(1000*dorig$adjre_fe[i])/1000),"\n")
      }
      str1 <- paste(str1, "\n", "Country Random Effects: ", toString(round(1000*dorig$ctr_re[1])/1000), sep = "")
      mtext(text = str1, side = 4, cex = 0.5,  las = 1)
    }
}



####################
## Construct plots
####################

#  pdf(ifelse(shocks, paste("graphs/child_mortality_model_shocks_",ss,".pdf",sep=""),
#             paste("graphs/child_mortality_model_",ss,".pdf",sep="")), width=16, height=9)
#  for (sr in sort(unique(d$gbd_super_region))) {
#    for (rr in sort(unique(d$gbd_region[d$gbd_super_region==sr]))) {
#      cat(paste(rr, "\n")); flush.console()
#      for (cc in sort(unique(d$ihme_loc_id[d$gbd_region==rr & d$gbd_super_region == sr]))) {
#        ii <- (d$ihme_loc_id==cc)
#        mm <- (dorig$ihme_loc_id == cc)
#        kk <- (compare.gpr$ihme_loc_id==cc)
#        ll <- (compare.d2$ihme_loc_id == cc)
#        plot_preds(d[ii,], compare.d2[ll,], compare.gpr[kk,],dorig[mm,],renums)
#        mtext(paste(gsub("_", " ", sr), ";  ", gsub("_", " ", rr), "\n", d$location_name[ii][1], " (", cc, ")", sep=""), outer=T, line=-1)
#      }
#    }
#  }
#  dev.off()

  if(chn.prov.only){
    d <- d[grepl("X(.{2})",d$ihme_loc_id),]
  }

  pdf(ifelse(shocks, paste("child_mortality_data_shocks_",ss,".pdf",sep=""),
             paste("graphs/child_mortality_data", ss, ".pdf",sep="")), width=10, height=6)
    for (rr in sort(unique(d$gbd_region))) {
      cat(paste(rr, "\n")); flush.console()
      for (cc in sort(unique(d$ihme_loc_id[d$gbd_region==rr]))) {
        if(natonly == 1 & (grepl("X..$",cc) | (cc %in% c("HKG","MAC","BMU","PRI")))) next
        if(chnonly & !((grepl("X..$",cc) | cc == "CHN_44533") & rr == "East Asia")) next
        if(mexonly & !((grepl("X..$",cc) | cc == "MEX") & rr == "Central Latin America")) next
        ii <- (d$ihme_loc_id==cc)
        jj <- (d3$ihme_loc_id==cc)
        kk <- (compare.gpr.unicef$ihme_loc_id == cc)
        ll <- (compare.gpr$ihme_loc_id == cc)
        mm <- (dorig$ihme_loc_id == cc)
        if(comp.old) nn <- (compare.old$ihme_loc_id == cc)
        if(renums) par(xaxs="i", oma=c(0,0,2,7), mar=c(3,3,2,2)) else par(xaxs="i", oma=c(0,0,2,0), mar=c(3,3,2,2))
        if(comp.old){
          plot_data(d = d[ii,],d3 = d3[jj,],compare.gpr = compare.gpr[ll,], compare.gpr.unicef = compare.gpr.unicef[kk,], dorig = dorig[mm,],renums = renums,compare.old = compare.old[nn,]) #, compare.old.stages = compare.old.stages[oo,])
        }else{
          plot_data(d[ii,],d3[jj,],compare.gpr[ll,], compare.gpr.unicef = compare.gpr.unicef[kk,], dorig = dorig[mm,],renums = renums)
        }
        
        mtext(paste(gsub("_", " ", rr), "\n", d$location_name[ii][1], " (", cc, ") \n", 
                    "lambda: ", d$lambda[ii][1],
                    ", zeta: ", d$zeta[ii][1],
                    ", amp: ", d$amp2x[ii][1],
                    ", scale: ", d$scale[ii][1],
                    sep = ""), outer=T, line=-1)

      }
    }
  dev.off()

  file.copy(from=ifelse(shocks, paste("child_mortality_data_shocks",ss,".pdf",sep=""),
                      paste("child_mortality_data_",ss,".pdf",sep="")),
          to=paste("child_mortality_data_",ss, ifelse(shocks, "_shocks_", "_noshocks_"), Sys.Date(), ".pdf", sep=""),
          overwrite=T)
		  
  file.copy(from= paste("child_mortality_data", ss, ".pdf",sep=""),
        to=paste("child_mortality_data_",ss, ifelse(shocks, "_shocks_", "_noshocks_"), Sys.Date(), ".pdf", sep=""),
        overwrite=T)

}

