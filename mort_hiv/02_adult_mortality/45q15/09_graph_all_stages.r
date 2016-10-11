###############################################################################
## Description: Graph all stages of adult mortality prediction, data, and other
##              pertinant information
###############################################################################


#source("strPath/09_graph_all_stages.r")

rm(list=ls())
library(foreign); library(lme4); library(RColorBrewer); library(lattice); library(data.table)

if (Sys.info()[1] == "Linux") {
  root <- "/home/j" 
  shocks <- F
  comparison <- T
  start_year  <- 1970
  param_selection <- commandArgs()[3]
} else {
  root <- "J:"
  shocks <- F
  comparison <- T
  start_year <- 1970
  param_selection <- F
}

setwd(paste0(root,"strPath"))

gbd_type <- "gbd2015"
comp_gbd_type <- "gbd2013" # Options: gbd2013, current, both

current_file <- list(est=ifelse(shocks, "results/estimated_45q15.txt", "strPath/estimated_45q15_noshocks_wcovariate.txt"), 
                     pred="data/input_data.txt", 
                     data="data/raw.45q15.txt")   

if(comp_gbd_type == "gbd2013") {
  filepath_2013 <- paste(root, "strPath", sep="")
  comparison_file <- list(est=ifelse(shocks,paste0(filepath_2013,"strPath/estimated_45q15_2014-05-13.txt"),paste0(filepath_2013,"strPath/estimated_45q15_noshocks_2014-05-13.txt")),
                          pred=paste0(filepath_2013,"strPath/prediction_model_results_all_stages_2014-05-13.txt"),
                          data=paste0(root,"strPath/raw.45q1513_May_2014.txt"))  
}
if(comp_gbd_type == "current") {
  target_date <- "2015-10-08" # Sample format: "2015-10-03"
  date_formatted <- format(as.Date(target_date,"%Y-%m-%d"),format = "%d_%b_%Y") # Produces "17_Sep_2015", for example
  if(substring(date_formatted,1,1) == "0") {
    date_formatted <- paste0("_",substring(date_formatted,2)) # Weird file saving thing where 0 is replaced with _ when saving
    date_formatted <- gsub("_2"," 2",date_formatted) # Replace second underscore with a space
  }
    # date_formatted <- "23_Oct_2015" # Sample format: "_3_Oct YYYY"
  
  ## We changed the format of 45q15 output files in late Oct 2015 -- so we need a handler for different output types within GBD2015
  compare_version <- ifelse(as.numeric(as.Date(target_date)) < as.numeric(as.Date("2015-10-24")),"old","new") 
  
  if(compare_version == "old") {
    # Sept 17th, 2015: Last use of 5-year sibs groups
    # Oct 3rd, 2015: Last run of 1-year sibs age groups
    # Oct 6th, 2015: Most recent run of 8 2-year sibs groups
    
    # Oct 23, updated run of 45q15 without HIV sims
    # Oct 27 First run of 45q15 with hiv sims
    comparison_file <- list(est=paste0("strPath/estimated_45q15_noshocks_",target_date,"_pre_param_select.txt"),
                            pred=paste0("strPath/prediction_model/prediction_model_results_all_stages_",target_date,".txt"),
                            data=paste0("strPath/raw.45q15.",date_formatted,"_pre_param_select.txt"))
  } else {
   comparison_file <- list(est=paste0("strPath/estimated_45q15_noshocks_",target_date,".txt"),
                           pred=paste0("strPath/raw.45q15.",target_date,".txt"),
                           data=paste0("strPath/raw.45q15.",date_formatted,".txt"))
  }
} else {
  compare_version <- "old"
}

source(paste0(root,"strPath/get_locations.r"))
codes <- get_locations()
iso3_map <- codes[,c("local_id_2013","ihme_loc_id","region_name","super_region_name")]
locnames <- codes[,c("ihme_loc_id","location_name","region_name")]


####################
## Load Everything
####################

