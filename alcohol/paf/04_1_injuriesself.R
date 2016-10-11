############# This program will compute the Alcohol Attributable Fractions (AAF) for the diseases listed
############# below. It requires an input file (in simple .txt format). Select the age category to be evaluated here:
rm(list=ls()); library(foreign)

### pass in arguments
	# For testing purposes, set argument values manually if in windows
	if (Sys.info()["sysname"] == "Windows") {
	  root <- "J:/"
	  arg <- c(1990, 21, "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs", "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp", 100, 100)
	} else {
	  root <- "/home/j/"
	  print(paste(commandArgs(),sep=" "))
	  arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
	}
	

	yyy <- as.numeric(arg[1])                     # Year for current analysis
	aaa <- as.numeric(arg[2])                     # Age-group for current analysis (1=15-34, 2=35-64, 3=65+)
	data.dir <- arg[3]                            # Data directory
	out.dir <- arg[4]                             # Directory to put temporary draws in
	nnn <- as.numeric(arg[5])                     # Number of draws to run (higher than save to match EG methods)
	save.draws <- as.numeric(arg[6])              # Number of draws to save

	## get age from age_group_id
	agemap <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv"))
	AGE <- agemap$age[agemap$age_group_id == aaa]
   
  
	age.file.m <- paste0(out.dir,"/alc_age_frac_",yyy,"_",aaa,"_1.csv")
	age.file.f <- paste0(out.dir,"/alc_age_frac_",yyy,"_",aaa,"_2.csv")
  agefracm <- read.csv(age.file.m,stringsAsFactors=F)
  agefracf <- read.csv(age.file.f,stringsAsFactors=F)
  
  ## troubleshoot
# 	agefracm <- read.csv(paste0("C:/Users/mcoates/Desktop/alc_age_frac_",yyy,"_",aaa,"_1.csv"),stringsAsFactors=F)
# 	agefracf <- read.csv(paste0("C:/Users/mcoates/Desktop/alc_age_frac_",yyy,"_",aaa,"_2.csv"),stringsAsFactors=F)
  names(agefracm)[names(agefracm)=="year_id"] <- "year"
  names(agefracm)[names(agefracm)=="sex_id"] <- "sex"
  agefracm$age <- AGE
  
  names(agefracf)[names(agefracf)=="year_id"] <- "year"
  names(agefracf)[names(agefracf)=="sex_id"] <- "sex"
  agefracf$age <- AGE
  

##### SELECTING SEED BASED ON AGE CATEGORY ######
##### SELECTING SEED BASED ON AGE CATEGORY ######
##### SELECTING SEED BASED ON AGE CATEGORY ######

SEEDS <- c(11,12,13,21,22,23)
SEED_MALE <- c(AGE)
SEED_FEMALE <- c(AGE+14)

##### SELECTING THE NUMBER OF SAMPLES ####
##### SELECTING THE NUMBER OF SAMPLES ####
##### SELECTING THE NUMBER OF SAMPLES ####

### These two variables set the amount of samples that will be used by the program ####
### to estimate the variances. As R has trouble handling large data sets, it is    ####
### much faster to split this process up in 2 steps. A number mmmm of sets will be ####
### generated, each containing the information of nnn samples. As at least 40'000  ####
### samples are necessary, by default, 20 sets of 2000 samples will be created     ####
### the names of the output files containing the separate information is given in  ####
### the input file "filenames.txt".                                                ####

### IHME - Do not set mmmm to more than 1. Also nnn must be greater than or equal to save.draws
### mmmm setting removed.



##### DEFINITION OF RELATIVE RISK FUNCTIONS #####
##### DEFINITION OF RELATIVE RISK FUNCTIONS #####
##### DEFINITION OF RELATIVE RISK FUNCTIONS #####

############# Definition of Relative Risk Functions as well as the Variances and Covariances of the parameters  ###########
############# In order to use them in a loop, we need a constant type in which we will store the parameters     ###########
############# As there are 4 different functions: sqrt(x), x, x^2 and x^3 we will use 4 beta parameters for     ###########
############# each RR function. If the function only has a few of there terms, the other coefficients will      ###########
############# simply equal zero. The cross correlation terms will also be voided. Hence each function will have ###########
############# its 4x4 matrix including all the needed information.                                              ###########
############# The beta coefficients will represent respectively the coeffients for  sqrt(x), x, x^2 and x^3     ###########


############# Note: the Relative Risk functions have sometimes been changed at the extremities, therefore, in   ###########
############# order to be able to simulate our RR functions with different beta parameters, the easiest is to   ###########
############# change the functions parameters compared to the previous ones. Namely, instead of being only a    ###########
############# function of x, the relative risk functions will be functions of x and the different betas.        ###########
############# To calculate the Confidence Intervals, we will therefore first generate the beta coefficients     ###########
############# and then plug them into our Relative Risk function that we can use to calculate the AAFs.          ###########


####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ########
####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ########
####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ########
####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ######## ####### IMPORTANT REMARK ########

  
#################################################################################################
###  The following relative risk functions are for morbidity only. The AAFs for mortality are ###
### obtained from the AAFs for morbidity with the following relations:                        ###
### 
###   
###   Men:
###   AAF MVA mortality = AAF MVA morbidity                                                    ###
###   AAF non-MVA mortality = AAF non-MVA morbidity                                            ###
###                                                                                            ###
###   Women:                                                                                   ###
###   AAF MVA morbidity = AAF calculated from male RR and female consumption                   ###
###   AAF MVA mortality = AAF MVA morbidity                                                    ###
###   AAF non-MVA mortality = AAF non-MVA morbidity                                            ###
###
###                                       ###
#################################################################################################


  

  
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

#### FEMALE ####

