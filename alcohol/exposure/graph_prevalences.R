## Compare prevalences across countries etc. 
## Compare: abstainers, former drinkers, drinkers, binge times
## Binge times: graph mean/SE
rm(list=ls()); library(foreign)
library("reshape2")
library("ggplot2")
library("plyr") ## split-apply-combine paradigm for R. Still figuring out what's useful here
library("stringr") ## Advanced string manipulation -- not needed yet, but maybe sometime soon
library("RODBC") 
library("dplyr") # after plyr so that overlapping functions with plyr are defaulted to dplyr
library("shiny")
library("ggvis")
library("magrittr")
library("RColorBrewer")
library("scales") # Allows for log scaling/transformation of axes
library("mgcv")

options(stringsAsFactors = FALSE) # Causes issues with renaming variables


## Location of 2010 
# Years: 1990, 2005, 2010
# gbd2010_loc/year/DATA_COUNTRY_year.csv
gbd2010_loc <- "J:/Project/GBD/RISK_FACTORS/Code/alcohol_eg/New Simulation Files/New Simulation Files/Simulation Folder - Dec 14 2011/Data Files"

## Location of 2013: 
# Years: 1990, 1995, 2000, 2005, 2010, 2013
# gbd2013_loc/alc_data_year.csv
gbd2013_loc <- "J:/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output"

# Set other directories
graph_dir <- "J:/temp/strUser/r_learning/graphs"

# Grab list of iso3s for GBD2010 to use when looping (need to aggregate GBD2013 to national level)
iso3_list <- read.csv("J:/DATA/IHME_COUNTRY_CODES/IHME_COUNTRY_CODES_Y2013M07D26.CSV", stringsAsFactors = FALSE)

iso3s_all <- iso3_list[iso3_list$iso3 !="BMU" & iso3_list$iso3 != "PRI" & iso3_list$gbd_country_iso3 != "ZAF" ,]
iso3s_all <- iso3s_all[iso3s_all$iso3 != "SSD" & iso3s_all$gbd_country_iso3 != iso3s_all$iso3 & iso3s_all$gbd_country_iso3 == "",]
iso3s_all <- iso3s_all[order(iso3s_all$iso3),]
iso3s <- unique(iso3s_all$iso3[iso3s_all$indic_epi == 1])

# Set years etc.
years_2010 <- c("1990", "2005", "2010")
years_2013 <- c("1990", "1995", "2000", "2005", "2010", "2013")

sexes <- c("1","2")


## Storage:
# Unique by country, sex, age category
# Variables of interest:
# REGION: iso3
# SEX: sex
# AGE_CATEGORY: age category (1-3)
# LIFETIME_ABSTAINERS
# FORMER_DRINKERS
# DRINKERS
# BINGE_TIMES
# BINGE_TIMES_SE
# BINGERS
# BINGERS_SE


# Location management
# All subnationals just are the same versions of national estimates
list_years_2013 <- data.frame(years_2013,"2013")
list_years_2010 <- data.frame(years_2010,"2010")
colnames(list_years_2013) <- c("years","gbd")
colnames(list_years_2010) <- c("years","gbd")


append_loop <- function(years,gbd) {
  if(gbd == 2010) {
    filepath <- paste0(gbd2010_loc,"/",years)
    test <- read.csv(paste0(filepath,"/","DATA_COUNTRY_",years,"_iso3corr.csv"), header = TRUE)
  }
  else if(gbd == 2013) {
    filepath <- gbd2013_loc
    read.csv(paste0(filepath,"/","alc_data_",years,".csv"), header = TRUE)
  }
}  

data_2010 <- mdply(list_years_2010,append_loop)
data_2013 <- mdply(list_years_2013,append_loop)

data_2010$iso3 <- data_2010$REGION
data_2013$iso3 <- data_2013$REGION
data_2013$iso3[data_2013$iso3=="CHN_491"] <- "CHN"
data_2013$iso3[data_2013$iso3=="MEX_4643"] <- "MEX"
data_2013$iso3[data_2013$iso3=="GBR_433"] <- "GBR"

#data_2013 <- data_2013[!grepl("CHN_", data_2013$iso3) & !grepl("MEX_", data_2013$iso3) & !grepl("GBR_", data_2013$iso3),] ## Starts with either an A or B]


# Drop Threshold variables from 2013, and combine into one large dataset
data_2013$Threshold <- NULL
data_2013$Threshold_SE <- NULL
data_total <- rbind(data_2013,data_2010)

# Reshape data long so that all variables are set in the correct manner
myvars <- c("iso3","years","gbd","SEX","AGE_CATEGORY","LIFETIME_ABSTAINERS","FORMER_DRINKERS","DRINKERS","BINGERS","BINGE_TIMES")
data_graph1 <- data_total[myvars]
reshape_data <- melt(data_graph1, id.vars = c("iso3","years","gbd","SEX","AGE_CATEGORY"), value.name = 'prevalence',variable.name= "type")
reshape_data$age <- ""
reshape_data$age[reshape_data$AGE_CATEGORY == 1] <- "15 to 34"
reshape_data$age[reshape_data$AGE_CATEGORY == 2] <- "35 to 59"
reshape_data$age[reshape_data$AGE_CATEGORY == 3] <- "60 and over"
names(reshape_data)[names(reshape_data) == "variable"] <- "type"