## define function for getting all data and all predictions and covariates


  prep_data <- function(file1,file2,file3,start_year,gbd_type,version,comp) { 
    ##  file1 is results
    ##  file2 is predictions (for old), or input_data (for new)
    ##  file3 is data
    ##  start_year is the year to start comparisons (usually 1950)
    ##  gbd_type = gbd_2010 or gbd_2013
    ##  version is related to compare_version (new vs. old results format)
    
    ## #######################################
    ## If you want to line by line test to see why data merges are failing:
#         file1 <- current_file[[1]]
#         file2 <- current_file[[2]]
#         file3 <- current_file[[3]]
#         file1 <- comparison_file[[1]]
#         file2 <- comparison_file[[2]]
#         file3 <- comparison_file[[3]]
    #     start_year <- 1970
#         gbd_type <- "gbd2015"
#         version <- "new"
#         comp <- T
    ## ########################################
    
    if (version == "old") {
      d1 <- read.csv(file1, stringsAsFactors=F)
      d2 <- read.csv(file2, stringsAsFactors=F)
      
      d <- merge(d1, d2)
    }
    if (version == "new") {
      d1 <- read.csv(file1, stringsAsFactors = F)
      names(d1)[names(d1) == "med_hiv"] <- "hiv"
      names(d1)[names(d1) == "med_stage1"] <- "pred.1.noRE"
      names(d1)[names(d1) == "med_stage2"] <- "pred.2.final"
      d2 <- read.csv(file2, stringsAsFactors = F)
      d2 <- unique(d2[,c("ihme_loc_id","sex","year","LDI_id","mean_yrs_educ","type")]) # Just want the covs and types, not the unique datapts
      d <- merge(d1,d2)
      d$stderr <- NA # Haven't figured out a way to aggregate SE
    }
    
    if (gbd_type == "gbd2010") {
      names(d)[names(d) == "pred.1b"] <- "pred.1.noRE"
    }
    if (gbd_type %in% c("gbd2010","gbd2013")) d$unscaled_mort <- as.numeric(NA)
    
    d3 <- read.csv(file3, header=T, stringsAsFactors=F)
    
    ## categorize data (needed for excluded data)
    d3$category[d3$adjust == "complete"] <- "complete" 
    d3$category[d3$adjust == "ddm_adjusted"] <- "ddm_adjust"
    d3$category[d3$adjust == "gb_adjusted"] <- "gb_adjust" 
    d3$category[d3$adjust == "unadjusted"] <- "no_adjust"
    d3$category[d3$source_type == "SIBLING_HISTORIES"] <- "sibs"    
    
    ## format the data
    d3$exclude <- as.numeric((d3$exclude + d3$shock)>0)
    d3$year <- floor(d3$year) + 0.5
    ## put this back in - temporary for Chris
    if(gbd_type == "gbd2013") {
      d <- merge(d,iso3_map,by.x="iso3",by.y="local_id_2013",all.x=T)
      d$iso3 <- NULL
      d3 <- merge(d3,iso3_map,by.x="iso3",by.y="local_id_2013",all.x=T)
      d3$iso3 <- NULL
    }
    
    d3 <- d3[d3$sex!="both",c("ihme_loc_id","year","sex","adj45q15","deaths_source","source_type","exclude","category","comp")]
    names(d3)[4] <- "mort" 
    if (version == "new") d3$data <- 1
    
    ## merge in non-excluded data 
    x <- nrow(d)
    if (version == "new") temp1 <- merge(d, d3[d3$exclude==0,], by=c("ihme_loc_id","year","sex"), all=T)
    if ( version == "old") temp1 <- merge(d, d3[d3$exclude==0,], by=c("ihme_loc_id","year","sex","mort","category"), all=T)
    # if (nrow(temp1) != x) stop("Data merge failed") 
    # This means that there is some non-excluded data that doesn't match with the results, or that are duplicates for a given year/sex/category 
    # If you are having data merge issues, then you should look at data_45q15_vet.do in the 45q15 folder to examine the data (easier 
    
    ## merge in excluded data 
    x <- nrow(d) + sum(d3$exclude==1)

    temp2 <- merge(unique(d[,c("ihme_loc_id","year","sex","mort_med","mort_lower","mort_upper","unscaled_mort",
                               "LDI_id","mean_yrs_educ","hiv","type",
                               "pred.1.noRE","pred.2.final")]), 
                   d3[d3$exclude==1,], by=c("ihme_loc_id","year","sex"), all.y=T)
    
    # Troubleshooting -- duplicated datapoint? 
    # xd3  <- d3[duplicated(d3[,c("ihme_loc_id","year","sex")]),]
    # xt <- temp2[duplicated(temp2[,c("ihme_loc_id","year","sex")]),]
    
    temp2$data <- 1
    d <- merge(temp1, temp2, all=T)  
    #if (nrow(d) != x) stop("Comparison merge failed")
    
    ## get country names
    d$region_name <- d$location_name <- NULL # Delete region/location_name if it already exists (for GBD2015)
    d <- merge(d, locnames, by="ihme_loc_id", all.x=T)
    d <- d[order(d$ihme_loc_id, d$sex, d$year, d$data),]  
    d <- d[d$year>start_year,]
  } 

