###########################################################
### Project: ubCov
### Purpose: Raking/Aggregation
###########################################################

###################
### Setting up ####
###################

source('utility.r')

###################################################################
# Raking blocks
###################################################################

tag_p_comp <- function(df) {

  # Generate the average estimate by parent, sex, and age
  df <- df[, p_mean := mean(gpr_mean), by=c("parent_id", "age_group_id", "sex_id")]
    
  # Generate an indicator for subnationals which should be raked in p_complement space
  df <- df[, p_comp := ifelse(p_mean > 0.6 & level > 3, 1, 0)]
    
  # Tag p_comp = 1 on the children of any parent_loc that has p_comp = 1
  parent_df <- unique(df[p_comp==1, .(parent_id,  age_group_id, sex_id, p_comp)])
  setnames(parent_df,  c("p_comp", "parent_id"), c("p_comp_parent", "location_id"))
  df <-merge(df, parent_df, by=c("age_group_id", "sex_id", "location_id"), all.x=TRUE)
  df <- df[p_comp_parent == 1, p_comp := 1]
  df <- df[, c("p_comp_parent", "p_mean") := NULL]

}

apply_p_comp <- function(df, vars) {
  df<- df[p_comp==1, (vars) := lapply(.SD, p_complement), .SDcols=vars]
  return(df)
}

p_complement <- function(x) {
  return(x <- 1 - x)
}

calculate_rf <- function(df) {

	## Rakes all of children to parents for a given child level

	## Calculate parent sum
	sum <- copy(df)
	sum <- sum[, parent_sum := gpr_mean * pop_scaled]
	sum <- sum[, .(location_id, year_id, age_group_id, sex_id, parent_sum)]
	setnames(sum, "location_id", "parent_id") 

	## Get sum of population weighted totals at level
	out <- copy(df)
  out <- out[, aggregated_sum := sum(gpr_mean * pop_scaled, na.rm=T), by=c("parent_id", "year_id", "age_group_id", "sex_id")]
	## Merge parent sum on
	out <- merge(out, sum, by=c("parent_id", "year_id", "age_group_id", "sex_id"), all.x=T)
	## Get ratio of parent to aggregation
	out <- out[, rake_factor := aggregated_sum/parent_sum]
  out <- out[, c("aggregated_sum", "parent_sum") := NULL]

	return(out)

}

rake_estimates <- function(df, lvl, vars, dont_rake) {
  df <- calculate_rf(df)
  ## Save unraked estimates if no draws
  if (draws == 0) df <- df[level == lvl & !is.na(rake_factor) & !is.element(parent_id, dont_rake), 
                                  paste0(vars, "_unraked") := lapply(.SD, function(x) x), .SDcols=vars]
  ## Rake particular level if theres a rake factor and parent isnt an element in dont_rake
  df <- df[level == lvl & !is.na(rake_factor) & !is.element(parent_id, dont_rake), 
            (vars) :=lapply(.SD, function(x) x/df[level == lvl & !is.na(rake_factor) & !is.element(parent_id, dont_rake), rake_factor]), .SDcols=vars]
  ## Clear rake_factor
  df <- df[, rake_factor := NULL]
  return(df)
}

aggregate_estimates <- function(df, vars, parent_ids) {
  ## Drop locations being created by aggregation
  df <- df[!location_id %in% parent_ids]
  ## Subset to requested parent_ids
  agg <- df[parent_id %in% parent_ids] %>% copy
  key <- c("parent_id", "year_id", "age_group_id", "sex_id")
  ## Aggregate estimates to the parent_id [ sum(var * pop) /sum_pop ]
  agg <- agg[, sum_pop := sum(pop_scaled), by=key]
  agg <- agg[, (vars) := lapply(.SD, function(x) x * agg[['pop_scaled']]), .SDcols=vars]
  agg <- agg[, (vars) := lapply(.SD, sum), .SDcols=vars, by=key]
  ## De-duplicate so get one set of estimates
  agg <- unique(agg[, c("parent_id", "year_id", "age_group_id", "sex_id", "sum_pop", vars), with=F])
  ## Divide by sum_pop
  agg <- agg[, (vars) := lapply(.SD, function(x) x/agg[['sum_pop']]), .SDcols=vars]
  agg <- agg[, sum_pop := NULL]
  ## Rename parent_id -> location_id
  setnames(agg, "parent_id", "location_id")
  df <- rbind(df, agg, fill=T)
  return(df)
}

