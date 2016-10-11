###########################################################
### Project: ubCov
### Purpose: Post-Model Cleaning and Stats
###########################################################

###################################################################
# Cleaning Process
###################################################################

full_results <- function(...) {


	#################
	# Prep
	#################

	vars <- c("location_id", "year_id", "age_group_id", "sex_id")

	## Adjusted Data
	data <- model_load(run_id, 'adj_data')
		cols <- c(vars, "data", "variance", "nid", grep("cv_", names(data), value=T))
		if ("outlier" %in% names(data)) cols <- c(cols, "outlier")
		data <- data[, cols, with=F]
		data <- data[, data := transform_data(data, data_transform, reverse=T)]
		data <- data[, variance := delta_transform(data, variance, data_transform, reverse=T)]
	## Prior
	prior <- model_path(run_id, 'prior') %>% h5read(., '/prior/ELT1') %>% data.table
		prior <- prior[, prior := transform_data(prior, data_transform, reverse=T)]
	## Spacetime
	st <- model_load(run_id, 'st')
		st <- st[, st := transform_data(st, data_transform, reverse=T)]
	## GPR
	gpr <- model_load(run_id, 'gpr')
		old <- c("gpr_mean", "gpr_lower", "gpr_upper")
		new <- paste(old, "_unraked", sep="")
		setnames(gpr, old, new)
		gpr <- gpr[, (new) := lapply(.SD, function(x) transform_data(x, data_transform, reverse=T)), .SDcols=new]
	## GPR Raked
	raked <- model_load(run_id, 'raked')

	#################
	# Merge
	#################

	## Merge
	df <- raked
	df <- merge(df, gpr, by=vars, all.x=T)
	df <- merge(df, st, by=vars, all.x=T)
	df <- merge(df, prior, by=vars, all.x=T)
	df <- merge(df, data, by=vars, all.x=T)

	#################
	# Clean
	#################


	return(df)
}

graph_prep <- function() {

	#################
	# Prep
	#################

	## Parameters
	data_path <- paste0(run_root, "/graph_temp.rds")
	temp_root <- paste0(run_root, "/graph_temp/")
	output_path <- paste0(run_root, "/ts_graph.pdf")

	## Make temp folder for output
	dir.create(temp_root, showWarnings = FALSE)

	## Save a temp file to be passed to graphing
	df <- full_results()
	saveRDS(df, file=data_path)

}

run_graphs <- function() {

	#################
	# Graph
	#################

	data_path <- paste0(run_root, "/graph_temp.rds")
	temp_root <- paste0(run_root, "/graph_temp/")
	output_path <- paste0(run_root, "/ts_graph.pdf")

	df <- readRDS(paste0(run_root, "/graph_temp.rds"))
	
	## Launch jobs to graph
	script <- paste0(model_root, "/make_graph.r")
	slots <- 4
	memory <- 8
	file_list <- NULL
	for (loc in unique(df$location_id)) {
		output <- paste0(temp_root, "/", loc, ".pdf")
		file_list <- c(file_list, output)
		args <- paste(model_root, "plot_ts", data_path, output, loc, sep=" ")
		qsub(job_name=paste0("graph_", run_id, "_", loc), script=script, slots=slots, memory=memory, arguments=args, cluster_project=cluster_project)
	}
	job_hold(paste0("graph_", run_id), file_list = file_list)

	#################
	# Append
	#################

	## Append graph, order by region, then alphabetically by ihme_loc_id
	loc.df <- get_location_hierarchy(41, china.fix=F)[, .(ihme_loc_id, region_id, location_id)]
	df <- merge(df, loc.df, by='location_id', all.x=T)
	locs <- df[order(region_id), location_id] %>% unique
	## Only keep if file exists
	locs <- locs[locs %in% as.numeric(gsub(".pdf", "", list.files(temp_root, ".pdf")))]
	files <- gsub(",", "", toString(paste0(temp_root, "/", locs, ".pdf")))
	## Append
	append_pdf(files, output_path)

	#################
	# Clean
	#################
	unlink(data_path, recursive=T)
	unlink(temp_root, recursive=T)

	print(paste0("Graph complete, saved to ", output_path))

}




