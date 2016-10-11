###########################################################
### Project: ubCov
### Purpose: Various model setup tasks
###########################################################

source('utility.r')

############################################
## Prep Data
############################################

hierarchy_fix <- function(df) {
	## Map all data from China (6) to China w/o HKG, MAC (44533)
	df <- df[location_id==6, location_id := 44533]
	return(df)

}

outlier <- function(df, me_name, merge_vars) {

	##	Given a dataframe, a file that contains the outliers,
	##	a list of variables to merge on creates a column 
	##	called outliers that contains the value outliered

	file <- list.files(ubcov_path("outlier_root"), me_name, full.names=T)
	if (length(file) == 1) {
		outliers <- fread(paste0(file, "/outlier_db.csv"))
		outliers[, outlier_flag := 1]
		## Batch outlier by NID
		batch_outliers <- outliers[batch_outlier==1, .(nid, outlier_flag)]
		setnames(batch_outliers, "outlier_flag", "batch_flag")
		if (nrow(batch_outliers) > 0) {
			df <- merge(df, batch_outliers, by='nid', all.x=T, allow.cartesian=TRUE)
			## Set outliers
			df <- df[batch_flag == 1, outlier := data]
			df <- df[batch_flag == 1, data := NA]
			df[, batch_flag := NULL]
		}
		## Specific merges
		specific_outliers <- outliers[batch_outlier==0, c(merge_vars, "outlier_flag"), with=F]
		setnames(specific_outliers, "outlier_flag", "specific_flag")
		if (nrow(specific_outliers) > 0) {
			df <- merge(df, specific_outliers, by=merge_vars, all.x=T)
			## Set outliers
			df <- df[specific_flag==1, outlier := data]
			df <- df[specific_flag==1, data := NA]
			df[, specific_flag:= NULL]
		}
		print("Outliers outliered")
	} else {
		print(paste0("No outliers for ", me_name))
	}

	return(df)

}

offset_data <- function(df, data_transform, offset) {

	## Offset 0's if logit or log
	if (length(df[data == 0 | data == 1, data]) > 0) {
		if (data_transform %in% c("logit", "log")) {
			df[data == 0, data := data + offset]
			## Offset 1's if logit
			if (data_transform == "logit") {
				data[data == 1, data := data - offset]
			}
		} 
	} else {
			df[, offset_data := 0]
	}
		
	
	return(df)
}

wilson_interval_method <- function(data, sample_size, variance) {
	df <- data.table(cbind(data=data, sample_size=sample_size, variance=variance))
	## Impute sample size if only some cases are missing
    df <- df[!is.na(data) & is.na(sample_size), sample_size := quantile(sample_size, 0.05, na.rm=T)]
    ## Fill in variance using p*(1-p)/n if variance is missing
    df <- df[!is.na(data) & is.na(variance), variance := (data*(1-data))/sample_size]
    ## Replace variance using Wilson Interval Score Method: p*(1-p)/n + 1.96^2/(4*(n^2)) if p*n or (1-p)*n is < 20
    df <- df[, cases_top := (1-data)*sample_size]
    df <- df[, cases_bottom := data*sample_size]
    df <- df[!is.na(data) & (cases_top<20 | cases_bottom<20), variance := ((data*(1-data))/sample_size) + ((1.96^2)/(4*(sample_size^2)))]

    return(df$variance)
}

cv_method <- function(data, sample_size, variance) {
	df <- data.table(cbind(data=data, sample_size=sample_size, variance=variance))
	## Compute standard deviation
    df <- df[!is.na(data) & !is.na(variance), standard_deviation := as.numeric(sqrt(sample_size * variance))]
    ## Take a global mean of the coefficient of variation
    df <- df[, cv_mean := mean(standard_deviation/data, na.rm=T)]
    ## Estimate missing standard_deviation using global average cv
    df <- df[!is.na(data) & is.na(standard_deviation), standard_deviation := data * cv_mean]
    ## Impute sample size using 5th percentile sample_size
    sample_size_lower <- quantile(df[sample_size > 0, sample_size], 0.05, na.rm=T)
    df <- df[!is.na(data) & (is.na(sample_size)|sample_size==0), sample_size := sample_size_lower]
    ## Estimate variance 
    df <- df[!is.na(data) & is.na(variance), variance := standard_deviation^2/sample_size]
	
	return(df$variance) 
    
}

