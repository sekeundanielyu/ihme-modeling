########################################################################################################################

library(foreign) 
library(car)

rm(list=ls())
root <- ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
thisdate <- format(Sys.time(), format = "%Y_%m_%d")
setwd(paste(root, "strPath", sep=""))

## Read in variable layout and loop over surveys ----------------------------------------------------------------------- 
layout <- read.csv("NHANES_files_and_variables.csv", stringsAsFactors=F)
data <- NULL 
for (svy in 1:nrow(layout)) {    
  cat(paste(svy, "of", nrow(layout), "\n")); flush.console() 
  
## Load and format demographics file ----------------------------------------------------------------------------------- 
  demo <- read.dta(paste(layout$dir[svy], layout$demo_file[svy], sep="/"))
  names(demo) <- tolower(names(demo))
  demo <- demo[, c("seqn", as.character(layout[svy, c("sex", "age", "mec_wt", "int_wt")]))]
  names(demo) <- c("seqn", "sex", "age", "mec_wt", "int_wt")
  
## Load and format diabetes modules ------------------------------------------------------------------------------------ 
  if (layout$prediq[svy] != "") {  # only 2005-onward have pre-diabetes questions
    diq <- read.dta(paste(layout$dir[svy], layout$diq_file[svy], sep="/"))
    names(diq) <- tolower(names(diq))
    diq <- diq[, c("seqn", as.character(layout[svy, c("diq", "prediq", "insulin", "oralpills")]))]
    names(diq) <- c("seqn", "diq", "prediq", "insulin", "oralpills")
  }

  else{
    diq <- read.dta(paste(layout$dir[svy], layout$diq_file[svy], sep="/"))
    names(diq) <- tolower(names(diq))
    diq <- diq[, c("seqn", as.character(layout[svy, c("diq", "insulin", "oralpills")]))]
    names(diq) <- c("seqn", "diq", "insulin", "oralpills")
    diq$prediq <- NA
  }

  diq$diq <- recode(diq$diq, "1=1; 2=0; 3=0; else=0")
  diq$prediq <- recode(diq$prediq, "1=1; 2=0; else=0")
  diq$insulin <- recode(diq$insulin, "1=1; 2=0; else=0")
  diq$oralpills <- recode(diq$oralpills, "1=1; 2=0; else=0")
  
  glu <- read.dta(paste(layout$dir[svy], layout$glu_file[svy], sep="/"))
  names(glu) <- tolower(names(glu))
  glu <- glu[, c("seqn", as.character(layout[svy, c("lbxglu", "mec_fast_wt")]))]
  names(glu) <- c("seqn", "lbxglu", "mec_fast_wt")
  
  if (layout$svy[svy] %in% c("1999_2000", "2001_2002", "2003_2004")) { 
    glu$lbxglu <- 0.9815*glu$lbxglu + 3.5707 # convert from Roche Cobras Mira method (used 1999-2004) to Roche/Hitachi 911 method
  } 
  if (layout$svy[svy] %in% c("1999_2000", "2001_2002", "2003_2004", "2005_2006")) { 
    glu$lbxglu <- glu$lbxglu + 1.148 # convert from Roche/Hitachi 911 method (used 2005-2006) to Roche ModP method (used 2007+)
  }
  
  ghb <- read.dta(paste(layout$dir[svy], layout$ghb_file[svy], sep="/"))
  names(ghb) <- tolower(names(ghb))
  ghb <- ghb[, c("seqn", as.character(layout[svy, "lbxgh"]))]
  names(ghb) <- c("seqn", "lbxgh")
  

## Merge files together ------------------------------------------------------------------------------------------------
  temp <- Reduce(function(x,y) merge(x, y, by="seqn", all=T), list(demo, diq, glu, ghb))        
  temp$seqn <- NULL 
  if (nrow(demo) != nrow(temp)) print(paste("warnings: respondents dropped or added in survey year", svy))
  data[[svy]] <- cbind(svyyear=layout$svyyear[svy], temp)
} 

## Collapse all data, make additional variables for treatement definitions, and save ------------------------------------------------------------------------------------------
data <- do.call("rbind", data)

#modify dataset to only the people we want
data <- data[data$age >= 12,]
data <- data[which(!is.na(data$lbxglu)),] # we need fasting plasma glucose and a1c for everyone
data <- data[which(!is.na(data$lbxgh)),]

#create new variables for 'on treatment' and satisfying each of the diabetes definitions:
data$treat <- 0 
data$treat[data$insulin==1 | (data$oralpills==1 & data$prediq!=1)] <-1 #create 'treatment' variable that is true only for known diabetics on treatment


#make new dataset of ratios, etc
diagnoses <- read.csv('diagnosis_def.csv',stringsAsFactors=F)

for (def_idx in 1:nrow(diagnoses)){
  diagnosis_name <- paste("diagnosis_", diagnoses[def_idx, "diagnosis"], sep="")
  condition <- diagnoses[def_idx, "condition"]
  cat(paste(diagnosis_name, "condition", condition, "\n")); flush.console()
  
  data[[diagnosis_name]] <- as.numeric(eval(parse(text=condition)))
  
}

#save microdata
data <- data[order(data$svyyear, data$sex, data$age),]
write.csv(data, file="../../data/01_pull_nhanes/diabetes_microdata_nhanes.csv") 

output <- sapply(paste0("diagnosis_", diagnoses$diagnosis), function(x) {
  table(data[[x]])
})

output<-data.frame(t(output))
names(output) <- c("total", "diabetes")
output$total = output$total + output$diabetes
output$prevalence = output$diabetes / output$total
output$prevalence_se = sqrt((output$prevalence*(1-output$prevalence)) / output$total)
output$prevalence_ratio = output$prevalence / output$prevalence[1] 
output$ratio_se = output$prevalence_ratio * sqrt( (output$prevalence_se/output$prevalence)^2 + (output$prevalence_se[1]/output$prevalence[1])^2 )

# we want the standard error for the reference category to be zero
output["diagnosis_ref", "ratio_se"]<-0


#save tabulated data
write.csv(output, file="strPath/diabetes_ratios_nhanes.csv") 
 

