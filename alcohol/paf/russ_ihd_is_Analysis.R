## For a particular year, age, sex, and cause group, generate the alcohol PAFs.


rm(list=ls()); library(foreign)

# For testing purposes, set argument values manually if in windows
if (Sys.info()["sysname"] == "Windows") {
  root <- "J:/"
  arg <- c(1995, 20, 2, "chronic", "C:/Users//Documents/repos/drugs_alcohol", "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs", "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp", 1, TRUE, 10, 10)
} else {
  root <- "/home/j/"
  print(paste(commandArgs(),sep=" "))
  arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
}


## Read in arguments passed in by shell script.
yyy <- as.numeric(arg[1])                     # Year for current analysis
aaa <- as.numeric(arg[2])                     # Age-group for current analysis (1=15-34, 2=35-64, 3=65+)
sss <- as.numeric(arg[3])                     # Sex for current analysis (1=male, 2=female)
ccc <- arg[4]                                 # cause group for current analysis
code.dir <- arg[5]                            # Code directory
data.dir <- arg[6]                            # Data directory
out.dir <- arg[7]                             # Directory to put temporary draws in
mycores <- as.numeric(arg[8])                 # Number of cores (which can be used to parallelize)
myverbose <- as.logical(arg[9])               # Whether to print messages to console showing progress
myB <- as.numeric(arg[10])            # Number of draws to run (higher than save to match EG methods)
mysavedraws <- as.numeric(arg[11])            # Number of draws to save


## get age from age_group_id
agemap <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv"))
age <- agemap$age[agemap$age_group_id == aaa]

## Prepare
## Read in exposure data
## more troubleshooting while J drive down data.file <- paste0("C:/Users/mcoates/Desktop/alc_data_1995.csv")
data.file <- paste0(data.dir, "/alc_data_", yyy, ".csv")
drkData <- read.csv(data.file)

##Change column 'location_id' to match Jurgen's
names(drkData)[names(drkData) == "location_id"] <- "REGION"
drkData <- drkData[,!names(drkData) %in% c("X","Unnamed..0")]


## Read in draws of age splitting
age.file <- paste0(out.dir,"/alc_age_frac_",yyy,"_",aaa,"_",sss,".csv")
agefrac <- read.csv(age.file)
# for testing agefrac <- read.csv(paste0("C:/Users/mcoates/Desktop/alc_age_frac_",yyy,"_",aaa,"_",sss,".csv"))
names(agefrac)[names(agefrac)=="year_id"] <- "year"
names(agefrac)[names(agefrac)=="sex_id"] <- "sex"
agefrac$age <- age


if (age < 34) agegroup <- 1
if (age > 34 & age < 59) agegroup <- 2
if (age > 59) agegroup <- 3

for (run in c("/rr/Russia_RR_IHD.R","/rr/Russia_RR_ISC_STROKE.R")) {
  
  ## Read in RR functions
  source(paste0(code.dir, run))
  if(sss == 1) {
    relativerisk <- relativeriskmale[agegroup]
  } else {
    relativerisk <- relativeriskfemale[agegroup]
  }
  
  ## Read in AAF calculation functions
  aaf.code <- paste0(code.dir, "/03_2_chronicAAF.R")
  source(aaf.code)
  
  drkData <- drkData[drkData$REGION %in% c(57,58,59,60,61,62,63),]
  

## Run PAF code for this group and save
set.seed(10 * sss + aaa) # Set unique seed for each age/sex group.
system.time(
  AAFConfint <- confintAAF(data = drkData, agefrac=agefrac, disease = relativerisk, B = myB, gender = sss, age = age, adjustPCA = 0.8, mc.cores = mycores, verbose = myverbose, saveDraws = mysavedraws)
)
AAFConfint$age <- age
if (run == "/rr/Russia_RR_IHD.R") IHD <- AAFConfint
}
AAFConfint <- rbind(AAFConfint,IHD)
## AAFConfint <- AAFConfint[AAFConfint$REGION %in% c("BLR", "RUS", "UKR","EST", "LVA", "LTU","MDA"),]
AAFConfint <- AAFConfint[AAFConfint$REGION %in% c(57,58,59,60,61,62,63),]


write.csv(AAFConfint, file = paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s", sss, "_russ_ihd_is.csv"))