save_draws <- function(df, run_id) {

  ## Check that all locations exist
  locs <- get_location_hierarchy(location_set_version_id)[level >= 3 & level <6]$location_id
  missing.locs <- setdiff(locs, unique(df$location_id))
  if (length(missing.locs) != 0) stop(paste0("missing locations ", toString(missing.locs)))
  ## Restrict columns
  cols <- c("location_id", "year_id", "age_group_id", "sex_id", grep("draw_", names(df), value=T))
  df <- df[, cols, with=F]
  ## Create measure_id col
  if (measure_type=="continuous") df <- df[, measure_id := 19]
  if (measure_type=="proportion") df <- df[, measure_id := 18]
  ## Save by locs
  output_path <- paste0(run_root, "/draws_temp")
  system(paste0("rm -rf ", output_path))
  system(paste0("mkdir -m 777 -p ", output_path))
  mclapply(locs, function(x) write.csv(df[location_id==x], paste0(output_path, "/", x, ".csv"), row.names=F, na=""), mc.cores=cores) %>% invisible
  print(paste0("Draw files saved to ", output_path))

}

###################################################################
# Raking Process
###################################################################

run_rake <- function(get.df=FALSE) {


  ####################
  # Setup
  ####################

  ## Load
  if (draws == 0) df <- model_load(run_id, "gpr")
  if (draws > 0) df <- mclapply(paste0(run_root, "/gpr_temp/") %>% list.files(.,full.names=T), fread, mc.cores=cores) %>% rbindlist

	## Identify which variable names you need to rake
	if (draws > 0) vars <- paste0("draw_", seq(0, draws-1)) else vars <- c("gpr_mean", "gpr_lower", "gpr_upper")

  ## Backtransform outputs
  df <- df[, (vars) := lapply(.SD, function(x) transform_data(x, data_transform, reverse=T)), .SDcols=vars]
		
  ## Set countries you don't want to rake for
  if (!is.blank(aggregate_ids)) aggregate_ids<-as.numeric(unlist(strsplit(gsub(" ", "", aggregate_ids), split = ",")))
  ## Aggregate for location 6 automatically
  aggregate_ids <- aggregate_ids[!is.na(aggregate_ids)] %>% unique

	## Merge on populations
	pops <- get_populations(location_set_version_id, year_start, year_end, by_sex, by_age)
	df <- merge(df, pops, by=c("location_id", "year_id", "age_group_id", "sex_id"))

	## Merge on location hierarchy
	locs <- get_location_hierarchy(location_set_version_id)[, .(location_id, parent_id, level)]
	df <- merge(df, locs, by="location_id")

  #########################
  # P complement and rake
  #########################

  if (rake_flag) {

	  ## Calculate mean if draws
	  if (draws > 0) df <- df[, gpr_mean := rowMeans(df[, (vars), with=F])]
	
	  ## Apply pcomp where necessary
	  if (data_transform == 'logit') {
	    df <- tag_p_comp(df)
	    df <- apply_p_comp(df, vars)
	  }
	  
	  ## Rake
	  for (lvl in c(4,5)) df <- rake_estimates(df=df, lvl=lvl, vars=vars, dont_rake=aggregate_ids)
	
	  ## Reverse pcomp
	  if (data_transform == 'logit') df <- apply_p_comp(df, vars)

	}

  #########################
  # Aggregate where needed
  #########################

  ## Use non-china fix hierarchy
  locs <- get_location_hierarchy(location_set_version_id)[, .(location_id, parent_id, level)]
  df <- df[,c("parent_id", "level") := NULL]
  df <- merge(df, locs, by='location_id', all.x=T)
  	
  ## Aggregate
  if (!rake_flag) {
      lvl_parents <- locs[level==5, parent_id] %>% unique
      df <- aggregate_estimates(df=df, vars=vars, parent_ids=lvl_parents)
      df <- df[,c("pop_scaled", "parent_id", "level"):=NULL]
      df <- merge(df, pops, by=c("location_id", "year_id", "age_group_id", "sex_id"))
      df <- merge(df, locs, by='location_id', all.x=T)
      lvl_parents <- locs[level==4, parent_id] %>% unique
      df <- aggregate_estimates(df=df, vars=vars, parent_ids=lvl_parents)
  } else {
      print(aggregate_ids)
    df <- aggregate_estimates(df=df, vars=vars, parent_ids=aggregate_ids)
  }

  #########################
  # Clean and save
  #########################
  	
  ## Clean
  varlist <- c("location_id", "year_id", "age_group_id", "sex_id", vars)
  df <- df[, varlist, with=F]
    	  	
  ## Sort
  df <- df[order(location_id, year_id, age_group_id, sex_id)]

  if (!get.df) {

  	if (draws == 0) model_save(df, run_id, 'raked')
  	
  	if (draws > 0) save_draws(df, run_id)

  } else return(df)

}


