############# This program will compute the Alcohol Attributable Fractions (AAF) for the diseases listed
############# below. It requires an input file (in simple .txt format). Select the age category to be evaluated here:

### pass in arguments
rm(list=ls())
library(foreign)
library(haven)
library(data.table)

if (Sys.info()["sysname"] == "Windows") {
  root <- "J:/"
  arg <- c(1995, "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs", "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp", 1000)
} else {
  root <- "/home/j/"
  print(paste(commandArgs(),sep=" "))
  arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
}

	arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
	yyy <- as.numeric(arg[1])                     # Year for current analysis
	data.dir <- arg[2]                            # Data directory
	out.dir <- arg[3]                             # Directory to put temporary draws in
	save.draws <- as.numeric(arg[4])              # Number of draws to save 




  print(yyy)
  print(data.dir)
  print(out.dir)
  print(save.draws)


	ages <- 1:3 # Input files only have ages 1-3, but output will have 0-3 because 0-14 year olds get hit by others
	ages <- seq(from=0,to=80,by=5)    ## adding these because of our new analysis
	age_group_ids <- c(2:21)
	sexes <- 1:2
	sims <- 1:save.draws

	set.seed(32859737) # Set a seed so the reference population will always have the same values
	
##### SELECTING THE SIMULATIONS FILE ####
##### SELECTING THE SIMULATIONS FILE ####
##### SELECTING THE SIMULATIONS FILE ####
	
	## Read pop file
	pop <- as.data.frame(read_dta(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta")))
	## get age from age_group_id
	agemap <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv"))
	pop <- merge(pop,agemap,by=c("age_group_id"))
	
	pop <- pop[pop$year_id == yyy & pop$sex_id %in% c(1,2),c("location_id","year_id","age","age_group_id","sex_id","pop_scaled")]
	
	## Get percentage of region's population that is in a given age-, sex-group. This will be used to
	## Population weight the PAFs.
	totalpop <- aggregate(pop_scaled ~ location_id, data=pop, FUN=sum)
	names(totalpop)[2] <- "TOTALPOPULATION"
	pop <- merge(pop, totalpop, by="location_id")
	pop$popfrac <- pop$pop_scaled / pop$TOTALPOPULATION
	pop <- pop[, c("location_id", "sex_id", "age", "popfrac")]
  names(pop) <- c("REGION","SEX","age","popfrac")
	
## Generate draws for australian injuries to others (as reference)
	ref <- data.frame(matrix(NA, nrow=4*2, ncol=2+save.draws))
	names(ref) <- c("AGE_CATEGORY", "MORTALITY", paste0("ref.others", 1:save.draws))
	ref$AGE_CATEGORY <- c(rep(0, 2), rep(1, 2), rep(2, 2), rep(3, 2))
	ref$MORTALITY <-  rep(c(0, 1), 4)
	ref[ref$AGE_CATEGORY == 0 & ref$MORTALITY == 1, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.143, sd=0.011070276)
	ref[ref$AGE_CATEGORY == 1 & ref$MORTALITY == 1, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.33705435, sd=0.014948201)
	ref[ref$AGE_CATEGORY == 2 & ref$MORTALITY == 1, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.252659574, sd=0.013741278)
	ref[ref$AGE_CATEGORY == 3 & ref$MORTALITY == 1, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.065372829, sd=0.007816599)
	ref[ref$AGE_CATEGORY == 0 & ref$MORTALITY == 0, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.099, sd=0.009444522)
	ref[ref$AGE_CATEGORY == 1 & ref$MORTALITY == 0, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.14452352, sd=0.011119194)
	ref[ref$AGE_CATEGORY == 2 & ref$MORTALITY == 0, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.086186541, sd=0.008874594)
	ref[ref$AGE_CATEGORY == 3 & ref$MORTALITY == 0, grep("ref.others", names(ref))] <- rnorm(save.draws,mean=0.017489712, sd=0.004145337)	
	
## Generate draws of australian total injuries to self  (as reference 
	ref.total.self <- data.frame(matrix(NA, nrow=2, ncol=1+save.draws))
	names(ref.total.self) <- c("MORTALITY", paste0("ref.total.self", 1:save.draws))
	ref.total.self$MORTALITY <- 0:1
	ref.total.self[ref.total.self$MORTALITY == 1, grep("ref.total.self", names(ref.total.self))] <- rnorm(save.draws,mean=0.205965241, sd=0.012788415)
	ref.total.self[ref.total.self$MORTALITY == 0, grep("ref.total.self", names(ref.total.self))] <- rnorm(save.draws,mean=0.162548654, sd=0.01166733)
	
	## Bring in injuries data and format it
	data <- list()
	for (aaa in age_group_ids[7:20]) {
	  for (sss in sexes) {
	    cat(paste0(aaa," ",sss,"\n")); flush.console()
	    data[[paste0(aaa,sss)]] <- fread(paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s", sss, "_inj_self.csv"))
	  }
	}
	data <- as.data.frame(rbindlist(data))
	
	## Get a mortality variable, rather than the DISEASE one which varies by sex.
	data$MORTALITY <- grepl("Mortality", data$DISEASE)
	# Only use non-motor vehicle accidents and get rid of extraneous variables
	data <- data[grep("^Motor Vehicle Accidents", data$DISEASE), c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY","age", paste0("draw", sims))]
	names(data) <- gsub("draw", "self", names(data))
	

## Get the population weighted average RR for region specific injuries to self and then convert back to the PAF.
	total.self <- merge(data, pop, by=c("REGION", "SEX", "age"))
	total.self[, paste0("self", sims)][total.self[, paste0("self", sims)] == 1] <- 0.9999 # This fails if we have PAFs equal to 1, so round it down so that it will work...
	total.self[, paste0("self", sims)] <- (1 / (1 - total.self[, paste0("self", sims)])) * total.self$popfrac
	total.self <- aggregate(total.self[, paste0("self", sims)], list(REGION=total.self$REGION, MORTALITY=total.self$MORTALITY), FUN="sum")
	total.self[, paste0("self", sims)] <- (total.self[, paste0("self", sims)] - 1) / total.self[, paste0("self", sims)]
	names(total.self) <- gsub("self", "total.self", names(total.self))

## Add on observations for age group = 0 (with 0 injuries to self) into the dataset
	temp <- data[data$AGE_CATEGORY==1,]
	temp$AGE_CATEGORY <- 0
  temp$age[temp$age==15] <- 0
  temp$age[temp$age==20] <- 5 
  temp$age[temp$age==25] <- 10
  temp = temp[temp$age!=30,] 

	temp[, grep("^self", names(temp))] <- 0
	data <- rbind(data, temp)

#   Test datasets: use in case of debugging (primarily for age group issues)
#   write.csv(data, file = paste0(out.dir, "/AAF_", yyy, "_predata_mva", ".csv"))
#   write.csv(total.self, file = paste0(out.dir, "/AAF_", yyy, "_self_mva", ".csv"))
#   write.csv(ref, file = paste0(out.dir, "/AAF_", yyy, "_ref_mva", ".csv"))
#   write.csv(ref.total.self, file = paste0(out.dir, "/AAF_", yyy, "_totalref_mva", ".csv"))

## Create a single complete dataset to work from
	data <- merge(data, total.self, by=c("REGION", "MORTALITY"))
	data <- merge(data, ref, by=c("AGE_CATEGORY", "MORTALITY"))
	data <- merge(data, ref.total.self, by=c("MORTALITY"))

#   write.csv(data, file = paste0(out.dir, "/AAF_", yyy, "_postdata_mva", ".csv"))

## Calculate mva PAFs
	## General idea: Work in log space to constrain the fraction, and scale the compliment of the injury to self burden by a scalar relating total
	## burden in the australian population to age specific hit by others in australia. 
	## Formula: PAF = (1 - mva_inj_self_age_i_region_j) * (1 - exp(log(1 - australian_hit_by_others_age_i) * mva_inj_self_total_region_j / mva_inj_self_total_australia))
	out.mva <- data.frame(matrix(NA, nrow=dim(data)[1], ncol=5+save.draws))
	names(out.mva) <- c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY", "age", paste0("draw", 1:save.draws))
	out.mva[, c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY","age")] <- data[, c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY","age")]
	out.mva[, grep("^draw", names(out.mva))] <- (1 - data[, grep("^self", names(data))]) * (1 - exp(log(1 - data[, grep("^ref\\.others", names(data))]) * data[, grep("^total\\.self", names(data))] / data[, grep("^ref\\.total\\.self", names(data))]))
	out.mva$DISEASE <- paste("MVA Injuries to others", ifelse(out.mva$MORTALITY, "Mortality", "Morbidity"), ifelse(out.mva$SEX==1, "MEN", "WOMEN"), sep=" - ")
	out.mva$MORTALITY <- NULL
	
## Calculate pedestrian PAFs
	## Pedestrian PAFs are similar to the mva PAFs, except we don't have to worry about complimenting the burden to self because pedestrians don't hit other people
	## TODO: Check with Theo about that logic. Seems like drunk pedestrians are at increased risk of MVA because they'll stumble into street?
	## Formula: PAF = 1 - exp(log(1 - australian_hit_by_others_age_i) * mva_inj_self_total_region_j / mva_inj_self_total_australia)
	out.ped <- data.frame(matrix(NA, nrow=dim(data)[1], ncol=5+save.draws))
	names(out.ped) <- c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY", "age", paste0("draw", 1:save.draws))
	out.ped[, c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY", "age")] <- data[, c("REGION", "SEX", "AGE_CATEGORY", "MORTALITY", "age")]
	out.ped[, grep("^draw", names(out.ped))] <- 1 - exp(log(1 - data[, grep("^ref\\.others", names(data))]) * data[, grep("^total\\.self", names(data))] / data[, grep("^ref\\.total\\.self", names(data))])
	out.ped$DISEASE <- paste("Pedestrian Injuries", ifelse(out.ped$MORTALITY, "Mortality", "Morbidity"), ifelse(out.ped$SEX==1, "MEN", "WOMEN"), sep=" - ")
	out.ped$MORTALITY <- NULL
	
	out <- rbind(out.ped, out.mva)

# Take out for now: no need for expansion since calculation is at age-level
# age <- ages
# AGE_CATEGORY <- c(0,0,0,1,1,1,1,2,2,2,2,2,3,3,3,3,3)
# expand <- cbind(age,AGE_CATEGORY)
# out <- merge(out,expand,by="AGE_CATEGORY",all=T)

write.csv(out, file = paste0(out.dir, "/AAF_", yyy, "_inj_mvaoth", ".csv"))