all_else_failed <- function(df) {
	## Find max of data with variance
 	df <- df[!is.na(data), max_nat := quantile(variance, 0.95, na.rm=T), by=location_id]
  	df <- df[!is.na(data), max_reg := quantile(variance, 0.95, na.rm=T), by=region_id]
  	df <- df[!is.na(data), max_sup := quantile(variance, 0.95, na.rm=T), by=super_region_id]
  	df <- df[!is.na(data), max_glo := quantile(variance, 0.95, na.rm=T)]
  	## Replace by increasing geography
  	for (col in c('max_nat', 'max_reg', 'max_sup', 'max_glo')) {
    	if (length(df[!is.na(data) & is.na(variance), data]) > 0) {
      		df <- df[!is.na(data) & is.na(variance), variance := get(paste0(col))]
    	}
  	}

  	return(df$variance)
}

impute_variance <- function(df, measure_type) {

	## Impute if not all datapoints have variance measures
	if (nrow(df[!is.na(data)]) != nrow(df[!is.na(variance)])) {
		## If still variance and sample size both empty, throw an error
	if (nrow(df[!is.na(sample_size)]) == 0 & nrow(df[!is.na(variance)]) == 0) {
		## Redundant check, should've broken on upload if so
		stop("Data must have some way to impute variance: variance and sample_size cant be entirely missing")
	## If sample size is not missing
	} else if (nrow(df[!is.na(sample_size)]) > 0) {
		## If proportion, do Wilson Interval method
		if (measure_type == "proportion") df[,variance := wilson_interval_method(data, sample_size, variance)]
		## If continuous, do coefficient of variation
		if (measure_type == "continuous") df[,variance := cv_method(data, sample_size, variance)]
	## If sample size is missing
	} else if (nrow(df[!is.na(sample_size)]) == 0) {
		df[,variance := all_else_failed(df)]
	}
	## Flag imputed variance
		df[,imputed_variance := 1]
	} else {
		df[,imputed_variance := 0]
	}

	return(df)

}

############################################
## Prep Parameters
############################################

prep_square <- function(run_id) {

	## Make square and grab covariates
	square <- make_square(location_set_version_id,
						 year_start, year_end,
						 by_sex, by_age,
						 custom_sex_id, custom_age_group_id,
						 covariates=covariates)
	
	## Get levels
	locs <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)
	levels <- locs[,grep("level|location_id", names(locs)), with=F]
	square <- merge(square, levels, by="location_id")

	return(square)
}

###########################################################
## Main Process
###########################################################

init_param <- function(run_id, get.param=FALSE) {

	## Set parameters into global environment
	param <- get_parameters(run_id=run_id) %>% data.frame
	for(p in names(param)) assign(p, param[, p], envir=globalenv())

	## Split up covariates, custom age, custom_sex
	for (var in c("covariates", "custom_age_group_id", "custom_sex_id", "aggregate_ids")) {
		if (var %in% c("covariates")) {
			assign(paste0(var), unlist(strsplit(gsub(" ", "", get(var)), split=",")), envir=globalenv())
		}
		else {
			assign(paste0(var), as.numeric(unlist(strsplit(gsub(" ", "", get(var)), split=","))), envir=globalenv())
		}
	}

	## Set paths into global environment
	assign("run_root", paste0(ubcov_path("cluster_model_output"), "/", run_id), envir=globalenv())
	assign("model_root", ubcov_path("model_root"), envir=globalenv())

	if (get.param) return(param)
}

