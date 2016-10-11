
cap program drop get_pct_treated
program define get_pct_treated
	version 12
	syntax , prefix(string) code_dir(string) [allyears]	
	
// Set arbitrary minimum fractiopn treated
	local min_treat .1
	
// Get list of GBD locations and years
	adopath + "`code_dir'/ado"
// Get covariates functions
	adopath + "$prefix/WORK/01_covariates/common/lib"
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	
// Get list of desired years
	get_demographics, gbd_team(epi)
	
// Get covariate values (need to pull final 2015 estimates from flat file for now because not properly uploaded to database yet)
	insheet using "$prefix/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015/03_steps/2015_08_17/01c_long_term_dws/01_inputs/hsa_capped_10_27_15.csv", comma names clear
	
// develop scale
	rename mean_value health_system
	gsort - health_system
	local max_value = health_system[1]
	local min_value = health_system[_N]
	set type double
	gen pct_treated = `min_treat' + ( (1 - `min_treat') * (health_system - `min_value') / (`max_value' - `min_value') )

// format
	keep location_id year_id pct_treated
	sort year_id location_id
	order location_id year_id pct_treated
	
end