RRnonmvafe =function(x,beta1,beta2,beta3,beta4) ifelse(x>=0,ifelse(x>=20,(exp(beta1*((((x*1.5)-20+ 0.0039997100830078)/100)^0.5))+exp(beta1*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2,(exp(0)+exp(beta1*((((x*1.5)+20+ 0.0039997100830078)/100)^0.5)))/2 ),0)
nonmvafebetas = c(2.187789, 0 ,0, 1)
nonmvafecovar = matrix(c(0.0627259,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0),4,4)
lnRRnonmvafeform= 0
lnRRnonmvafeformvar= 0

RRnonmvafecap = function(x,beta1,beta2,beta3,beta4) {ifelse(x<RRcap,RRnonmvafe(x,beta1,beta2,beta3,beta4),RRnonmvafe(RRcap,beta1,beta2,beta3,beta4)) }

NONMVA_female = list ("NON-Motor Vehicle Accidents - Morbidity - WOMEN", RRnonmvafecap, nonmvafebetas, nonmvafecovar,lnRRnonmvafeform,lnRRnonmvafeformvar)

################ Creating a list of all the diseases ####################

relativeriskmale = list(MVA_male ,  NONMVA_male  )

relativeriskfemale = list(MVA_female, NONMVA_female  )


### RR Multiplier ##
RRM <- 1.0


#################âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž   INPUT FILE   âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž#############################
#################âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž   INPUT FILE   âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž#############################
#################âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž   INPUT FILE   âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž#############################
#################âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž   INPUT FILE   âˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆžâˆž#############################

############ Reading in and Formatting the input file #############
############ Reading in and Formatting the input file #############

######## The inputs are as follows:
######## REGION - SEX - AGE CATEGORY - %LIFETIME ABSTAINERS - %FORMER DRINKERS - %DRINKERS - POPULATION WEIGHT - RELATIVE COEFFICIENT - PCA (by sex) - SE of PCA
##### The AGE_CATEGORY variables have to be numbers. This is required in order for the program to recognise the different categories automatically. This will enable
##### us to change the number of age categories at any time


##### ATTENTION: PCA HAS TO BE GIVEN IN LITRES/YEAR!!! IT IS ALSO A REDUNDANT NUMBER INSIDE EACH REGION AS IT REPRESENTS THE TOTAL PCA OF THE REGION IN QUESTON.
##### IT IS KEPT REDUNDANT ONLY FOR THE SIMPLICITY OF THE PROGRAM DESIGN.
##### IN ADDITION TO THAT, THE PROGRAM WILL TAKE THE 80% OF THE INPUT PCA

## MAKING AN ADDITION MC 12/13/14
## WE HAVE NOW EXTRACTED AGE DISTRIBUTION OF CONSUMPTION IN FINER AGE GROUPS
## IN ORDER TO RUN ANALYSIS FOR THESE AGE GROUPS, ADJUSTING THE WAY THE CODE HANDLES AGE
if (AGE < 34) agegroup <- 1
if (AGE > 34 & AGE < 59) agegroup <- 2
if (AGE > 59) agegroup <- 3

## Read in exposure data
data.file <- paste0(data.dir, "/alc_data_", yyy, ".csv")
input <- read.csv(data.file,stringsAsFactors=F)
##Change column 'location_id' to match Jurgen's
names(input)[names(input) == "location_id"] <- "REGION"
input <- input[,!names(input) %in% c("X","Unnamed..0")]

inputm = input[input$SEX==1,] ####### male dataset
inputmage=inputm[inputm$AGE_CATEGORY==agegroup,]
inputf = input[input$SEX==2,] ####### female dataset
inputfage=inputf[inputf$AGE_CATEGORY==agegroup,]
prop_abs_male = inputmage$LIFETIME_ABSTAINERS
prop_form_male = inputmage$FORMER_DRINKERS
BINGERS_MALES = as.numeric(inputmage$BINGERS)
BINGE_TIMES_MALES = as.numeric(inputmage$BINGE_TIMES)
IM = as.numeric(inputmage$BINGE_A)

#### the list of regions will be used to compute the mean values ####
#### indeed, each region has 6 different entries (2x3) for sex   ####
#### and age group). We therefore need a non redundant list of   ####
#### the regions. we will also have a list of the age categories ####
#### in case we want to compute the results for more than one at ####
#### a time.                                                     ####
agecategories_male=unique(inputmage$AGE_CATEGORY)
regions_male = unique(inputmage$REGION)
n_agecategories_male = length(agecategories_male)

######## Determining the MEAN values #########
######## Determining the MEAN values #########
######## Determining the MEAN values #########

#### the generation of the mean values will need the use of a function ####
#### which we will be able to re-use for the CI by generating random   ####
#### inputs and returning the output.			                 ####

#### p1,p2 and p3 are the size of populations, a,b and c the relative coefficients; 								  ####
#### the proportion of drinkers is directly related to the proportions of abstainers and former drinkers. the rest is straightforward ####
#### THE OUTPUT IS A VECTOR OF THE X MEAN VALUES CORRESPONDING TO THE X AGE GROUPS.                   					  ####
compute_mu=function(popsize, age_fraction, pabs, pformer, pca)
{

  if (age_fraction[1] < 34) agegroup <- 1
  if (age_fraction[1] > 34 & age_fraction[1] < 59) agegroup <- 2
  if (age_fraction[1] > 59) agegroup <- 3

  ## NORMAL PCA ADJUSTMENT THAT'S DONE HERE IN OTHER CODE IS DONE FARTHER DOWN HERE IN INPUT STAGE

  ## percent of drinkers in each age group
  pdrk <- (1 - pabs - pformer)
  ## alcohol consumption total is just per capita consumption times population
  tot <- pca * sum(popsize)
  ## consumption total in this age group is total consumption times fraction of total consumption in this age
  cons_age <- tot*age_fraction[3]
  ## consumption per drinker in this age group is consumption in this age group divided by the number of drinkers
  mu <- cons_age/(pdrk[agegroup]*age_fraction[2])
  mu <- unlist(mu)

}

# The idea is to create a vector with NAs at the beginning and then fill it. Then you don't have to use the combine-command so often which slows things down.
mean_male=rep(NA, length = length(regions_male)*n_agecategories_male)


for (i in 1:length(regions_male))
{

  #### extracting the required information for each region ####
  info_male_region = inputm[inputm$REGION==regions_male[i],]

  #### subset the age fraction file for the right region
  ragefracm <- agefracm[agefracm$location_id == regions_male[i],]

  #### calculating the mean values for each group
  population = info_male_region$POPULATION
  coeffs=info_male_region$RELATIVE_COEFFICIENT
  prop_abs=info_male_region$LIFETIME_ABSTAINERS
  prop_form = info_male_region$FORMER_DRINKERS
  pcalitresperyear=info_male_region$PCA[1]  #### the three values for pca are redundant (one value only for the whole region), the choice to take the first one is arbitrary of course
  pcagramsperday=pcalitresperyear*1000*0.789*0.8/365   #### This is to calculate the 80% pca
  pca=pcagramsperday

  mean_region = compute_mu(population,age_fraction=ragefracm[,c("age","pop_scaled","mean_frac")],prop_abs,prop_form,pca)
  mean_male[i] = mean_region
}

mean_male_store = mean_male

#### The people are separated as follows: bingers and non-bingers.
#### The bingers do not binge every day. THe AAF will be calculated easily in 2 categories: mean consumption times risk, and binge drinkers on their occasions with RR associated to binge drinking
#### The proportion of 60+ drinkers will simply be the AAF above times the prevalence of drinking 60+ (assuming no different risk for these people) thus simply assuming the AAF is the same for every comsumption value.
#### This should possibly be changed in the future so that those over 60 g/day count as bingers... however, it doesn't make sense to call them
#### bingers now because this still uses Juergen's binge amounts and subtracts out binge consumption from normal consumption
#### If we treated 60+ as binge, we'd have to do the the gamma earlier, then recalculate another gamma after subtracting those out? But could still end up with
## some over 60- I think method would need to be changed to change the approach here...
BINGE_Intake = IM*BINGE_TIMES_MALES*BINGERS_MALES

BINGE_Intake <- ifelse(BINGE_Intake>=mean_male, mean_male-0.1, BINGE_Intake)

mean_male_corrected = mean_male-(BINGE_Intake)

### This is the average daily consumption of all but the bingers
AVERAGENBDAYCONSUMPTION = mean_male_corrected/(1-BINGERS_MALES*BINGE_TIMES_MALES)


mean_male = AVERAGENBDAYCONSUMPTION



sd_male = 1.171*mean_male

k_male = mean_male^2/sd_male^2
theta_male = sd_male^2/mean_male


nmale = length (mean_male)     ##### number of different distributions corresponding to male populations



################### Calculation of AAF for male population ########################
################### Calculation of AAF for male population ########################
################### Calculation of AAF for male population ########################

#### Time functions


TIME_AT_RISK_OCC_FUNC_MALES_BINGE = function (x) {((24/(48.2725*((x/12)^-1.143)))/24)}

TIME_AT_RISK_OCC_FUNC_BINGE_AVG = function (x) { ((24/(48.2725*((x/12)^-1.143)))/24)}

TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG = function (x) {((24/(48.2725*((x/12)^-1.143)))/24)}

#### male population ####
AAFinfolistmale = data.frame(matrix(NA, nrow=nmale*length(relativeriskmale), ncol=6))
names(AAFinfolistmale) = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAFmorb", "AAFmort")
system.time(
  for (i in 1:nmale) ### Group Loop
  {



    ### Average for non binge drinkers ###

    ######## normalising gamma function ##############
    #### un-normalised gamma function
    #prevalencegamma = function(x) {dgamma(x,shape=k_male[i],scale=theta_male[i])}
    #ncgamma1 = integrate(prevalencegamma, lower = 0.1, upper = 150)    # str(ncgamma1) tells you it's a list of 5 and the value can be accessed via ncgamma1$value
    #prevgamma=function(x){(1/ncgamma1$value)*prevalencegamma(x)*x}

    #### filling the data frame with the group specific information
    n_diseasemale = length(relativeriskmale)
    AAFinfolistmale$REGION[(((i-1)*n_diseasemale)+1):(i*n_diseasemale)] <- inputmage$REGION[i]
    AAFinfolistmale$SEX[(((i-1)*n_diseasemale)+1):(i*n_diseasemale)] <- inputmage$SEX[i]
    AAFinfolistmale$AGE_CATEGORY[(((i-1)*n_diseasemale)+1):(i*n_diseasemale)] <- inputmage$AGE_CATEGORY[i]
    AAFinfolistmale$age[(((i-1)*n_diseasemale)+1):(i*n_diseasemale)] <- AGE


    #### Calculation of the AAFs for all disease categories ####

    for (p in 1:n_diseasemale)  ### Disease Loop
    {
      ## find normalizing constant
      normConst <- integrate(dgamma, lower = 0.1, upper = 150, shape = k_male[i],scale = theta_male[i])$value

      betas <- relativeriskmale[[p]][[3]]
      non_binging <- (1 - prop_abs_male[i] - prop_form_male[i])*(1-BINGERS_MALES[i]*BINGE_TIMES_MALES[i])/normConst *
            integrate(function(x){
            dgamma(x, shape = k_male[i],scale = theta_male[i]) *
            ((relativeriskmale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
            (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)
          }, lower = 0.1, upper = 150)$value

        #curvea <-function(x){
        #    dgamma(x, shape = k_male[i],scale = theta_male[i]) *
        #    ((relativeriskmale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
        #    (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)}
        #plot(curvea,xlim=c(0,150))
        #curve(relativeriskmale[[p]][[2]](x,beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4]),xlim=c(0,150))

      DRINKERSM = 1- prop_abs_male[i] - prop_form_male[i]
      #non_binging = DRINKERSM*(1-BINGERS_MALES[i]*BINGE_TIMES_MALES[i])*
      #((RRM*(relativeriskmale[[p]][[2]](mean_male[i],relativeriskmale[[p]][[3]][1],relativeriskmale[[p]][[3]][2],relativeriskmale[[p]][[3]][3],relativeriskmale[[p]][[3]][4]))-1)*
      #(TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(mean_male[i])) +1 )
      binging=DRINKERSM*(BINGE_TIMES_MALES[i]*BINGERS_MALES[i])*((RRM*(relativeriskmale[[p]][[2]](IM[i],relativeriskmale[[p]][[3]][1],relativeriskmale[[p]][[3]][2],relativeriskmale[[p]][[3]][3],relativeriskmale[[p]][[3]][4]))-1)*TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(IM[i])+1)
      AAFmaleden=(prop_abs_male[i] + prop_form_male[i]+binging+non_binging)
      AAFgammamale=(AAFmaleden-1)/(AAFmaleden)

      ##### creating a list of all information, the list contains: ####

      ##### filling the dataframe with the disease specific information
      AAFinfolistmale$DISEASE[((i-1)*n_diseasemale+p)] <- relativeriskmale[[p]][[1]]
      AAFinfolistmale$AAFmorb[((i-1)*n_diseasemale+p)] <- AAFgammamale


      #### Applying the multiplication factors to the right diseases ####
      #### we'll also apply the 90% cap on mortality here            ####

      if (AAFinfolistmale$DISEASE[((i-1)*n_diseasemale+p)]=="Motor Vehicle Accidents - Morbidity - MEN")
      {
        # AAFinfolistmale$AAFmort[((i-1)*n_diseasemale+p)] <- ifelse (3/2*AAFgammamale<=0.9,3/2*AAFgammamale, 0.9)
        AAFinfolistmale$AAFmort[((i-1)*n_diseasemale+p)] <- ifelse (AAFgammamale<=0.9,AAFgammamale, 0.9)
      } else if (AAFinfolistmale$DISEASE[((i-1)*n_diseasemale+p)]=="NON-Motor Vehicle Accidents - Morbidity - MEN")
      {
        # AAFinfolistmale$AAFmort[((i-1)*n_diseasemale+p)] <- ifelse (9/4*AAFgammamale<=0.9,9/4*AAFgammamale, 0.9)
        AAFinfolistmale$AAFmort[((i-1)*n_diseasemale+p)] <- ifelse (AAFgammamale<=0.9,AAFgammamale, 0.9)
      }

    }### loop p, representing the diseases


  }###loop i, representing the different groups
) ### HF: end of system.time




############# FEMALES ############# ############# FEMALES ############# ############# FEMALES #############
############# FEMALES ############# ############# FEMALES ############# ############# FEMALES #############
############# FEMALES ############# ############# FEMALES ############# ############# FEMALES #############
############# FEMALES ############# ############# FEMALES ############# ############# FEMALES #############
############# FEMALES ############# ############# FEMALES ############# ############# FEMALES #############


prop_abs_female = inputfage$LIFETIME_ABSTAINERS
prop_form_female = inputfage$FORMER_DRINKERS
BINGERS_FEMALES = as.numeric(inputfage$BINGERS)
BINGE_TIMES_FEMALES = as.numeric(inputfage$BINGE_TIMES)
IM = as.numeric(inputfage$BINGE_A)

#### the list of regions will be used to compute the mean values ####
#### indeed, each region has 6 different entries (2x3) for sex   ####
#### and age group). We therefore need a non redundant list of   ####
#### the regions. we will also have a list of the age categories ####
#### in case we want to compute the results for more than one at ####
#### a time.                                                     ####

agecategories_female=unique(inputfage$AGE_CATEGORY)
regions_female = unique(inputfage$REGION)
n_agecategories_female = length(agecategories_female)
  

######## Determining the MEAN values #########
######## Determining the MEAN values #########
######## Determining the MEAN values #########


# The idea is to create a vector with NAs at the beginning and then fill it. Then you don't have to use the combine-command so often which slows things down.
mean_female=rep(NA, length = length(regions_female)*n_agecategories_female)

for (i in 1:length(regions_female))
{
  #### extracting the required information for each region ####
  info_female_region = inputf[inputf$REGION==regions_female[i],]
  ragefracf <- agefracf[agefracf$location_id == regions_female[i],]

  #### calculating the mean values for each group
  population = info_female_region$POPULATION
  coeffs=info_female_region$RELATIVE_COEFFICIENT
  prop_abs=info_female_region$LIFETIME_ABSTAINERS
  prop_form = info_female_region$FORMER_DRINKERS
  pcalitresperyear=info_female_region$PCA[1]  #### the three values for pca are redundant (one value only for the whole region), the choice to take the first one is arbitrary of course
  pcagramsperday=pcalitresperyear*1000*0.789*0.8/365   #### This is to calculate the 80% pca
  pca=pcagramsperday

  mean_region = compute_mu(popsize=population,age_fraction=ragefracf[,c("age","pop_scaled","mean_frac")],pabs=prop_abs,pformer=prop_form,pca=pca)
  mean_female[i] = mean_region
}

mean_female_store = mean_female

#### The people are separated as follows: bingers and non-bingers.
#### The bingers do not binge every day. THe AAF will be calculated easily in 2 categories: mean consumption times risk, and binge drinkers on their occasions with RR associated to binge drinking
#### The proportion of 60+ drinkers will simply be the AAF above times the prevalence of drinking 60+ (assuming no different risk for these people) thus simply assuming the AAF is the same for every comsumption value.


BINGE_Intake = IM*BINGE_TIMES_FEMALES*BINGERS_FEMALES
BINGE_Intake <- ifelse(BINGE_Intake>=mean_female, mean_female-0.1, BINGE_Intake)
mean_female_corrected = mean_female-(BINGE_Intake)

### This is the average daily consumption of all but the bingers
AVERAGENBDAYCONSUMPTION = mean_female_corrected/(1-BINGERS_FEMALES*BINGE_TIMES_FEMALES)
mean_female = AVERAGENBDAYCONSUMPTION


sd_female = 1.258*mean_female

k_female = mean_female^2/sd_female^2
theta_female = sd_female^2/mean_female


nfemale = length (mean_female)     ##### number of different distributions corresponding to male populations



################### Calculation of AAF for female population ########################
################### Calculation of AAF for female population ########################
################### Calculation of AAF for female population ########################

#### Time functions


TIME_AT_RISK_OCC_FUNC_FEMALES_BINGE = function (x) {((24/(48.2725*((x/12)^-1.143)))/24)}

TIME_AT_RISK_OCC_FUNC_BINGE_AVG = function (x) {((24/(48.2725*((x/12)^-1.143)))/24)}

TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG = function (x) {((24/(48.2725*((x/12)^-1.143)))/24)}



# AAFinfolistfemale = data.frame(matrix(NA, nrow=nfemale*2*length(relativeriskfemale), ncol=6))

AAFinfolistfemale = data.frame(matrix(NA, nrow=nfemale*length(relativeriskfemale), ncol=6))
names(AAFinfolistfemale) = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAFmorb","AAFmort")
system.time(
  for (i in 1:nfemale) ### Group Loop
  {
    ### Average for non binge drinkers ###
    ######## normalising gamma function ##############
    #### un-normalised gamma function
    prevalencegamma = function(x) {dgamma(x,shape=k_female[i],scale=theta_female[i])}
    ncgamma1 = integrate(prevalencegamma, lower = 0.1, upper = 150)    # str(ncgamma1) tells you it's a list of 5 and the value can be accessed via ncgamma1$value
    prevgamma=function(x){(1/ncgamma1$value)*prevalencegamma(x)*x}


    #### filling the data frame with the group specific information
    n_diseasefemale = length(relativeriskfemale)
    AAFinfolistfemale$REGION[(((i-1)*n_diseasefemale)+1):(i*n_diseasefemale)] <- inputfage$REGION[i]
    AAFinfolistfemale$SEX[(((i-1)*n_diseasefemale)+1):(i*n_diseasefemale)] <- inputfage$SEX[i]
    AAFinfolistfemale$AGE_CATEGORY[(((i-1)*n_diseasefemale)+1):(i*n_diseasefemale)] <- inputfage$AGE_CATEGORY[i]
    AAFinfolistfemale$age[(((i-1)*n_diseasefemale)+1):(i*n_diseasefemale)] <- AGE

    #### Calculation of the AAFs for all disease categories ####

    for (p in 1:n_diseasefemale)  ### Disease Loop
    {
      #### the "integral" function is as follows: prevgamma(x){[(Coeff*RR(x)-1]*time_at_risk + 1} = prevgamma(x)[Coeff*RR(x)*time_at_risk + (1 - time_at_risk) ]

      normConst <- integrate(dgamma, lower = 0.1, upper = 150, shape = k_female[i],scale = theta_female[i])$value

      betas <- relativeriskfemale[[p]][[3]]
      non_binging <- (1 - prop_abs_female[i] - prop_form_female[i])*(1-BINGERS_FEMALES[i]*BINGE_TIMES_FEMALES[i])/normConst *
            integrate(function(x){
            dgamma(x, shape = k_female[i],scale = theta_female[i]) *
            ((relativeriskfemale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
            (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)
          }, lower = 0.1, upper = 150)$value

        #curvea <-function(x){
        #    dgamma(x, shape = k_male[i],scale = theta_male[i]) *
        #    ((relativeriskmale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
        #    (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)}
        #plot(curvea,xlim=c(0,150))
        #curve(relativeriskmale[[p]][[2]](x,beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4]),xlim=c(0,150))

      DRINKERSF = 1- prop_abs_female[i] - prop_form_female[i]
      #non_binging = DRINKERSF*(1-BINGERS_FEMALES[i]*BINGE_TIMES_FEMALES[i])*((RRM*(relativeriskfemale[[p]][[2]](mean_female[i],relativeriskfemale[[p]][[3]][1],relativeriskfemale[[p]][[3]][2],relativeriskfemale[[p]][[3]][3],relativeriskfemale[[p]][[3]][4]))-1)*(TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(mean_female[i])) +1 )
      binging=DRINKERSF*(BINGE_TIMES_FEMALES[i]*BINGERS_FEMALES[i])*((RRM*(relativeriskfemale[[p]][[2]](IM[i],relativeriskfemale[[p]][[3]][1],relativeriskfemale[[p]][[3]][2],relativeriskfemale[[p]][[3]][3],relativeriskfemale[[p]][[3]][4]))-1)*TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(IM[i])+1)

      AAFfemaleden=(prop_abs_female[i] + prop_form_female[i]+binging+non_binging)
      AAFgammafemale=(AAFfemaleden-1)/(AAFfemaleden)

      ##### creating a list of all information, the list contains: ####

      ##### filling the dataframe with the disease specific information
      AAFinfolistfemale$DISEASE[((i-1)*n_diseasefemale+p)] <- relativeriskfemale[[p]][[1]]
      AAFinfolistfemale$AAFmorb[((i-1)*n_diseasefemale+p)] <- AAFgammafemale

    }### loop p, representing the diseases


  }###loop i, representing the different groups
) ### HF: end of system.time

	


for (i in 1:(nrow(AAFinfolistfemale))) ### Group Loop
{
  AAFgammafemale=AAFinfolistfemale$AAFmorb[i]

  #### filling in mortality data
  if (AAFinfolistfemale$DISEASE[i]==toString("Motor Vehicle Accidents - Morbidity - WOMEN"))
  {
    # AAFinfolistfemale$AAFmort[i] <- ifelse (3/2*AAFgammafemale<=0.9,3/2*AAFgammafemale, 0.9)
    AAFinfolistfemale$AAFmort[i] <- ifelse (AAFgammafemale<=0.9,AAFgammafemale, 0.9)
  } else if (AAFinfolistfemale$DISEASE[i]==toString("NON-Motor Vehicle Accidents - Morbidity - WOMEN"))
  {
    # AAFinfolistfemale$AAFmort[i] <- ifelse (9/4*AAFgammafemale<=0.9,9/4*AAFgammafemale, 0.9)
    AAFinfolistfemale$AAFmort[i] <- ifelse (AAFgammafemale<=0.9,AAFgammafemale, 0.9)
  }

}#loop i
##### Printing output and writing to file #####
##### Printing output and writing to file #####

### IHME: Don't save the point estimate file, because the PE exists in the final file.


################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################


### m is the number of different sets of nnn points that will be computed

set.seed(SEED_MALE)

  ####°°°° MALE SIMULATIONS °°°°####
  ####°°°° MALE SIMULATIONS °°°°####
  ####°°°° MALE SIMULATIONS °°°°####



{





  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####
  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####
  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####

  #### generating proportions of abstainers, former drinkers and drinkers. This is a binomial distribution considering a survey with 1'000 data points per sex-age group.
  #### the output matrix is ordered in the following way: each line represents the 10'000 generated parameters for one group.
  #### in order to compute the mean values we need the prop_abstainers for each region. To avoid 2 calculations these are combined together


  prop_abs_listmale = NULL
  prop_form_listmale = NULL
  prop_drk_listmale = NULL
  mean_male_store_list=NULL
  mean_male_list_temp=NULL
  mean_male_list=NULL
  mean_male_corrected_list=NULL
  mean_male_list_region=NULL
  BINGERS_MALES_list=NULL
  BINGE_TIMES_MALES_list=NULL
  IM_list=NULL

  BINGE_INTAKE_list=data.frame(matrix(NA, nrow=length(regions_male), ncol=nnn))

  ###### THIS PART USES ALL 3 AGE CATEGORIES TO SIMULATE THE MEAN VALUES
  ###### ALL OTHER VALUES ARE ONLY GENERATED FOR A GIVEN REGION DEFINED IN "inputmage"

  system.time(
    for (i in 1:length(regions_male))
    {
      #### extracting the required information for each region ####
      info_male_regionage = inputmage[inputmage$REGION==regions_male[i],]
      info_male_region = inputm[inputm$REGION==regions_male[i],]

##    ## adding the age split dataset
      agefrac_male_region <- agefracm[agefracm$location_id == regions_male[i],]

      #### calculating the mean values for each group
      population = info_male_region$POPULATION
      coeffs=info_male_region$RELATIVE_COEFFICIENT
      pcalitresperyear=info_male_region$PCA[1]
      var_pca=info_male_region$VAR_PCA[1]

      #### generating random values for pca
      pca_listlitresperyear=rnorm(nnn, pcalitresperyear, sqrt(var_pca))

      #### the following is to avoid having negative numbers as PCAs due to the random distribution.

      for (h in 1:length(pca_listlitresperyear))
      {
        if (pca_listlitresperyear[h]<=0.001)
        {
          pca_listlitresperyear[h]=0.001
        }

      }
      pca_list=0.8*pca_listlitresperyear*1000*0.789/365
      mean_male_list_region=prop_abs_listmale_region=prop_form_listmale_region=NULL ### obviously, this has to be reinitialised at each region iteration

      for (k in 1:length(info_male_region$AGE_CATEGORY)) #### this should usually be from 1 to 3
      {
        pabs=rnorm(nnn,info_male_region$LIFETIME_ABSTAINERS[k],sqrt(info_male_region$LIFETIME_ABSTAINERS[k]*(1-info_male_region$LIFETIME_ABSTAINERS[k])/1000))
        pform=rnorm(nnn,info_male_region$FORMER_DRINKERS[k], sqrt(info_male_region$FORMER_DRINKERS[k]*(1-info_male_region$FORMER_DRINKERS[k])/1000))
        pdrink=rnorm(nnn,info_male_region$DRINKERS[k], sqrt(info_male_region$DRINKERS[k]*(1-info_male_region$DRINKERS[k])/1000))

        pdrink[pdrink < 0.001] <- 0.001
        pform[pform < 0.001] <- 0.001
        
        
        ### ENVELOPE METHOD  #####

            sum=pabs+pform+pdrink
            pabs=pabs/sum
            pform=pform/sum

        prop_abs_listmale_region=rbind(prop_abs_listmale_region, pabs) ### this is a 3xnnn matrix used for the computation of the mu values below. These values are also stored in a greater matrix for further use in prop_abs_listmale
        prop_form_listmale_region=rbind(prop_form_listmale_region, pform)
      }
##
      prop_abs_listmale=rbind(prop_abs_listmale, prop_abs_listmale_region[agegroup,])
##
      prop_form_listmale=rbind(prop_form_listmale, prop_form_listmale_region[agegroup,])

      for (j in 1:nnn)
      {
        prop_abs=prop_abs_listmale_region[,j]
        prop_form = prop_form_listmale_region[,j]
##
        mean_region = compute_mu(population,agefrac_male_region[,c("age","pop_scaled",paste0("draw_",j))],prop_abs,prop_form,pca_list[j])
        mean_male_list_region=cbind(mean_male_list_region,mean_region) ### this generates a 3xnnn matrix containing the mu values for each region, they will be placed in a bigger matrix mean_male_list
      }

      ### This is the mean without correction for binge amount, this value is temporary only
      mean_male_list_temp = rbind(mean_male_list_temp, mean_male_list_region)
      ###### REMINDER: THIS IS DONE FOR EACH REGION, SO CREATE BINGE AMOUNT, BINGE PREVALENCE AND
      ###### BINGE TIMES FOR EACH REGION AND THEN MERGE THE PARAMETERS LIKE DONE ABOVE FOR THE
      ###### OTHER VARIABLES.
      bingers_region=rnorm(nnn,info_male_regionage$BINGERS,info_male_regionage$BINGERS_SE)
      binge_times_region=rnorm(nnn,info_male_regionage$BINGE_TIMES,info_male_regionage$BINGE_TIMES_SE)
      im_region=rnorm(nnn,info_male_regionage$BINGE_A,info_male_regionage$BINGE_A_SE)

      for(r in 1:length(bingers_region))
      {
        if(bingers_region[r]<0) {bingers_region[r]=0}
        if(binge_times_region[r]<0){binge_times_region[r]=0}
        if(im_region[r]<0){im_region[r]=0}
      }

      mean_male_store_list=mean_male_list_temp
      BINGERS_MALES_list=rbind(BINGERS_MALES_list,bingers_region)
      BINGE_TIMES_MALES_list=rbind(BINGE_TIMES_MALES_list,binge_times_region)
      IM_list=rbind(IM_list,im_region)
    }
  ) ### HF: system.time end

  for (i in 1:length(regions_male))
  {
    for (y in 1:nnn)
    {
      BINGE_INTAKE_list[i,y] <- ifelse( (IM_list[i,y]*BINGE_TIMES_MALES_list[i,y]*BINGERS_MALES_list[i,y])>=mean_male_list_temp[i,y],mean_male_list_temp[i,y]-0.1,   (IM_list[i,y]*BINGE_TIMES_MALES_list[i,y]*BINGERS_MALES_list[i,y]))
    }
    mean_male_corrected_list=mean_male_list_temp-BINGE_INTAKE_list
    AVERAGENBDCONSUMPTION_list=mean_male_corrected_list/(1-BINGERS_MALES_list*BINGE_TIMES_MALES_list)
  }
  ##### Generating the values for k and theta #####
  ngroups = length (inputmage$AGE_CATEGORY)
  k_list_male=NULL
  for (i in 1:ngroups)
  {
    k_list_male_group = rnorm (nnn, ((1/1.171)^2), sqrt(4*0.013^2/1.171^6))   # HF: 1 x nnn
    k_list_male=rbind(k_list_male,k_list_male_group)                  # HF: ngroups x nnn
  }
  theta_list_male=NULL
  for (i in 1:ngroups)
  {
    theta_list_male_group = mean_male_store_list[i,]/k_list_male[i,]
    theta_list_male = rbind(theta_list_male, theta_list_male_group)
  }

  ####### Generating the Betas for the Relative Risk Functions ##########

  library("MASS")

  set.seed(1000)

  #### male population ####
  ndiseasesmale = length (relativeriskmale)
  betacoefficients_male=list(rep(0,ndiseasesmale))
  for (i in 1:ndiseasesmale)
  {
    betas = relativeriskmale[[i]][[3]]
    covariance = relativeriskmale[[i]][[4]]
    generatedbetas_disease = mvrnorm(nnn, betas, covariance)
    betacoefficients_male[[i]]=t(generatedbetas_disease)  #### we transpose only in order to have the values for each beta in a line and not a column
  }

  RRform_male_list=NULL
  for (i in 1:ndiseasesmale)
  {
    lnRRform=rnorm(nnn,relativeriskmale[[i]][[5]],sqrt(relativeriskmale[[i]][[6]]))
    RRform_male_list_disease = exp(lnRRform)
    RRform_male_list=rbind(RRform_male_list,RRform_male_list_disease)  ### this creates a vector ndiseasesmale X nnn -> each line corresponds to a disease and contains nnn occurences
  }

  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################
  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################
  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################




  #### male population ####

  #variances is the final table with all the AAFs and their confidence intervals
  # ihme - add in 2 * save.draws columns to save both the morbidity and mortality draws.
  variances.male = data.frame(matrix(NA, nrow=length(regions_male)*length(agecategories_male)*length(relativeriskmale), ncol=10 + (2 * save.draws)))
  names(variances.male)[1:10] = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAFmorb","morbMEAN","morbVARIANCE","AAFmort","mortMEAN","mortVARIANCE")
  if(save.draws > 0) {
	names(variances.male)[11:(10 + (2 * save.draws))] <- c(paste0("morb", 1:save.draws), paste0("mort", 1:save.draws))
  }

  system.time(

    for (i in 1:nmale) ### Group Loop (sex/age/region)
    {
      ##### improved code: for each iteration (of each region) we use a new table which is deleted at the end of the operation thus limiting the space used for the computation
      AAFinfolistmalelist = data.frame(matrix(NA, nrow=nnn*length(relativeriskmale), ncol=6))
      names(AAFinfolistmalelist) = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAFmorb","AAFmort")
      niterations_male=length(relativeriskmale)*nnn

      #### filling the data frame with the group specific information
      n_diseasemale = length(relativeriskmale)
      first_entry = 1
      last_entry =  n_diseasemale*nnn
      AAFinfolistmalelist$REGION[first_entry:last_entry] <- inputmage$REGION[i]
      AAFinfolistmalelist$SEX[first_entry:last_entry] <- inputmage$SEX[i]
      AAFinfolistmalelist$AGE_CATEGORY[first_entry:last_entry] <- inputmage$AGE_CATEGORY[i]
##
      AAFinfolistmalelist$age[first_entry:last_entry] <- AGE

      for (z in 1:nnn)       ## iterations loop (calculates nnn AAFs for each disease)
      {
        ######## normalising gamma function ##############
        #### un-normalised gamma function
        prevalencegamma = function(x) {dgamma(x,shape=k_list_male[i,z],scale=theta_list_male[i,z])}
        ncgamma1 = integrate(prevalencegamma, lower = 0.1, upper = 150,stop.on.error=FALSE)

        if(ncgamma1$message=="OK" & ncgamma1$value != 0)
        {
          #prevgamma=function(x){(1/(ncgamma1$value))*prevalencegamma(x)*x}
          #### Calculation of the AAFs for all disease categories ####

          for (p in 1:length(relativeriskmale))  ### Disease Loop
          {
           normConst <- integrate(dgamma, lower = 0.1, upper = 150, shape = k_list_male[i,z],scale = theta_list_male[i,z])$value

            betas <- relativeriskmale[[p]][[3]]
            non_binging <- (1 - prop_abs_listmale[i,z] - prop_form_listmale[i,z])*(1-BINGERS_MALES_list[i,z]*BINGE_TIMES_MALES_list[i,z])/normConst *
                  integrate(function(x){
                  dgamma(x, shape = k_list_male[i,z],scale = theta_list_male[i,z]) *
                  ((relativeriskmale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
                  (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)
                }, lower = 0.1, upper = 150)$value


            DRINKERSM = 1- prop_abs_listmale[i,z] - prop_form_listmale[i,z]
            #non_binging = DRINKERSM*(1-BINGERS_MALES_list[i,z]*BINGE_TIMES_MALES_list[i,z])*((RRM*(relativeriskmale[[p]][[2]]( AVERAGENBDCONSUMPTION_list[i,z],betacoefficients_male[[p]][1,z],betacoefficients_male[[p]][2,z],betacoefficients_male[[p]][3,z],betacoefficients_male[[p]][4,z]))-1)*(TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(AVERAGENBDCONSUMPTION_list[i,z])) +1 )
            binging=DRINKERSM*(BINGE_TIMES_MALES_list[i,z]*BINGERS_MALES_list[i,z])*((RRM*(relativeriskmale[[p]][[2]](IM_list[i,z],betacoefficients_male[[p]][1,z],betacoefficients_male[[p]][2,z],betacoefficients_male[[p]][3,z],betacoefficients_male[[p]][4,z]))-1)*TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(IM_list[i,z])+1)
            AAFmaleden=(prop_abs_listmale[i,z] + prop_form_listmale[i,z]+binging+non_binging)
            AAFgammamale=(AAFmaleden-1)/(AAFmaleden)

            ##### filling the dataframe with the disease specific information
            AAFinfolistmalelist$DISEASE[((z-1)*n_diseasemale+p)] <- relativeriskmale[[p]][[1]]
            AAFinfolistmalelist$AAFmorb[((z-1)*n_diseasemale+p)] <- AAFgammamale
            #### Applying the multiplication factors to the right diseases ####
            #### we'll also apply the 90% cap on mortality here            ####

            if (AAFinfolistmalelist$DISEASE[((z-1)*n_diseasemale+p)]=="Motor Vehicle Accidents - Morbidity - MEN")
            {
              # AAFinfolistmalelist$AAFmort[((z-1)*n_diseasemale+p)] <- ifelse (3/2*AAFgammamale<=0.9,3/2*AAFgammamale, 0.9)
              AAFinfolistmalelist$AAFmort[((z-1)*n_diseasemale+p)] <- ifelse (AAFgammamale<=0.9,AAFgammamale, 0.9)
            } else if (AAFinfolistmalelist$DISEASE[((z-1)*n_diseasemale+p)]=="NON-Motor Vehicle Accidents - Morbidity - MEN")
            {
             #  AAFinfolistmalelist$AAFmort[((z-1)*n_diseasemale+p)] <- ifelse (9/4*AAFgammamale<=0.9,9/4*AAFgammamale, 0.9)
              AAFinfolistmalelist$AAFmort[((z-1)*n_diseasemale+p)] <- ifelse (AAFgammamale<=0.9,AAFgammamale, 0.9)
            }
            niterations_male=niterations_male-1
            print(c("#of iterations left for male population: ",niterations_male,"for region", i, "from set #",t))
          }### loop p, representing the diseases
        }
        else
        {
          ### in case the first integral didn't work (prevalence assumed to be zero everywhere) we need to fill the corresponding AAF line with zeros
          for (p in 1:length(relativeriskmale))  ### Disease Loop
          {
            AAFgammamale=0

            AAFinfolistmalelist$DISEASE[((z-1)*n_diseasemale+p)] <- relativeriskmale[[p]][[1]]
            AAFinfolistmalelist$AAFmorb[((z-1)*n_diseasemale+p)] <- AAFgammamale
            AAFinfolistmalelist$AAFmort[((z-1)*n_diseasemale+p)] <- AAFgammamale

            niterations_male=niterations_male-1
            print(c("#of iterations left for male population: ",niterations_male,"for region",i,"from set #",t))

          }### loop p in the case where the first integral didn't work

        }## end of is/else statement for the first integral

      } ###loop z, representing the different simulations of each group

      #### Now we evaluate the CI for the age/sex/region under test and store the value in the final table

      AAFlist_region=AAFinfolistmalelist[AAFinfolistmalelist$REGION==toString(regions_male[i]),]

      for (j in 1:length(agecategories_male))
      {
        AAFlist_regionage=AAFlist_region[AAFlist_region$AGE_CATEGORY==agecategories_male[j],]

        for (k in 1:length(relativeriskmale))
        {
          AAFlist_regionagedisease=AAFlist_regionage[AAFlist_regionage$DISEASE==toString(relativeriskmale[[k]][1]),]
          meanregagedisease=mean(as.numeric(AAFlist_regionagedisease$AAFmorb))
          varregagedisease=var(as.numeric(AAFlist_regionagedisease$AAFmorb))

          ### finding the AAF corresponding to this CI in the previously obtained matrix
          AAFreg=AAFinfolistmale[AAFinfolistmale[,1]==toString(regions_male[i]),]
          AAFregage=AAFreg[AAFreg[,3]==as.numeric(agecategories_male[j]),]
          AAFregagedis=AAFregage[AAFregage[,4]==toString(relativeriskmale[[k]][1]),]
          AAFmorb=AAFregagedis$AAFmorb
          AAFmort=AAFregagedis$AAFmort

          #### creating the entry for the final list
          entry <- ((i-1)*length(agecategories_male)*length(relativeriskmale) + (j-1)*length(relativeriskmale) + k)
          variances.male$REGION[entry] <-  regions_male[i]
          variances.male$SEX[entry] <-  AAFlist_regionagedisease$SEX[1]
          variances.male$AGE_CATEGORY[entry] <-  agecategories_male[j]
          variances.male$DISEASE[entry] <-  toString(relativeriskmale[[k]][1])
          variances.male$AAFmorb[entry] <-  AAFmorb
          variances.male$morbMEAN[entry] <- meanregagedisease
          variances.male$morbVARIANCE[entry] <- varregagedisease
          variances.male$AAFmort[entry] <-AAFmort
          # variances.male$mortMEAN[entry] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN", 3/2, 9/4) * meanregagedisease
          variances.male$mortMEAN[entry] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN", 1, 1) * meanregagedisease
		      variances.male$mortMEAN[entry] <- ifelse(variances.male$mortMEAN[entry] > .9, .9, variances.male$mortMEAN[entry])
          # variances.male$mortVARIANCE[entry] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN",(3/2)^2*varregagedisease,(9/4)^2*varregagedisease)
		      variances.male$mortVARIANCE[entry] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN",(1)^2*varregagedisease,(1)^2*varregagedisease)
		  
##
          variances.male$age[entry] <- AGE
		  ## IHME - save draws.
		  if (save.draws > 0) {
			  variances.male[entry, paste0("morb", 1:save.draws)] <- as.numeric(AAFlist_regionagedisease$AAFmorb)[1:save.draws]
			  # variances.male[entry, paste0("mort", 1:save.draws)] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN", 3/2, 9/4) * variances.male[entry, paste0("morb", 1:save.draws)]
			  variances.male[entry, paste0("mort", 1:save.draws)] <- ifelse(toString(relativeriskmale[[k]][1])=="Motor Vehicle Accidents - Morbidity - MEN", 1, 1) * variances.male[entry, paste0("morb", 1:save.draws)]
        variances.male[entry, paste0("mort", 1:save.draws)] <- ifelse(variances.male[entry, paste0("mort", 1:save.draws)] > .9, .9, variances.male[entry, paste0("mort", 1:save.draws)])
          }
        }
      }
    }###loop i, representing the different groups
  ) ### HF: system.time end
  ### Moved save file to end, to process it to be more similar to the other causes.
}






################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################
################°°°°°°°°°°°°°°°°°°° COMPUTING THE CONFIDENCE INTERVALS °°°°°°°°°°°°°°°°°°°#################




set.seed(SEED_FEMALE)

  ####°°°° FEMALE SIMULATIONS °°°°####
  ####°°°° FEMALE SIMULATIONS °°°°####
  ####°°°° FEMALE SIMULATIONS °°°°####

{

  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####
  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####
  ####°°°° GENERATING PARAMETERS FOR MALE POPULATION °°°°####

  #### generating proportions of abstainers, former drinkers and drinkers. This is a binomial distribution considering a survey with 1'000 data points per sex-age group.
  #### the output matrix is ordered in the following way: each line represents the 10'000 generated parameters for one group.
  #### in order to compute the mean values we need the prop_abstainers for each region. To avoid 2 calculations these are combined together

  prop_abs_listfemale = NULL
  prop_form_listfemale = NULL
  prop_drk_listfemale = NULL
  mean_female_store_list=NULL
  mean_female_list_temp=NULL
  mean_female_list=NULL
  mean_female_corrected_list=NULL
  mean_female_list_region=NULL
  BINGERS_FEMALES_list=NULL
  BINGE_TIMES_FEMALES_list=NULL
  IM_list=NULL


  BINGE_INTAKE_list=data.frame(matrix(NA, nrow=length(regions_female), ncol=nnn))


  ###### THIS PART USES ALL 3 AGE CATEGORIES TO SIMULATE THE MEAN VALUES
  ###### ALL OTHER VALUES ARE ONLY GENERATED FOR A GIVEN REGION DEFINED IN "inputmage"


  system.time(
    for (i in 1:length(regions_female))
    {
      #### extracting the required information for each region ####
      info_female_regionage = inputfage[inputfage$REGION==regions_female[i],]
      info_female_region = inputf[inputf$REGION==regions_female[i],]

##    ## adding the age split dataset
      agefrac_female_region <- agefracf[agefracf$location_id == regions_female[i],]

      #### calculating the mean values for each group
      population = info_female_region$POPULATION
      coeffs=info_female_region$RELATIVE_COEFFICIENT
      pcalitresperyear=info_female_region$PCA[1]
      var_pca=info_female_region$VAR_PCA[1]

      #### generating random values for pca
      pca_listlitresperyear=rnorm(nnn, pcalitresperyear, sqrt(var_pca))

      #### the following is to avoid having negative numbers as PCAs due to the random distribution.

      for (h in 1:length(pca_listlitresperyear))
      {
        if (pca_listlitresperyear[h]<=0.001)
        {
          pca_listlitresperyear[h]=0.001
        }

      }
      pca_list=0.8*pca_listlitresperyear*1000*0.789/365


      mean_female_list_region=prop_abs_listfemale_region=prop_form_listfemale_region=NULL ### obviously, this has to be reinitialised at each region iteration

      for (k in 1:length(info_female_region$AGE_CATEGORY)) #### this should usually be from 1 to 3
      {
        pabs=rnorm(nnn,info_female_region$LIFETIME_ABSTAINERS[k],sqrt(info_female_region$LIFETIME_ABSTAINERS[k]*(1-info_female_region$LIFETIME_ABSTAINERS[k])/1000))
        pform=rnorm(nnn,info_female_region$FORMER_DRINKERS[k], sqrt(info_female_region$FORMER_DRINKERS[k]*(1-info_female_region$FORMER_DRINKERS[k])/1000))
        pdrink=rnorm(nnn,info_female_region$DRINKERS[k], sqrt(info_female_region$DRINKERS[k]*(1-info_female_region$DRINKERS[k])/1000))

      	 pdrink[pdrink < 0.001] <- 0.001
         pform[pform < 0.001] <- 0.001

        #### It may happen that the generated proportions of abstainers and former drinkers will be larger than 1. In this case, we will set the propoprtion ####
        #### of drinkers to 0 and scale the other 2 down. 																     ####



            sum=pabs+pform+pdrink
            pabs=pabs/sum
            pform=pform/sum


        prop_abs_listfemale_region=rbind(prop_abs_listfemale_region, pabs) ### this is a 3xnnn matrix used for the computation of the mu values below. These values are also stored in a greater matrix for further use in prop_abs_listmale
        prop_form_listfemale_region=rbind(prop_form_listfemale_region, pform)
      }
##
      prop_abs_listfemale=rbind(prop_abs_listfemale, prop_abs_listfemale_region[agegroup,])
##
      prop_form_listfemale=rbind(prop_form_listfemale, prop_form_listfemale_region[agegroup,])


      for (j in 1:nnn)
      {
        prop_abs=prop_abs_listfemale_region[,j]
        prop_form = prop_form_listfemale_region[,j]
##
        mean_region = compute_mu(population,agefrac_female_region[,c("age","pop_scaled",paste0("draw_",j))],prop_abs,prop_form,pca_list[j])
        mean_female_list_region=cbind(mean_female_list_region,mean_region) ### this generates a 3xnnn matrix containing the mu values for each region, they will be placed in a bigger matrix mean_male_list
      }

      ### This is the mean without correction for binge amount, this value is temporary only

      mean_female_list_temp = rbind(mean_female_list_temp, mean_female_list_region)
      ###### REMINDER: THIS IS DONE FOR EACH REGION, SO CREATE BINGE AMOUNT, BINGE PREVALENCE AND
      ###### BINGE TIMES FOR EACH REGION AND THEN MERGE THE PARAMETERS LIKE DONE ABOVE FOR THE
      ###### OTHER VARIABLES.
      bingers_region=rnorm(nnn,info_female_regionage$BINGERS,info_female_regionage$BINGERS_SE)
      binge_times_region=rnorm(nnn,info_female_regionage$BINGE_TIMES,info_female_regionage$BINGE_TIMES_SE)
      im_region=rnorm(nnn,info_female_regionage$BINGE_A,info_female_regionage$BINGE_A_SE)

      for(r in 1:length(bingers_region))
      {
        if(bingers_region[r]<0) {bingers_region[r]=0}
        if(binge_times_region[r]<0){binge_times_region[r]=0}
        if(im_region[r]<0){im_region[r]=0}

      }

      mean_female_store_list=mean_female_list_temp
      BINGERS_FEMALES_list=rbind(BINGERS_FEMALES_list,bingers_region)
      BINGE_TIMES_FEMALES_list=rbind(BINGE_TIMES_FEMALES_list,binge_times_region)
      IM_list=rbind(IM_list,im_region)

    }

  ) ### HF: system.time end


  for (i in 1:length(regions_female))
  {
    for (y in 1:nnn)
    {
      BINGE_INTAKE_list[i,y] <- ifelse( (IM_list[i,y]*BINGE_TIMES_FEMALES_list[i,y]*BINGERS_FEMALES_list[i,y])>=mean_female_list_temp[i,y],mean_female_list_temp[i,y]-0.1,   (IM_list[i,y]*BINGE_TIMES_FEMALES_list[i,y]*BINGERS_FEMALES_list[i,y]))
    }
    mean_female_corrected_list=mean_female_list_temp-BINGE_INTAKE_list

    AVERAGENBDCONSUMPTION_list=mean_female_corrected_list/(1-BINGERS_FEMALES_list*BINGE_TIMES_FEMALES_list)

  }         ## wary here...negative binge intake may be possible


  ##### Generating the values for k and theta #####
  ngroups = length (inputfage$AGE_CATEGORY)
  k_list_female=NULL
  for (i in 1:ngroups)
  {
    k_list_female_group = rnorm (nnn, ((1/1.258)^2), sqrt(4*0.018^2/1.258^6))   # HF: 1 x nnn
    k_list_female=rbind(k_list_female,k_list_female_group)                  # HF: ngroups x nnn
  }

  theta_list_female=NULL

  for (i in 1:ngroups)
  {
    theta_list_female_group = mean_female_store_list[i,]/k_list_female[i,]
    theta_list_female = rbind(theta_list_female, theta_list_female_group)
  }



  ####### Generating the Betas for the Relative Risk Functions ##########

  library("MASS")

  set.seed(1000)

  #### male population ####
  ndiseasesfemale = length (relativeriskfemale)
  betacoefficients_female=list(rep(0,ndiseasesfemale))
  for (i in 1:ndiseasesfemale)

  {
    betas = relativeriskfemale[[i]][[3]]
    covariance = relativeriskfemale[[i]][[4]]
    generatedbetas_disease = mvrnorm(nnn, betas, covariance)
    betacoefficients_female[[i]]=t(generatedbetas_disease)  #### we transpose only in order to have the values for each beta in a line and not a column
  }

  RRform_female_list=NULL
  for (i in 1:ndiseasesfemale)

  {
    lnRRform=rnorm(nnn,relativeriskfemale[[i]][[5]],sqrt(relativeriskfemale[[i]][[6]]))
    RRform_female_list_disease = exp(lnRRform)
    RRform_female_list=rbind(RRform_female_list,RRform_female_list_disease)  ### this creates a vector ndiseasesmale X nnn -> each line corresponds to a disease and contains nnn occurences

  }



  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################
  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################
  ##################°°°°°°°°°°°°°°°°° DEFINING THE AAF FUNCTION THAT WILL ITERATE THROUGH ALL THE POINTS °°°°°°°°°°°°°°°°°°°°°°°########################



  #### male population ####

  #variances is the final table with all the AAFs and their confidence intervals
  variances.female = data.frame(matrix(NA, nrow=length(regions_female)*length(agecategories_female)*length(relativeriskfemale), ncol=10 + 2 * save.draws))
  names(variances.female)[1:10] = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAFmorb","morbMEAN","morbVARIANCE","AAFmort","mortMEAN","mortVARIANCE")

  if(save.draws > 0) {
	names(variances.female)[11:(10 + (2 * save.draws))] <- c(paste0("morb", 1:save.draws), paste0("mort", 1:save.draws))
  }


  system.time(

    for (i in 1:nfemale) ### Group Loop (sex/age/region)
    {

      AAFinfolistfemalelist = data.frame(matrix(NA, nrow=nnn*length(relativeriskfemale), ncol=5))
      names(AAFinfolistfemalelist) = c("REGION","SEX","AGE_CATEGORY","DISEASE","AAF")
      niterations_female=length(relativeriskfemale)*nnn

      #### filling the data frame with the group specific information
      n_diseasefemale = length(relativeriskfemale)
      first_entry = 1
      last_entry =  n_diseasefemale*nnn
      AAFinfolistfemalelist$REGION[first_entry:last_entry] <- inputfage$REGION[i]
      AAFinfolistfemalelist$SEX[first_entry:last_entry] <- inputfage$SEX[i]
      AAFinfolistfemalelist$AGE_CATEGORY[first_entry:last_entry] <- inputfage$AGE_CATEGORY[i]
##
      AAFinfolistfemalelist$age[first_entry:last_entry] <- AGE
   
      for (z in 1:nnn)       ## iterations loop (calculates nnn AAFs for each disease)
      {
        ######## normalising gamma function ##############
        #### un-normalised gamma function
        prevalencegamma = function(x) {dgamma(x,shape=k_list_female[i,z],scale=theta_list_female[i,z])}
        ncgamma1 = integrate(prevalencegamma, lower = 0.1, upper = 150,stop.on.error=FALSE)
       
        
        if(ncgamma1$message=="OK" & ncgamma1$value != 0)
        {
          #### Calculation of the AAFs for all disease categories ####

          for (p in 1:length(relativeriskfemale))  ### Disease Loop
          {
            normConst <- integrate(dgamma, lower = 0.1, upper = 150, shape = k_list_female[i,z],scale = theta_list_female[i,z])$value

            betas <- relativeriskfemale[[p]][[3]]
            non_binging <- (1 - prop_abs_listfemale[i,z] - prop_form_listfemale[i,z])*(1-BINGERS_FEMALES_list[i,z]*BINGE_TIMES_FEMALES_list[i,z])/normConst *
                  integrate(function(x){
                  dgamma(x, shape = k_list_female[i,z],scale = theta_list_female[i,z]) *
                  ((relativeriskfemale[[p]][[2]](x, beta1=betas[1],beta2=betas[2],beta3=betas[3],beta4=betas[4])-1) *
                  (TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(x)) + 1)
                }, lower = 0.1, upper = 150)$value


            DRINKERSF = 1- prop_abs_listfemale[i,z] - prop_form_listfemale[i,z]

            #non_binging = DRINKERSF*(1-BINGERS_FEMALES_list[i,z]*BINGE_TIMES_FEMALES_list[i,z])*
            #((RRM*(relativeriskfemale[[p]][[2]]( AVERAGENBDCONSUMPTION_list[i,z],betacoefficients_female[[p]][1,z],
            #betacoefficients_female[[p]][2,z],betacoefficients_female[[p]][3,z],betacoefficients_female[[p]][4,z]))-1)*
            #(TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(AVERAGENBDCONSUMPTION_list[i,z])) +1 )

            binging=DRINKERSF*(BINGE_TIMES_FEMALES_list[i,z]*BINGERS_FEMALES_list[i,z])*
            ((RRM*(relativeriskfemale[[p]][[2]](IM_list[i,z],betacoefficients_female[[p]][1,z],betacoefficients_female[[p]][2,z],
            betacoefficients_female[[p]][3,z],betacoefficients_female[[p]][4,z]))-1)*TIME_AT_RISK_OCC_FUNC_NON_BINGE_AVG(IM_list[i,z])+1)

            AAFfemaleden=(prop_abs_listfemale[i,z] + prop_form_listfemale[i,z]+binging+non_binging)
            AAFgammafemale=(AAFfemaleden-1)/(AAFfemaleden)

            ##### filling the dataframe with the disease specific information
            AAFinfolistfemalelist$DISEASE[((z-1)*n_diseasefemale+p)] <- relativeriskfemale[[p]][[1]]
            AAFinfolistfemalelist$AAF[((z-1)*n_diseasefemale+p)] <- AAFgammafemale
            niterations_female=niterations_female-1
            print(paste0("#of iterations left for female population: ",niterations_female,"for region", i, "from set #"))

          }### loop p, representing the diseases
        }
        else
        {
          ### in case the first integral didn't work (prevalence assumed to be zero everywhere) we need to fill the corresponding AAF line with zeros
          for (p in 1:length(relativeriskfemale))  ### Disease Loop
          {

            AAFgammafemale=0

            AAFinfolistfemalelist$DISEASE[((z-1)*n_diseasefemale+p)] <- relativeriskfemale[[p]][[1]]
            AAFinfolistfemalelist$AAF[((z-1)*n_diseasefemale+p)] <- AAFgammafemale

            niterations_female=niterations_female-1
            print(c("#of iterations left for female population: ",niterations_female,"for region",i,"from set #",t))

          }### loop p in the case where the first integral didn't work

        }## end of is/else statement for the first integral

      } ###loop z, representing the different simulations of each group

      #### Now we evaluate the CI for the age/sex/region under test and store the value in the final table
      AAFlist_region=AAFinfolistfemalelist[AAFinfolistfemalelist$REGION==toString(regions_female[i]),]

      for (j in 1:length(agecategories_female))
      {
        AAFlist_regionage=AAFlist_region[AAFlist_region$AGE_CATEGORY==agecategories_female[j],]

        for (k in 1:length(relativeriskfemale))
        {
          AAFlist_regionagedisease=AAFlist_regionage[AAFlist_regionage$DISEASE==toString(relativeriskfemale[[k]][1]),]
          meanregagedisease=mean(as.numeric(AAFlist_regionagedisease$AAF))
          varregagedisease=var(as.numeric(AAFlist_regionagedisease$AAF))
          ### finding the AAF corresponding to this CI in the previously obtained matrix
          AAFreg=AAFinfolistfemale[AAFinfolistfemale[,1]==toString(regions_female[i]),]
          AAFregage=AAFreg[AAFreg[,3]==as.numeric(agecategories_female[j]),]
          AAFregagedis=AAFregage[AAFregage[,4]==toString(relativeriskfemale[[k]][1]),]
          AAFmorb=AAFregagedis$AAFmorb
          AAFmort=AAFregagedis$AAFmort
          #### creating the entry for the final list
          entry <- ((i-1)*length(agecategories_female)*length(relativeriskfemale) + (j-1)*length(relativeriskfemale) + k)
          variances.female$REGION[entry] <-  regions_female[i]
          variances.female$SEX[entry] <-  AAFlist_regionagedisease$SEX[1]
          variances.female$AGE_CATEGORY[entry] <-  agecategories_female[j]
          variances.female$DISEASE[entry] <-  toString(relativeriskfemale[[k]][1])
          variances.female$AAFmorb[entry] <-  AAFmorb
          variances.female$morbMEAN[entry] <- meanregagedisease
          variances.female$morbVARIANCE[entry] <- varregagedisease
          variances.female$AAFmort[entry] <- AAFmort
#           variances.female$mortMEAN[entry]<-(9/4)*meanregagedisease
#           variances.female$mortVARIANCE[entry]<-(9/4)^2*varregagedisease
          variances.female$mortMEAN[entry]<-meanregagedisease
          variances.female$mortVARIANCE[entry]<-varregagedisease
##
          variances.female$age[entry] <- AGE

		  ## IHME - save draws.
		  if (save.draws > 0) {
			  variances.female[entry, paste0("morb", 1:save.draws)] <- as.numeric(AAFlist_regionagedisease$AAF)[1:save.draws]
			  # variances.female[entry, paste0("mort", 1:save.draws)] <- 9/4 * variances.female[entry, paste0("morb", 1:save.draws)]
			  variances.female[entry, paste0("mort", 1:save.draws)] <- variances.female[entry, paste0("morb", 1:save.draws)]
          }

        }
      }


    }###loop i, representing the different groups
  ) ### HF: system.time end

}


## Save mortality and morbidity long, so that the files match the other causes.
	#MALES
	temp.morb <- variances.male[, c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAFmorb", "morbMEAN", "morbVARIANCE", "age")]
	temp.morb$SD <- sqrt(temp.morb$morbVARIANCE)
	temp.morb$morbVARIANCE <- NULL
	names(temp.morb) <- c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAF_PE", "AAF_MEAN", "age","SD")
	if (save.draws > 0) {
		temp.morb <- cbind(temp.morb, variances.male[, paste0("morb", 1:save.draws)])
		names(temp.morb) <- gsub("^morb", "draw", names(temp.morb))
	}

	temp.mort <- variances.male[, c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAFmort", "mortMEAN", "mortVARIANCE", "age")]
	temp.mort$SD <- sqrt(temp.mort$mortVARIANCE)
	temp.mort$mortVARIANCE <- NULL
	temp.mort$DISEASE <- gsub("Morbidity", "Mortality", temp.mort$DISEASE)
	names(temp.mort) <- c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAF_PE", "AAF_MEAN", "age","SD")
	if (save.draws > 0) {
		temp.mort <- cbind(temp.mort, variances.male[, paste0("mort", 1:save.draws)])
		names(temp.mort) <- gsub("^mort", "draw", names(temp.mort))
	}
	variances.male <- rbind(temp.morb, temp.mort)

	temp.morb <- variances.female[, c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAFmorb", "morbMEAN", "morbVARIANCE", "age")]
	temp.morb$SD <- sqrt(temp.morb$morbVARIANCE)
	temp.morb$morbVARIANCE <- NULL
	names(temp.morb) <- c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAF_PE", "AAF_MEAN", "age","SD")
	if (save.draws > 0) {
		temp.morb <- cbind(temp.morb, variances.female[, paste0("morb", 1:save.draws)])
		names(temp.morb) <- gsub("^morb", "draw", names(temp.morb))
	}
	# FEMALES
	temp.mort <- variances.female[, c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAFmort", "mortMEAN", "mortVARIANCE", "age")]
	temp.mort$SD <- sqrt(temp.mort$mortVARIANCE)
	temp.mort$mortVARIANCE <- NULL
	temp.mort$DISEASE <- gsub("Morbidity", "Mortality", temp.mort$DISEASE)
	names(temp.mort) <- c("REGION", "SEX", "AGE_CATEGORY", "DISEASE", "AAF_PE", "AAF_MEAN", "age","SD")
	if (save.draws > 0) {
		temp.mort <- cbind(temp.mort, variances.female[, paste0("mort", 1:save.draws)])
		names(temp.mort) <- gsub("^mort", "draw", names(temp.mort))
	}
	variances.female <- rbind(temp.morb, temp.mort)
	
## add checks for sensibility
if (any(variances.male$age != AGE)) stop("age group issue")
if (any(variances.female$age != AGE)) stop("age group issue")
	
## make sure no missing draws or negative draws
drs <- names(variances.male)[grepl("draw",names(variances.male))]
for (nm in drs) {
  if (any(is.na(variances.male[,paste0(nm)]))) stop(paste0("missing value in ",nm," males"))
  if (any(is.na(variances.female[,paste0(nm)]))) stop(paste0("missing value in ",nm," females"))
  
  if (any(variances.male[,paste0(nm)] < 0)) stop(paste0("negative value in ",nm," males"))
  if (any(variances.female[,paste0(nm)] < 0)) stop(paste0("negative value in ",nm," females"))
  
  
  if (any(variances.male[,paste0(nm)] > 1)) stop(paste0("value over 1 in ",nm," males"))
  if (any(variances.female[,paste0(nm)] > 1)) stop(paste0("value over 1 in ",nm," females"))
}
	

## Ready to save
write.csv(variances.male, file=paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s1_inj_self.csv"),row.names=F)
write.csv(variances.female, file=paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s2_inj_self.csv"),row.names=F)
