############# This program will compute the Alcohol Attributable Fractions (AAF) for assault injuries
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
### pass in arguments
	arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
	yyy <- as.numeric(arg[1])                     # Year for current analysis
	data.dir <- arg[2]                            # Data directory
	out.dir <- arg[3]                             # Directory to put temporary draws in
	save.draws <- as.numeric(arg[4])              # Number of draws to save 

	## ages <- 1:3 # Input files only have ages 1-3, but output will have 0-3 because 0-14 year olds get hit by others
	ages <- seq(from=0,to=80,by=5)    ## adding these because of our new analysis
	age_group_ids <- c(2:21)
	sexes <- 1:2
	sims <- 1:save.draws





##### SELECTING THE SIMULATIONS FILE ####
##### SELECTING THE SIMULATIONS FILE ####
##### SELECTING THE SIMULATIONS FILE ####

## Get population (from input data files)
##	data.file <- paste0(data.dir, "/alc_data_", yyy, ".csv")
##	pop <- read.csv(data.file, stringsAsFactors=F)
##	pop <- pop[, c("REGION", "SEX", "AGE_CATEGORY", "POPULATION")]

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
	data <- data[grep("^NON-Motor Vehicle Accidents", data$DISEASE), c("REGION", "SEX", "age", "MORTALITY", paste0("draw", sims))]
  data[, paste0("draw", sims)][data[, paste0("draw", sims)] == 1] <- 0.9999 # This fails if we have PAFs equal to 1, so round it down so that it will work...

## Get the population weighted average RR and then convert back to the PAF.
	data <- merge(data, pop, by=c("REGION", "SEX", "age"),all.x=T)

	data[, paste0("draw", sims)] <- (1 / (1 - data[, paste0("draw", sims)])) * data$popfrac
	data <- aggregate(data[, paste0("draw", sims)], list(REGION=data$REGION, MORTALITY=data$MORTALITY), FUN="sum")
	data[, paste0("draw", sims)] <- (data[, paste0("draw", sims)] - 1) / data[, paste0("draw", sims)]
	
# Loop through the ages and sexes, and multiply the population weighted PAF by the Australian scalar
# of what a total population PAF is to age-,sex- PAF.
	AGE_CATEGORIES <- 0:3
	scalar <- data.frame(age=AGE_CATEGORIES, scalar=c(0.610859729, 1.75084178, 1.014666593, 0.456692913))
	
	out <- data.frame()
	for (aaa in AGE_CATEGORIES) {
		for (sss in sexes) {
			temp <- data[, c("REGION", "MORTALITY")]
			temp$AGE_CATEGORY <- aaa
			temp$SEX <- sss
			## this was previously PAF*scalar...but the scalar should be for RR, so do in RR space, in steps to troubleshoot
		
      ## make RR:                               RR = 1/(1-PAF)
			temp[, paste0("draw", sims)] <- 1/(1 - data[, paste0("draw", sims)])
			
      ## multiply (RR-1) by scalar, add to 1:   RR_adj = (1 + (RR_orig -1)*scalar)
			temp[, paste0("draw", sims)] <- 1 + (temp[, paste0("draw", sims)]-1)*scalar[scalar$age == aaa, "scalar"]
			
      ## convert back to PAF:                   PAF = 1 - (1/RR_adj)
			temp[, paste0("draw", sims)] <- 1 - (1/(temp[, paste0("draw", sims)]))

			out <- rbind(temp, out)
		}
	}
	
  
  age <- ages
  AGE_CATEGORY <- c(0,0,0,1,1,1,1,2,2,2,2,2,3,3,3,3,3)
  expand <- cbind(age,AGE_CATEGORY)
  out <- merge(out,expand,by="AGE_CATEGORY",all=T)
		
	# Fix names of DISEASE values.
	out$DISEASE <- paste("Assault Injuries", ifelse(out$MORTALITY, "Mortality", "Morbidity"), ifelse(out$SEX==1, "MEN", "WOMEN"), sep=" - ")
	out$MORTALITY <- NULL
	
	write.csv(out, file = paste0(out.dir, "/AAF_", yyy, "_inj_aslt", ".csv"))