init_settings <- function(run_id, kos, draws, cluster_project, parallel, nparallel, logs) {
	## Set run settings
	args <- match.call() %>% as.list
    args.str <- names(args)[-1]
    lapply(args.str, function(x) assign(x, args[[x]], envir=globalenv()))

    ## Set model parameters
    init_param(run_id)

    ## Set start time
    assign("model.start", proc.time(), envir=globalenv())

    ## Set cores
    assign("cores", 10, envir=globalenv())

    print("Settings loaded")   
}


prep_folders <- function(run_root) {

	## Clear and make new directories
	system(paste0("rm -rf ", run_root))
	system(paste0("mkdir -m 777 -p ", run_root))

	## Create output, param, temp databases
	H5close()
	for (db in c("output", "param", "temp")) {
		path <- paste0(run_root, "/", db, ".h5")
		h5createFile(file=path)
		system(paste("chmod 777", path))
	}

}

prep_parameters <- function(run_id) {

	## Save parameters into output.h5
	param <- get_parameters(run_id=run_id)
	model_save(param, run_id, "parameters")

	## Save covariate versions into output.h5
	cov_version <- get_covariate_version(covariates)
	model_save(cov_version, run_id, "covariate_version")

	## Save location hierarchy temp.h5
	locs <- get_location_hierarchy(location_set_version_id, china.fix=TRUE)
	locs <- locs[, c('location_id', 'parent_id', 'region_id', 'super_region_id', 'level', grep("level_", names(locs), value=T)), with=F]
	model_save(locs, run_id, "location_hierarchy")

	## Save square file into temp.h5
	square <- prep_square(run_id)
	model_save(square, run_id, "square")

}


prep_data <- function(run_id, me_name, data_transform, data_offset, measure_type, output=FALSE) {

	## Load data
	df <- model_load(run_id, "data")

	## Subset based on specificed age, sex, year
	df <- df[year_id >= year_start & year_id <= year_end]

	## Outlier
	df <- outlier(df, me_name, c("me_name", "nid", "location_id", "year_id", "age_group_id", "sex_id"))

	## Map data to locations
	df <- hierarchy_fix(df)

	## Save originals
	df <- df[, `:=` (original_data = data, original_variance = variance)]

	## Offset
	df <- offset_data(df, data_transform, data_offset)

	## Impute variance
	df <-  impute_variance(df, measure_type)

	## Increase variance if cv_subgeo == 1
	if (!("cv_subgeo" %in% names(df))) {
		if ("cv_subnat" %in% names(df)) { 
			setnames(df, "cv_subnat", "cv_subgeo") 
		} else if ("smaller_site_unit" %in% names(df)) {
			setnames(df, "smaller_site_unit", "cv_subgeo")
		} else {
			df <- df[, cv_subgeo :=0]
		}
	}
	df <- df[is.na(cv_subgeo), cv_subgeo := 0]
	df <- df[cv_subgeo == 1, variance := variance * 10]

	## Data, Variance transformations
	df <- df[, variance := delta_transform(data, variance, data_transform)]
	df <- df[, data := transform_data(data, data_transform)]
	
	## Sort by location year age sex
	df <- df[order(location_id, year_id, age_group_id, sex_id)]
	
	## Create a unique id for datapoints
	df <- df[, data_id := 1:nrow(df)]
	
	## Save 
	model_save(df, run_id, "prepped")

	if(output) return(df)

}

get_kos <- function(run_id, model_root, run_root, kos) {

	## Run script to get a frame of knockouts with
	## codem_ko, then return that for use
	
	## Run script to get knockouts
	script <- paste0(model_root, "/ko.py")
	args <- paste(run_root, model_root, kos, sep=" ")
	system(paste("/usr/local/bin/python", script, args, sep=" "))

	print(paste0("Saved kos to ", model_path(run_id, 'kos')))

}


###########################################################
## Full setup
###########################################################


model_prep <- function() {

	## Clear folders
	prep_folders(run_root)

	## Parameter prep
	prep_parameters(run_id)

	## Data Prep
	prep_data(run_id, me_name, data_transform, data_offset, measure_type)

	## Knockout
	if (kos > 0) get_kos(run_id, model_root, run_root, kos)

}