## get current and (if applicable) comparitor data 
d <- prep_data(file1=current_file[[1]], file2=current_file[[2]], file3=current_file[[3]],start_year,gbd_type="gbd2015",version = "new", comp = F)                  
if (comparison) {
  c <- prep_data(file1=comparison_file[[1]], file2=comparison_file[[2]], comparison_file[[3]],start_year,comp_gbd_type, compare_version, comp = T)    
  c$ihme_loc_id[c$ihme_loc_id == "CHN"] <- "CHN_44533"
}

## current selected parameters
params <- read.csv("results/selected_parameters.txt")
p <- merge(params[params$best==1,], unique(d[,c("ihme_loc_id","sex","type")]))
p <- p[,c("ihme_loc_id", "sex", "type", "scale", "amp2x", "zeta", "lambda")]
d <- merge(d[,names(d)!="type"], p)
d <- d[order(d$ihme_loc_id, d$sex, d$year, d$data),]

## Temporary - include both previous run and gbd 2013

prev <- read.csv(paste0(root, "strPath/estimated_45q15_noshocks_wcovariate_2016-03-21.txt"))
setnames(prev, old=c("mort_med", "med_stage1"), new=c("mort_med_old", "first_stage_old"))
prev$mort_upper <- prev$mort_lower <- prev$unscaled_mort <- NULL



d <- merge(d, prev, all.x=T, by=c("ihme_loc_id","year", "sex"))


####################
## Classify sources & categories 
####################
## set categories (Symbols) 
symbols <- c(23,24,25,21,22)
names(symbols) <- c("complete", "ddm_adjust", "gb_adjust", "no_adjust", "sibs")
for (ii in names(symbols)) {
  d$pch[d$category==ii] <- symbols[ii]
  if (comparison) c$pch[c$category==ii] <- symbols[ii]
} 

## set sources (colors) 
colors <- c(VR="purple", SRS="green1", DSP="green2", DSS="orange",
            DHS="red", RHS="orange1", PAPFAM="hotpink", PAPCHILD="hotpink1", 
            Census="blue", Other="chocolate4")

d$color[d$source_type =="VR"] <- colors["VR"]
d$color[grepl("SRS", d$source_type)] <- colors["SRS"]
d$color[grepl("DSP", d$source_type)] <- colors["DSP"]
d$color[grepl("DSS", d$source_type)] <- colors["DSS"]
d$color[grepl("DHS", d$deaths_source) | grepl("dhs",d$deaths_source)] <- colors["DHS"]
d$color[d$deaths_source == "CDC-RHS"] <- colors["RHS"]
d$color[d$deaths_source == "PAPFAM"] <- colors["PAPFAM"]
d$color[d$deaths_source == "PAPCHILD"] <- colors["PAPCHILD"]
d$color[d$source_type == "CENSUS" | grepl("census", tolower(d$deaths_source))] <- colors["Census"]
d$color[is.na(d$color) & d$data==1] <- colors["Other"]

d$fill <- d$color
d$fill[d$exclude == 1] <- NA

if (comparison) {    
  c$fill <- c$color <- "gray" 
  c$fill[c$exclude == 1] <- NA  
}

####################
## Define graph functions
####################

## data and predictions plot function
plot_preds_data <- function(d, start_year) {
  ## determine range and set up plot
  ylim <- range(unlist(d[,c("mort_lower", "mort_upper", "mort", "pred.1.noRE", "pred.2.final")]), na.rm=T)
  plot(0,0,xlim=c(start_year,2013),ylim=ylim,
       xlab=" ", ylab=" ", tck=1, col.ticks="gray95")
  
  ## plot all predictions (current) 
  polygon(c(d$year, rev(d$year)), c(d$mort_lower, rev(d$mort_upper)), col="gray65", border="gray65")
  # lines(d$year, d$pred.1.wRE, col="green4", lty=2, lwd=2)
  lines(d$year, d$pred.1.noRE, col="red", lty=1, lwd=2)
  lines(d$year, d$pred.2.final, col="blue", lty=1, lwd=2)
  lines(d$year, d$unscaled_mort, col="yellow", lty=1, lwd=3)
  lines(d$year, d$mort_med, col="black", lty=1, lwd=3)
  
  ## plot data
  points(d$year, d$mort, pch=d$pch, col=d$color, bg=d$fill, cex=1.5)
  
  ## legend
  legend("bottomleft", 
         legend=c("1 w/o RE", "2 final", "GPR Unscaled", "GPR", 
                  "Complete VR", "DDM adjusted", "GB adjusted", "Unadjusted", "Sibs"),
         col=c("red","blue","yellow", "black", 
               "black", "black", "black", "black", "black"), 
         lty=c(2,1,1,1,1,rep(NA,5)), lwd=c(rep(2,5),rep(NA,5)),
         pch=c(rep(NA,5),symbols),pt.bg=c(rep(NA,5),rep("black",5)),
         bg="white", ncol=2)
  if (sum(d$data[!is.na(d$data)])>0) legend("top", legend=names(colors)[colors %in% d$color], fill=colors[colors %in% d$color], border=colors[colors %in% d$color], horiz=T, bg="white")
  text(2000, ylim[2], paste(d$type[1], ": scale=", d$scale[1], "; amp2=", round(d$amp2[1],5), " (", d$amp2x[1], ")", sep=""), pos=4)
}

