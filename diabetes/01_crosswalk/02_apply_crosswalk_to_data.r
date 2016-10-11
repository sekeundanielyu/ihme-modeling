########################################################################################################################

########################################################################################################################

rm(list=ls())
root <- ifelse(Sys.info()[1]=="Windows", "prefix", "prefix")
thisdate <- format(Sys.time(), format = "%Y_%m_%d")
parent_dir <- paste(root,"strPath", sep="")
setwd(paste(parent_dir, "strPath", sep=""))

crosswalk_dir <- paste(parent_dir, "strPath/diabetes_ratios_nhanes.csv", sep="")
data_date <- "date"
data_dir <- paste(root, "strPath/diabetes_", data_date,".csv", sep="")

## Read in data and crosswalk ratios -----------------------------------------------------------------------

#crosswalk ratios
crosswalks <- read.csv(crosswalk_dir, stringsAsFactors=F)
rownames(crosswalks) <- crosswalks$X #set index, remove that column
crosswalks$X <- NULL
crosswalks <- data.frame(t(crosswalks))
#assign more descriptive names that match names in 'datapoints'
names(crosswalks) <- c("fpg126_self_drug", "fpg110", "fpg120", "fpg122", "fpg126", "fpg140", "fpg155_ppg222", "fpg100_self_drug", "fpg110_self_drug", "fpg122_self_drug", "fpg140_self_drug", "ha1c10_self_drug")

#add additional definitions:
#four definitions are fpg-based definitions, with an additional ppg component.  We set these equal
# to the simple fpg value.  There are also two stand-alone ppg200 values.  We set these equal to the 
# corresponding fpg126 values.

add_ppg_defs <- c("fpg126", "fpg140", "")
treatment_types <- c("", "_self_drug")

for (def_idx in 1:length(add_ppg_defs)){
  def = add_ppg_defs[def_idx]
  for (type_idx in 1:length(treatment_types)){
    type = treatment_types[type_idx]
    cat(paste(def, type, "\n"))
    if (def!="") {
      crosswalks[[paste(def, "_ppg200", type, sep="")]] = crosswalks[[paste(def, type, sep="")]]
    }
    else{  #we need to create totally new variables for just ppg200 alone, equivalent to fpg126 alone
      crosswalks[[paste(def, "ppg200", type, sep="")]] = crosswalks[[paste("fpg126", type, sep="")]]
    }
  }
}

datapoints <- read.csv(data_dir,stringsAsFactors=F) 

#only keep for grouping=Cases, parameter_type in [Prevalence, Incidence], and data_status="
datapoints<-datapoints[datapoints$grouping=="cases" & (datapoints$parameter_type=="Prevalence" | datapoints$parameter_type=="Incidence"),]  #& datapoints$data_status==""

#a handful of datapoints have 1's for both fpg110 and ppg200_self_drug.  Switch these to just ppg200_self_drug
datapoints$cv_fpg110[datapoints$cv_ppg200_self_drug==1 & datapoints$cv_fpg110==1]<- 0

## Assign each datapoint a crosswalk ratio -----------------------------------------------------------------------

datapoints$crosswalk <-0
datapoints$crosswalk_se <-0 

for (def_idx in 2:length(names(crosswalks))){
  def = names(crosswalks)[def_idx]
  datapoints$crosswalk[datapoints[[paste("cv_", def,sep="")]]==1] <- crosswalks["prevalence_ratio", def]
  datapoints$crosswalk_se[datapoints[[paste("cv_", def,sep="")]]==1] <- crosswalks["ratio_se", def]
}

#any remaining zeros in this column refer to studies that fit the reference categories; we fill these with mean 1, se 0
datapoints$crosswalk[datapoints$crosswalk==0] <- crosswalks["prevalence_ratio", "fpg126_self_drug"]
datapoints$crosswalk[datapoints$crosswalk==0] <- crosswalks["ratio_se", "fpg126_self_drug"]

## Generate new mean/upper/lower by multiplying original means with crosswalks -----------------------------------------------------------------------

#rename original mean and se
names(datapoints)[names(datapoints)=="mean"]<- "original_mean"
names(datapoints)[names(datapoints)=="standard_error"]<- "original_standard_error"

#generate new mean and se
datapoints$mean <- datapoints$original_mean / datapoints$crosswalk
#add in quadrature for standard error
datapoints$standard_error = datapoints$mean * sqrt( (datapoints$original_standard_error/datapoints$original_mean)^2 + (datapoints$crosswalk_se/datapoints$crosswalk)^2)


## Save -----------------------------------------------------------------------

write.csv(datapoints, file=paste("strPath/crosswalked_data_", data_date, ".csv") )
