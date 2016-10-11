###########################################################
### Project: ubCov
### Purpose: Utility functions for modeling
###########################################################

###################
### Setting up ####
###################
library(data.table)
library(stringr)
library(plyr)
library(dplyr)
library(RMySQL)
library(rhdf5, lib.loc='/share/local/R-3.1.2/lib64/R/library')


## ubcov functions
source("../../functions/ubcov_tools.r")
ubcov_functions(c("db_tools", "cluster_tools"))


####################################################################################################################################################
# 															   Table of Contents
####################################################################################################################################################

## General Model Utility
	## model_path
	## model_load
	## model_save
	## get_parameters
	## get_ids
	## get_me_name
	## get_model_list
	## get_data_list
	## get_run_list

## Math Functions
	## logit
	## inv.logit
	## transform_data
	## delta_transform


####################################################################################################################################################
# 															 General Model Utility
####################################################################################################################################################


	model_path <- function(run_id, obj) {

		## Group objects
		data <- c("data")
		param <- c("parameters", "covariate_version", "location_hierarchy", "square", "kos", "st_amp")
		temp <- c("prepped", "prior", "st", "adj_data", "gpr", "raked")
		output <- c("flat", "draws")
		objs <- c(data, param, temp, output)

		## Check
		if (!(obj %in% objs)) stop(paste0(obj, " not in ", toString(objs)))

		## Return Path
		if (obj %in% data) path <- get_parameters(run_id=run_id)$data_id %>% paste0(ubcov_path("cluster_model_data"), "/", ., ".h5")
		for (file in c("param", "temp", "output")) {
			if (obj %in% get(file)) path <-  paste0(ubcov_path("cluster_model_output"), "/", run_id, "/", file, ".h5")
		}
		return(path)
	}

#####################################################################################################################################################

	model_load <- function(run_id, obj) {
		path <- model_path(run_id, obj)
		if (obj %in% c("kos")) {
			return(h5read.py(path, obj) %>% data.table)
		} else {
			return(h5read(path, obj) %>% data.table)
		}
	}

#####################################################################################################################################################

	model_save <- function(df, run_id, obj) {
		H5close()
		path <- model_path(run_id, obj)
		h5write(df, path, obj)
		print(paste("Saved", obj, "to", path, sep=" "))
	}

#####################################################################################################################################################

	table_to_fixed <- function(input, output, obj) {
		script <- paste0(ubcov_path("model_root"), "/table_to_fixed.py")
		args <- paste(input, output, obj)
		system(paste("/usr/local/bin/python", script, args, sep=" "))
		print(paste0("TtF Complete. Saved ", obj, " to ", output))
	}

#####################################################################################################################################################

	get_parameters <- function(me_name=NULL, data_id=NULL, model_id=NULL, run_id=NULL, return=NULL) {

		## Returns list of parameters with the specificity requested. If run_id given, checks that there is only 1 row

		## Drop columns
		cols <- c("author", "uploader", "date", "notes", "best")
		drop_cols <- function(df, cols) {
			list <- paste(cols, collapse="|")
			return(df[, -grep(list, names(df), value=T), with=F])
		}

		## Combine the me, data, model, and run databases
		param_db <- ubcov_path("me_db") %>% fread(., na.strings="NA")
		param_db <- merge(param_db, ubcov_path("data_db") %>% fread(., na.strings=c("NA", "")) %>% drop_cols(., cols), by="me_name")
		param_db <- merge(param_db, ubcov_path("model_db") %>% fread(., na.strings=c("NA", "")) %>% drop_cols(., cols), by="me_name", allow.cartesian=TRUE)
		param_db <- merge(param_db, ubcov_path("run_db") %>% fread(., na.strings=c("NA", "")) %>% drop_cols(., cols), by=c("me_name","model_id", "data_id"))

		## Subset based on parameters
		ifstatement <- "1==1"
		for (id in c("me_name", "data_id", "model_id", "run_id")) {
			if (!is.null(get(id))) ifstatement <- paste(ifstatement, "&", id, "%in% c(", toString(get(id)), ")")
		}
		parameters <- param_db[eval(parse(text=ifstatement))]

		## If run_id given, check that only 1 row per run_id)
		if (!is.null(run_id)) if (length(run_id) != nrow(parameters)) stop("duplicates in run_id")

		return(parameters)
	}

####################################################################################################################################################
# 															 Math Functions
####################################################################################################################################################

	logit <- function(x) {
		return(log(x/(1-x)))
	}

#####################################################################################################################################################

	inv.logit <- function(x) {
		return(exp(x)/(exp(x)+1))
	}

#####################################################################################################################################################


	transform_data <- function(var, space, reverse=F) {
		if (space == "logit" & reverse==F) {
			var <- logit(var)
		} else if (space == "logit" & reverse==T) {
			var <- inv.logit(var)
		} else if (space == "log" & reverse==F) {
			var <- log(var)
		} else if (space == "log" & reverse==T) {
			var <- exp(var)
		}

		return(var)

	}

#####################################################################################################################################################

	delta_transform <- function(data, variance, space, reverse=F) {
		if (space == "logit" & reverse==F) {
			variance <- variance * (1/(data*(1-data)))^2
		} else if (space == "logit" & reverse==T) {
			variance <- variance / (1/(data*(1-data)))^2
		} else if (space == "log" & reverse==F) {
			variance <- variance * (1/data)^2
		} else if (space == "log" & reverse==T) {
			 variance <- variance / (1/data)^2
		}
		return(variance)
	}

####################################################################################################################################################
# 															 h5 utilities
####################################################################################################################################################

h5read.py = function(h5File, name) {
  
  listing = h5ls(h5File)

  if (!(name %in% listing$name)) stop(paste0(name, " not in HDF5 file"))
  
  # only take requested group (df) name
  listing = listing[listing$group==paste0('/',name),]
  
  # Find all data nodes, values are stored in *_values and corresponding column
  # titles in *_items
  data_nodes = grep("_values", listing$name)
  name_nodes = grep("_items", listing$name)
  
  data_paths = paste(listing$group[data_nodes], listing$name[data_nodes], sep = "/")
  name_paths = paste(listing$group[name_nodes], listing$name[name_nodes], sep = "/")
  
  columns = list()
  for (idx in seq(data_paths)) {
    data <- data.frame(t(h5read(h5File, data_paths[idx])))
    names <- t(h5read(h5File, name_paths[idx]))
    entry <- data.frame(data)
    colnames(entry) <- names
    columns <- append(columns, entry)
  }
  
  data <- data.frame(columns)
  
  return(data)
}

#####################################################################################################################################################

is.blank <- function(x) {
	 any(is.null(x))  || any(is.na(x))  || any(is.nan(x)) 
}