plot_preds_data_compare <- function(d, c, start_year,comp_gbd_type) {
  ## determine range and set up plot
  ylim <- range(c(unlist(d[,c("mort_lower", "mort_upper", "mort", "pred.1.noRE", "pred.2.final")]),
                  unlist(c[,c("mort_lower", "mort_upper", "mort", ifelse(comp_gbd_type == "gbd2010","pred.1b","pred.1.noRE"), "pred.2.final")])), na.rm=T)
  plot(0,0,xlim=c(start_year,2015),ylim=ylim,
       xlab=" ", ylab=" ", tck=1, col.ticks="gray95")
  
  ## plot current predictions
    polygon(c(d$year, rev(d$year)), c(d$mort_lower, rev(d$mort_upper)), col="gray65", border="gray65")
    lines(d$year, d$pred.1.noRE, col="red", lty=1, lwd=2)
    lines(d$year, d$pred.2.final, col="blue", lty=1, lwd=2)
    lines(d$year, d$unscaled_mort, col="yellow", lty=1, lwd=3)
    lines(d$year, d$mort_med, col="black", lty=1, lwd=3)
    lines(d$year, d$mort_med_old, col = "orange", lty=1, lwd=2)
    lines(d$year, d$first_stage_old, col = "red", lty=3)
  
  ## plot comparison predictions
  if (comp_gbd_type == "gbd2010") {
    lines(c$year, c$pred.1b, col="red", lty=2, lwd=1)
    lines(c$year, c$pred.2.final, col="blue", lty=2, lwd=1)
    lines(c$year, c$mort_lower, col="black", lty=2, lwd=1)
    lines(c$year, c$mort_upper, col="black", lty=2, lwd=1)
    lines(c$year, c$mort_med, col="black", lty=2, lwd=2)
  } else {
    lines(c$year, c$pred.1.noRE, col="red", lty=2, lwd=1)
    lines(c$year, c$pred.2.final, col="blue", lty=2, lwd=1)
    lines(c$year, c$mort_lower, col="black", lty=2, lwd=1)
    lines(c$year, c$mort_upper, col="black", lty=2, lwd=1)
    lines(c$year, c$mort_med, col="black", lty=2, lwd=2)
  }
  
  #lines(c$year, c$mort_2013, col="orange", lty=1, lwd=2)
  
  ## plot comparison data
  points(c$year, c$mort, pch=c$pch, col=c$color, bg=c$fill, cex=1.5)
  
  ## plot current data
  points(d$year, d$mort, pch=d$pch, col=d$color, bg=d$fill, cex=1.5)
  
  ## legend
  legend("bottomleft", 
         legend=c("1st stage", "2nd stage", "GPR Unscaled", "GPR", "delta1", "First stage delta1",
                  "Complete VR", "DDM adjusted", "GB adjusted", "Unadjusted", "Sibs"),
         col=c("red","blue", "yellow", "black", "orange", "red",
               "black", "black", "black", "black", "black"),
         lty=c(1,1,1,1,1,3,rep(NA,5)), lwd=c(rep(2,6),rep(NA,5)),
         pch=c(rep(NA,6),symbols),pt.bg=c(rep(NA,6),rep("black",5)),
         bg="white", ncol=2)
  if (sum(d$data[!is.na(d$data)])>0) legend("top", legend=names(colors)[colors %in% d$color], fill=colors[colors %in% d$color], border=colors[colors %in% d$color], horiz=T, bg="white")
}  

