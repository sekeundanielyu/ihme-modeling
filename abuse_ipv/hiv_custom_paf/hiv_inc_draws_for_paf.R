###############################################################################
# Date: 23 May 2016
# Description: Prepare incidence draws for HIV PAF code
###############################################################################

### Setup
rm(list=ls())
gc()
root <- ifelse(Sys.info()[1]=="Windows", "J:/", "/home/j/")
library(data.table)
library(parallel)

### Arguments
# Check to make sure that this is the most up to date run!!!
spectrum.name <- "160515_echo1"
# Set number of cores used in qlogin
ncores <- 80

### Paths
spectrum.dir <- paste0("/share/gbd/WORK/02_mortality/03_models/hiv/spectrum_draws/", spectrum.name, "/compiled/")
# Change this to wherever you want the file to write to, probably not to J:/ cuz its big
output.dir <- "/share/epi/risk/temp/ipv_hiv_pafs/hiv_inc_draws/"
dir.create(output.dir, showWarnings=F)

### Tables
loc.table <- fread(paste0(root, "temp/maps/location_map.csv"))
age.table <- fread(paste0(root, "temp/maps/age_map.csv"))
sex.table <- fread(paste0(root, "temp/maps/sex_map.csv"))

### Functions
id.loc <- function(data) {
# Determine location variable and convert to location_id
	if (sum(names(data) %in% names(loc.table), na.rm=T) > 0) {
		loc.var <- names(data)[names(data) %in% names(loc.table)]
		if (loc.var != "location_id") {
			loc.table <- loc.table[,c(loc.var, "location_id"), with=F]
			data <- merge(data, loc.table, by=loc.var, all.x=T)
			data[,c(loc.var):=NULL]
		} 
	} else {
		stop("Missing location variable")
	}	
	return(data)
}

id.age <- function(data) {
# Determine age variable and convert to age_group_id
	if (sum(names(data) %in% names(age.table), na.rm=T) > 0) {
		age.var <- names(data)[names(data) %in% names(age.table)]
		if (age.var != "age_group_id") {
			age.table <- age.table[,c(age.var, "age_group_id"), with=F]
			data[,c(age.var):=as.character(get(age.var))]
			data <- merge(data, age.table, by=age.var, all.x=T)
			data[,c(age.var):=NULL]
		} 
	} else {
		stop("Missing age variable")
	}
	return(data)
}
 
id.sex <- function(data) {
# Determine sex variable and convert to sex_id
	if (sum(names(data) %in% c("sex", "sex_id")) > 0) {
	sex.var <- names(data)[names(data) %in% c("sex", "sex_id", "gender")]
		if (sex.var != "sex_id") {
				sex.table <- data.table(sex=c("male", "female", "both"), sex_id=c(1, 2, 3))
				data <- merge(data, sex.table, by=sex.var, all.x=T)
				data[,c(sex.var):=NULL]
		} 
	} else {
		stop("Missing sex variable")
	}
	return(data)
}

id.data  <- function(data) {
# Call all ID functions at once
	data <- id.loc(data)
	data <- id.age(data)
	data <- id.sex(data)
	return(data)
}

### Code
## Get a list of lowest level locations and special South Africa names
loc.lowest <- unique(loc.table[most_detailed==1, .(ihme_loc_id)])
loc.notzaf <- loc.lowest[!(grep("ZAF_", ihme_loc_id))]
loc.zaf <- loc.table[grep("ZAF_", spectrum_loc), .(spectrum_loc)]
setnames(loc.zaf, "spectrum_loc", "ihme_loc_id")
loc.list <- unique(rbind(loc.notzaf, loc.zaf)[,ihme_loc_id])
for (loc in loc.list) {
# data.list <- mclapply(loc.list, function(loc) {
	file <- paste0(loc, "_ART_data.csv")
	# Check if there are stage 2 results 
	if(file.exists(paste0(spectrum.dir, "stage_2/", file))){
		data <- fread(paste0(spectrum.dir, "stage_2/", file))[, .(run_num, year, sex, age, new_hiv, pop_neg, pop_lt200, pop_200to350, pop_gt350, pop_art)]
	} else {
		data <- fread(paste0(spectrum.dir, "stage_1/", file))[, .(run_num, year, sex, age, new_hiv, pop_neg, pop_lt200, pop_200to350, pop_gt350, pop_art)]
	}
	if(grepl("ZAF_", loc)) {
    data[, spectrum_loc:=loc]
	} else {
	  data[, ihme_loc_id:=loc]
	}
	data.id <- id.data(data)
	setnames(data.id, "year", "year_id")
	
	#Calculate person-years for rate calculation (pop_neg, pop_lt200, pop_200to350, pop_gt350, pop_art)
	# data.id[,"summed"] <- data.id[,pop_neg] + data.id[,pop_lt200] + data.id[,pop_200to350] + data.id[,pop_gt350] + data.id[,pop_art]
	data.id[, summed := pop_neg + pop_lt200 + pop_200to350 + pop_gt350 + pop_art]
	
	# data.id[,"inc_rate"] <- data.id[,new_hiv] / data.id[,summed]
	data.id[summed!=0, inc_rate := new_hiv / summed]
	data.id[summed==0, inc_rate := 0]

	data.id[, run_num := paste0("inc", run_num)]
	cast.data <- dcast.data.table(data.id, location_id + year_id + age_group_id + sex_id ~ run_num, value.var="inc_rate")
	loc.id <- unique(cast.data[, location_id])
	output.path <- paste0(output.dir, loc.id, "_hiv_incidence_draws.csv")
	write.csv(cast.data, file=output.path, row.names=F)
}
# }, mc.cores=ncores)

### End
