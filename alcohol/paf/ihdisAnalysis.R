### NOTE concerning age groups:                                            ###
### in the case of IHD, the RRs are different for each age group           ###
### so when setting up the GROUP variable, keep in mind that the output    ###
### will be given separately by age group. If an aggregate AAF across age  ###
### groups is to be evaluated at the end, all 3 age groups should          ###
### consistently be present for each country in each GROUP.                ###

rm(list=ls()); library(foreign)

	# For testing purposes, set argument values manually if in windows
	if (Sys.info()["sysname"] == "Windows") {
	  root <- "J:/"
		arg <- c(2005, 11, 2, "ihd", "C:/Users/strUser/Documents/repos/drugs_alcohol", "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs", "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp", 1, TRUE, 10, 10)
		## for manual cluster session arg <- c(2010, 1, 1, "ihd", "/home/j/WORK/05_risk/01_database/02_data/drugs_alcohol/04_paf/04_models/code", "/home/j/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/output", "/clustertmp/gregdf/alcohol_temp", 1, TRUE, 10, 10)
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
	mycores <- 1 #as.numeric(arg[8])                 # Number of cores (which can be used to parallelize)
	myverbose <- as.logical(arg[9])               # Whether to print messages to console showing progress
	myB <- as.numeric(arg[10])            # Number of draws to run (higher than save to match EG methods)
	mysavedraws <- as.numeric(arg[11])            # Number of draws to save


## get age from age_group_id
agemap <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv"))
age <- agemap$age[agemap$age_group_id == aaa]




#if(test_data=="y"){
## for the calculation of the bootstrap confidence intervals:
## set a seed to make these results reproducable
## set number of Bootstrap samples B and number of cores
#mycores <- as.numeric(readline("set number of cores: ")) ## should be 1 for windows machines
#myB <- as.numeric(readline("set number of samples: ")) ## should be between 40'000 - 100'000
#myverbose <- TRUE
#MyTestStatus <- readline("Perform the coherence check for the proportion of bingers?
#If not, the proportion of bingers among drinkers will be set to the prevalence of
#drinking 60g/day or more if the input value is smaller than that. [yes/no]: ")


## load functions
library(foreach)
#library(doParallel)


## This will make the code break if the proportion of bingers is smaller than the proportion of people who drink 60+ g/day
## Those who drink that much automatically qualify as bingers, so it should never be smaller
MyTestStatus <- "no" ## now replacing with > 60 g/day if > bingers


## Read in exposure data
data.file <- paste0(data.dir, "/alc_data_", yyy, ".csv")
drkData <- read.csv(data.file)

##Change column 'location_id' to match Jurgen's
names(drkData)[names(drkData) == "location_id"] <- "REGION"
drkData <- drkData[,!names(drkData) %in% c("X","Unnamed..0")]
drkData$GROUP <- row.names(drkData)




## load information on relative risks for various diseases, make sure right sex files here
source(paste0(code.dir, "/rr/",ccc,"RR.R"))
	if(sss == 1) {
			relativerisk <- relativeriskmale

		} else {
			relativerisk <- relativeriskfemale
		}

## Read in draws of age splitting
age.file <- paste0(out.dir,"/alc_age_frac_",yyy,"_",aaa,"_",sss,".csv")
agefrac <- read.csv(age.file)
# for testing agefrac <- read.csv(paste0("C:/Users/mcoates/Desktop/alc_age_frac_",yyy,"_",aaa,"_",sss,".csv"))
names(agefrac)[names(agefrac)=="year_id"] <- "year"
names(agefrac)[names(agefrac)=="sex_id"] <- "sex"
agefrac$age <- age

    source(paste0(code.dir, "/ischemicstroke_ihd_AAF.R"))
    
    
## calculate AAF draws for morbidity and mortality
## Men, age category 1
set.seed(10 * sss + aaa + 2)
system.time(
AAFConfint <- confintAAF(data = drkData, agefrac=agefrac, disease = relativerisk, B = myB, verbose = myverbose, mc.cores = mycores,gender = sss,
                            age = age, adjustPCA = 0.8,TestStatus=MyTestStatus,saveDraws=mysavedraws)
)
# }
write.csv(AAFConfint, file = paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s", sss, "_", ccc, ".csv"))