reshape_data$newtype <- ""
reshape_data$newtype[reshape_data$type == "LIFETIME_ABSTAINERS"] <- "Abstainers"
reshape_data$newtype[reshape_data$type == "FORMER_DRINKERS"] <- "Former"
reshape_data$newtype[reshape_data$type == "DRINKERS"] <- "Drinkers"
reshape_data$newtype[reshape_data$type == "BINGERS"] <- "Bingers"
reshape_data$newtype[reshape_data$type == "BINGE_TIMES"] <- "Binge Times"

#dismod <- list()
#count <- 1
#for (i in c(1990,1995,2000,2005,2010,2013)) {
#  dismod[[count]] <- read.csv(paste0("J:/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/intermediate/swap_prev_",i,".csv"),stringsAsFactors=F)
#  count <- count + 1
#}
#dismod <- do.call("rbind",dismod)
#names(dismod)[1:4] <- c("iso3","years","AGE_CATEGORY","SEX")
#dismod$age[dismod$AGE_CATEGORY == 1] <- "15 to 34"
#dismod$age[dismod$AGE_CATEGORY == 2] <- "35 to 59"
#dismod$age[dismod$AGE_CATEGORY == 3] <- "60 and over"
#dismod$BINGE_TIMES <- dismod$BINGE_TIMES_SE <- NULL
#dismod$gbd <- "DISMOD"
#dismod <- melt(dismod, id.vars = c("iso3","years","gbd","SEX","AGE_CATEGORY","age"), value.name = 'prevalence',variable.name= "type")
#dismod$newtype[dismod$type == "LIFETIME_ABSTAINERS"] <- "Abstainers"
#dismod$newtype[dismod$type == "FORMER_DRINKERS"] <- "Former"
#dismod$newtype[dismod$type == "DRINKERS"] <- "Drinkers"
#dismod$newtype[dismod$type == "BINGERS"] <- "Bingers"

#reshape_data <- rbind(reshape_data,dismod)

# master_combo

# Line w/ uncertainty over time, dif colors for gbd 2010/2013
# For binge_times

# Graphs over iso3/sex/age category

# 
# # Let's try a translucent ribbon, with the mean in the middle
# # This looks ugly because too much overlap. 
# # But if we set it to one country, it looks better
# master <- ggplot(small_years_meanul[small_years_meanul$iso3 == "SLV",], aes(x = age, y = mean, color = iso3, linetype = factor(year))) +
#   geom_line() +
#   geom_ribbon(aes(x = age, ymin = lower, ymax = upper, color = iso3, fill = factor(year), alpha = 1/100000000)) +
#   guides(fill = FALSE, color = FALSE, linetype = FALSE, alpha = FALSE) # Can do these individually, or do theme(legend.position="none")
# 
#reshape_data$variable <- as.character(reshape_data$variable)

#view <- reshape_data[order(reshape_data$iso3,reshape_data$variable,reshape_data$gbd,reshape_data$SEX,reshape_data$AGE_CATEGORY,reshape_data$year),]

# Print
setwd(graph_dir)
pdf("prevalence_alc_plusdismod5.pdf",height=8,width=12)
for(iso3 in iso3s) {
  for(sex in sexes) {
    if(sex == "1") sex_name <- "Male"
    if(sex == "2") sex_name <- "Female"
    # Graphs
    # Line over time, solid for GBD2013, dotted for 2010, with same colors
    # Comparing drinkers, former drinkers, and bingers
    master <- ggplot(reshape_data[reshape_data$iso3==iso3 & reshape_data$SEX == sex ,], aes(x = years, y = value, color = gbd, group = gbd, ymin = 0, ymax = 1)) +
      geom_line() +
      ggtitle(paste0(iso3," ", sex_name,": Graph of prevalence, by age and type of drinking")) 
    
    # Create facets with free scales (different sizes/ranges)
    master_combo <- master + 
      facet_grid(AGE_CATEGORY~newtype, scales = "free_y") +
      theme(axis.text.x  = element_text(angle=90))
    print(master_combo)
  }
}
dev.off()

## make subnat graphs
reshape_data <- reshape_data[substr(reshape_data$iso3,1,3) %in% c("CHN","MEX","GBR"),]
iso3s <- unique(reshape_data$iso3)
#reshape_data <- reshape_data[!(reshape_data$iso3 %in% c("CHN","MEX","GBR")),]
setwd(graph_dir)
pdf("prevalence_alc_plusdismod_subnat.pdf")
for(iso3 in iso3s) {
  for(sex in sexes) {
    if(sex == "1") sex_name <- "Male"
    if(sex == "2") sex_name <- "Female"
    print(iso3)
    # Graphs
    # Line over time, solid for GBD2013, dotted for 2010, with same colors
    # Comparing drinkers, former drinkers, and bingers
    master <- ggplot(reshape_data[reshape_data$iso3==iso3 & reshape_data$SEX == sex ,], aes(x = years, y = prevalence, color = gbd, group = gbd, ymin = 0, ymax = 1)) +
      geom_line() +
      ggtitle(paste0(iso3," ", sex_name,": Graph of prevalence, by age and type of drinking")) 
    
    # Create facets with free scales (different sizes/ranges)
    master_combo <- master + 
      facet_grid(age~newtype, scales = "free_y") +
      theme(axis.text.x  = element_text(angle=90))
    print(master_combo)
  }
}
dev.off()