## covariates plot function
plot_cov <- function(d) {
  plot(x=d$year, y=log(d$LDI_id), main="LDI", 
       xlab=" ",ylab="", type="l", col="red", lwd=2)
#   text(min(d$year)+1,max(log(d$LDI_id)),coefs$coef[coefs$param=="beta1" & coefs$sex==d$sex[1]],adj=c(0,1))
  
  plot(x=d$year, y=d$mean_yrs_educ, main="Edu",
       xlab=" ",ylab="", type="l", col="red", lwd=2)         
#   text(min(d$year)+1,max(d$mean_yrs_educ),coefs$coef[coefs$param=="beta2" & coefs$sex==d$sex[1]],adj=c(0,1))
  
  plot(x=d$year, y=d$hiv, main="HIV",
       xlab=" ",ylab="", type="l", col="red", lwd=2)      
  abline(h=0.0001, col="black", lwd=0.5)
#   text(min(d$year)+1,ifelse(max(d$hiv)==0,1,max(d$hiv)),coefs$coef[coefs$param=="beta3" & coefs$sex==d$sex[1]],adj=c(0,1))         
}

## data table
data_table <- function(d) {
  d <- d[d$data==1,c("year","mort","stderr", "comp","category","color")]
  d$year <- floor(d$year)
  d$mort <- format(round(d$mort, 3), digits=3, nsmall=3)
  d$stderr <- format(round(d$stderr, 3), digits=3, nsmall=3)
  d$stderr[grepl("NA",d$stderr)] <- "" 
  d$comp <- format(round(d$comp, 3), digits=3, nsmall=3)
  d$comp[grepl("NA",d$comp)] <- "" 
  d$category <- as.character(factor(d$category,
                                    levels=c("complete","ddm_adjust","gb_adjust","no_adjust","sibs"),
                                    labels=c("1","2","3","4","5")))
  d <- rbind(c("Year", "45q15", "se", "comp", "cat", "black"), d)
  
  plot(c(0,0.7),c(0,1),xlab="",ylab="",xaxt="n",yaxt="n",type="n",yaxs="i")
  y <- (1 - seq(0.015,1,by=0.015))[1:nrow(d)]
  text(0.01, y, d$year, col=d$color, cex=0.8, pos=4)
  text(0.15, y, d$mort, col=d$color, cex=0.8, pos=4)
  text(0.3, y, d$stderr, col=d$color, cex=0.8, pos=4)
  text(0.45, y, d$comp, col=d$color, cex=0.8, pos=4)
  text(0.6, y, d$category, col=d$color, cex=0.8, pos=4)
}

####################
## Construct plots
####################
# 
# # Graph the results alone with covariates
#   pdf(ifelse(shocks, "graphs/adult_mortality_all_stages_shocks.pdf", "graphs/adult_mortality_all_stages_noshocks.pdf"), width=10, height=5.6)  
#   for (rr in sort(unique(d$region_name))) { 
#     cat(paste(rr, "\n")); flush.console()
#     for (cc in sort(unique(d$ihme_loc_id[d$region_name==rr]))) { 
#       for (ss in c("male", "female")) { 
#         ii <- (d$ihme_loc_id==cc & d$sex==ss)
#         par(xaxs="i", oma=c(0,0,2,0), mar=c(3,3,2,2))
#         layout(matrix(c(1,2,2,2,1,3,4,5), nrow=2, ncol=4, byrow=T),
#                widths=c(1.5,2,2,2), heights=c(3,1))
#         data_table(d[ii,])
#         plot_preds_data(d[ii,], start_year)
#         plot_cov(d[ii,])
#         mtext(paste(gsub("_", " ", d$super_region_name[ii][1]), ";  ", gsub("_", " ", rr), "\n", d$location_name[ii][1], " (", cc, ");  ", ss, "; data type ", d$type[ii][1], "\n", "Years covered: ", length(unique(d$year[d$ihme_loc_id == cc & d$sex == ss & !is.na(d$category)& d$exclude != 1])), sep=""), outer=T, line=-1) 
#       }
#     } 
#   }  
#   dev.off()
#   
#   file.copy(from=ifelse(shocks, "graphs/adult_mortality_all_stages_shocks.pdf", "graphs/adult_mortality_all_stages_noshocks.pdf"),
#             to=paste("graphs/archive/adult_mortality_all_stages_", ifelse(shocks, "shocks_", "noshocks_"), Sys.Date(), ".pdf", sep=""),
#             overwrite=T)

## Graph the results against comparison results
if (comparison == T) {  
  pdf(ifelse(shocks, "strPath/comparison_adult_mortality_all_stages_shocks.pdf", "strPath/comparison_adult_mortality_all_stages_noshocks.pdf"), width=10, height=5.6)  
  
  plot(1:10, 1:10, type="n", xaxt="n", yaxt="n", xlab="", ylab="")
  text(1, 9, "current files:", adj=0)
  for (ii in 1:3) text(1, 9-ii, paste("     ", current_file[[ii]]), adj=0, cex=0.8)
  text(1, 5, "comparison files:", adj=0)
  for (ii in 1:3) text(1, 5-ii, paste("     ", comparison_file[[ii]]), adj=0, cex=0.8)  
  
  for (rr in sort(unique(d$region_name))) { 
    cat(paste(rr, "\n")); flush.console()
    for (cc in sort(unique(d$ihme_loc_id[d$region_name==rr]))) { 
      for (ss in c("male", "female")) { 
        ii <- (d$ihme_loc_id==cc & d$sex==ss)
        jj <- (c$ihme_loc_id==cc & c$sex==ss)
        amp2x <- unique(d[ii,]$amp2x)
        scale <- unique(d[ii,]$scale)
        lambda <- unique(d[ii,]$lambda)
        zeta <- unique(d[ii,]$zeta)
        par(xaxs="i", oma=c(0,0,2,0), mar=c(3,3,2,2))
        plot_preds_data_compare(d[ii,], c[jj,], start_year,comp_gbd_type)
        mtext(paste(gsub("_", " ", d$super_region_name[ii][1]), ";  ", gsub("_", " ", rr), "\n", d$location_name[ii][1], " (", cc, ");  ", ss, "; data type ", d$type[ii][1], "\n", "Years covered: ", length(unique(d$year[d$ihme_loc_id == cc & d$sex == ss & !is.na(d$category)& d$exclude != 1])),"\n","scale: ", scale, ", ", "amplitude: ", amp2x,", ", "zeta: ", zeta, ", ", "lambda: ", lambda, sep=""), outer=T, line=-1)  
        
      }
    } 
  }  
  dev.off()   
  
  file.copy(from=ifelse(shocks, "strPath/comparison_adult_mortality_all_stages_shocks.pdf", "strPath/comparison_adult_mortality_all_stages_noshocks.pdf"),
            to=paste("strPath/archive/comparison_adult_mortality_all_stages_", ifelse(shocks, "shocks_", "noshocks_"), Sys.Date(), ".pdf", sep=""),
            overwrite=T)
} 

####################
## Make parameter plots 
####################

if(param_selection == T) {
  ## format parameters selection data for lattice 
  params <- params[params$type != "no data",]
  params$mse <- format(round(params$mse, 5), nsmall=5, digits=5)
  params$version <- factor(paste(params$scale, "; ", params$amp2x, sep=""), 
                           levels=paste(rep(sort(unique(params$scale)), each=5), "; ", rep(sort(unique(params$amp2x)), 5), sep=""))
  params$type <- factor(as.character(params$type))
  params$type <- factor(params$type, levels=levels(params$type), 
                        labels=paste(levels(params$type), " (mse: ", unique(params$mse[order(params$type)]), ")", sep=""))
  colors <- brewer.pal(length(unique(params$scale)), "Set1") # What color set + n colors to use for scale
  symbols <- 21:25 # What symbols to use for amp2x
  
  ## make plots                       
  pdf("strPath/parameter_selection_by_type.pdf", width=10, height=7)
  print(xyplot(are ~ coverage|type, groups=version, data=params, 
               selected.loss=params$best, 
               layout=c(1,1), scales=list(alternate=F,relation="free"), type=c("p","g"),
               panel = panel.superpose,
               panel.groups = function(x,y,subscripts,selected.loss,...) { 
                 panel.xyplot(x,y,...) 
                 panel.xyplot(x[selected.loss[subscripts]==1], y[selected.loss[subscripts]==1], pch=0, cex=3, col="black")    
               },
               par.settings=list(superpose.symbol=list(col=rep(colors, each=5),
                                                       fill=rep(colors, each=5), 
                                                       pch=rep(symbols,5), 
                                                       cex=1.2)),
               auto.key=list(space="right")))
  dev.off()
  
  file.copy(from="strPath/parameter_selection_by_type.pdf",
            to=paste("strPath/parameter_selection_by_type_", Sys.Date(), ".pdf", sep=""),
            overwrite=T)
}
