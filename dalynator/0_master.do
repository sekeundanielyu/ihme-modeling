// Purpose:	Calculate DALYs using CodCorrect/COMO/PAF inputs and upload to gbd database for visualization in GBD Compare and querying for publications
// Code:		do "/home/j/WORK/10_gbd/01_dalynator/01_code/prod/0_master.do"

// SET LOCALS
	// dev/prod (make sure to update path above)
		local envir		prod
	// local cluster envir
		local cluster_envir prod
	// initialize to delete and recreate version folder (yes/no)
		local init		no
	// GBD year round
		local gbd_round_id 3 // GBD_round = 2015
	// dalynator output_version_id
		local gbd		119
	// cod/epi output_version_id (0=skip)
		local cod		41
		local epi		96
		local risk		177
	// set our location_set_version
		local location_set_version 75
	// set our cause_set_id
		local cause_set_id 3 // GBD reporting
	// risk overlap table too?
		local risk_overlap no

	// submit locations 
		local submit_loc5	yes // Most-detailed subnational
		local submit_loc4	yes // Sub-national
		local submit_loc3	yes // Countries
		local submit_loc2	yes // Regions
		local submit_loc1	yes // Super-region
		local submit_loc0	yes // Global
		local SDS yes // SDS groupings (runs with global)
		
		// "Mini run" - just a few countries
		local mini no

	// upload
		local upload	yes
		local cod_table 265
		local risk_table 317
		local etiology_table 318
		local summary_table 311

	// regional scalars
		local scalars 18
		
	// MEMORY
		clear all
		set more off, perm
		set maxvar 32000
		local mem 2
		local min_memory = round(0.5  * `mem', .1)
		local max_memory = round(0.75 * `mem', .1)
		set min_memory `min_memory'g
		set max_memory `max_memory'g
		set niceness 0
		
	// DIRECTORIES
		if c(os) == "Unix" {
			global j "/home/j/"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global j "J:"
		}
		
		local username = c(username)
		cd /snfs2/HOME/`username'/

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// PREP STATA (SHOULDN'T NEED TO MODIFY PAST THIS POINT)
	adopath + "$j/WORK/10_gbd/00_library/functions"
	local cod_dir "/share/central_comp/codcorrect/`cod'/draws"
	local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"
	local risk_dir "/share/central_comp/pafs/`risk'"
	local code_dir "$j/WORK/10_gbd/01_dalynator/01_code/`envir'"
	local in_dir "$j/WORK/10_gbd/01_dalynator/02_inputs"
	local out_dir "$j/WORK/10_gbd/01_dalynator/03_results/`gbd'"
	local tmp_dir "/share/central_comp/dalynator/`gbd'"
	
	if "`init'" == "yes" {
		display _newline(5) "You are about to delete the last run, type yes to continue." _newline(2) _request(initok)
		noisily display "$initok"
		if lower("$initok") != "yes" error(999) 
	}

	foreach dir in out_dir tmp_dir {
		if "`init'" == "yes" {
			! rm -rf "``dir''"
		}
		! mkdir "``dir''"
		! chmod o+rx "`dir'"
		! chmod 777 "`dir'"
		! mkdir "``dir''/checks"
		! mkdir "``dir''/diagnostics"
		! mkdir "``dir''/draws"
		! mkdir "``dir''/logs"
		! mkdir "``dir''/summary"
		! mkdir "``dir''/temp"
		! mkdir "``dir''/temp/upload"
		! mkdir "``dir''/draws_convergence"
	}

	capture log close
	log using "`tmp_dir'/logs/log.smcl", replace

** for job submission
if "`cluster_envir'"=="dev" local project = ""
else local project = "-P proj_dalynator "

** for db upload
if "`cluster_envir'"=="dev" local server = "dev"
else local server = "prod"

	local mem_job = 24 // 12 slots per job
	local year_ids 1990 1995 2000 2005 2010 2015
	local num_y : word count `year_ids'

	** set year_ids to pass for upload
	if `num_y' > 10 local upload_type = "cod"
	else local upload_type = "epi"

	local upload_mem = 30

** load files for parallel script
** pull pop
	odbc load, exec("SELECT location_id, year_id, sex_id, age_group_id, pop_scaled FROM mortality.output JOIN mortality.output_version USING (output_version_id) WHERE is_best=1") `conn_string' clear	
	save $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/envelope_`gbd'.dta, replace

	** pull age weights
	odbc load, exec("SELECT age_group_id, age_group_weight_value FROM shared.age_group_weight LEFT JOIN shared.gbd_round USING (gbd_round_id) WHERE gbd_round_id in ('`gbd_round_id'') AND age_group_weight_description LIKE 'IHME%'") `conn_string' clear
	save $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/age_W_`gbd'.dta, replace

	** prep causes and age_group_id restrictions
	odbc load, exec("SELECT chh.cause_set_version_id, chh.cause_set_id, chh.cause_id, chh.cause_id AS cause_id_dup, chh.level, chh.is_estimate, chh.parent_id, chh.path_to_top_parent, chh.sort_order, chh.cause_outline, chh.cause_name, chh.most_detailed, chh.male, chh.female, CAST(yll_age_group_id_start.cause_metadata_value AS CHAR) as yll_age_group_id_start, CAST(yll_age_group_id_end.cause_metadata_value AS CHAR) as yll_age_group_id_end, CAST(yld_age_group_id_start.cause_metadata_value AS CHAR) as yld_age_group_id_start, CAST(yld_age_group_id_end.cause_metadata_value AS CHAR) as yld_age_group_id_end FROM shared.cause_hierarchy_history chh LEFT OUTER JOIN shared.cause_metadata yll_age_group_id_start ON chh.cause_id = yll_age_group_id_start.cause_id AND yll_age_group_id_start.cause_metadata_type_id = 21 LEFT OUTER JOIN shared.cause_metadata yll_age_group_id_end ON chh.cause_id = yll_age_group_id_end.cause_id AND yll_age_group_id_end.cause_metadata_type_id = 22 LEFT OUTER JOIN shared.cause_metadata yld_age_group_id_start ON chh.cause_id = yld_age_group_id_start.cause_id AND yld_age_group_id_start.cause_metadata_type_id = 23 LEFT OUTER JOIN shared.cause_metadata yld_age_group_id_end ON chh.cause_id = yld_age_group_id_end.cause_id AND yld_age_group_id_end.cause_metadata_type_id = 24 WHERE cause_set_version_id = shared.active_cause_set_version(`cause_set_id',`gbd_round_id') ORDER BY chh.sort_order") `conn_string' clear

	destring *age*, replace
	save $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, replace

	** load measures
		odbc load, exec("SELECT measure_id, measure FROM shared.measure") `conn_string' clear
		compress
		save $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/measures.dta, replace
		
	** load metrics
		odbc load, exec("SELECT metric_id, metric_name AS metric FROM gbd.metric") `gbd_connect' clear
		replace metric = lower(metric)
		compress
		save $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/metrics.dta, replace

	** pull shock version
		odbc load, exec("SELECT shock_version_id FROM cod.shock_version WHERE shock_version_status_id = 1") `conn_string' clear
		levelsof shock_version_id, local(shock_version) c

** Check risks are done
qui do "$j/WORK/10_gbd/00_library/functions/get_demographics.ado"
get_demographics, gbd_team("epi")
local LOCS : word count $location_ids

local num_r = (`num_y' * `LOCS')

	local r = 0
		while `r' == 0 {
			local draws_r : dir "`risk_dir'" files "*.dta", respectcase
			local nr : word count `draws_r'
			di "Checking `c(current_time)': `nr' of `num_r' risks"
			if (`nr' == `num_r') local r = 1
			else sleep 60000
		}

** Check COMO is done
qui do "$j/WORK/10_gbd/00_library/functions/get_demographics.ado"
get_demographics, gbd_team("epi")
local LOCS : word count $location_ids

local num_e = (`num_y' * `LOCS' * 2)

	local e = 0
		while `e' == 0 {
			local draws_e : dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs" files "*.csv", respectcase
			local ne : word count `draws_e'
			di "Checking `c(current_time)': `ne' of `num_e' YLD draws"
			if (`ne' == `num_e') local e = 1
			else sleep 60000
		}

** build location hierarchy and submit jobs

odbc load, exec("SELECT lhh.level AS location_level,lhh.location_id,lhh.location_name,lhh.parent_id,lhh.location_type,lhh.most_detailed,(SELECT GROUP_CONCAT(location_id) FROM shared.location_hierarchy_history WHERE location_set_version_id = `location_set_version' and parent_id = lhh.location_id) AS children FROM shared.location_hierarchy_history lhh WHERE lhh.location_set_version_id = `location_set_version' GROUP BY lhh.location_id, lhh.location_name, lhh.parent_id, lhh.location_type, lhh.most_detailed ORDER BY lhh.sort_order") `conn_string' clear
replace children = subinstr(children,"1,4","4",.) if location_id == 1
replace children = subinstr(children,","," ",.)
replace children = "." if children==""

** SDS groupings
if "`SDS'" == "yes" {
	append using $j/temp/`username'/GBD_2015/SDS_06_20_16.dta
}

** mini run is just a number of countries for diagnostics
** Here I selected one from each region with no subnational components
if "`mini'"=="yes" {
local mini_message "geos: 1 random country per GBD region to review risks"
gen keep = 0
// replace keep = 1 if location_id==20 // Vietnam
replace keep = 1 if location_id==7 // North Korea
// replace keep = 1 if location_id==22 // Fiji
replace keep = 1 if location_id==38 // Mongolia
replace keep = 1 if location_id==51 // Poland
replace keep = 1 if location_id==63 // Ukraine
replace keep = 1 if location_id==68 // South Korea
replace keep = 1 if location_id==71 // Australia
replace keep = 1 if location_id==90 // Norway
replace keep = 1 if location_id==80 // France
replace keep = 1 if location_id==98 // Chile
replace keep = 1 if location_id==101 // Canada
replace keep = 1 if location_id==114 // Haiti
replace keep = 1 if location_id==121 // Bolivia
replace keep = 1 if location_id==125 // Colombia
replace keep = 1 if location_id==136 // Paraguay
replace keep = 1 if location_id==141 // Egypt
replace keep = 1 if location_id==160 // Afghanistan
replace keep = 1 if location_id==170 // Congo
replace keep = 1 if location_id==179 // Ethiopia
replace keep = 1 if location_id==193 // Botswana
replace keep = 1 if location_id==204 // Chad
replace keep = 1 if location_id==142 // Iran
replace keep = 1 if location_id==62 // Russia
replace keep = 1 if location_id==98 // Argentina
replace keep = 1 if location_id==140 // Bahrain
replace keep = 1 if location_id==57 // Belarus
replace keep = 1 if location_id==11 // Indonesia
keep if keep == 1 
}

local num_loc = _N
levelsof location_id, local(geos) c
		
** additional message to be emailed out (ie "full time series or UK specific")
local message ""
if "`mini'"=="yes" {
local message "years `year_ids' `mini_message'"
}
	quietly summ location_level
	local lvl_max = r(max)

	tempfile location_hierarchy
	save `location_hierarchy', replace

	forvalues loclvl = `lvl_max'(-1)0 {
		// Skip this level if the submit indicator isn't 1
		if "`submit_loc`loclvl''" != "yes" continue
	
		// Get list of all locations in this level
		use `location_hierarchy', clear
		keep if location_level == `loclvl'
		local loc_count = _N

		// Submit job for each row (ie location) for remaining years
		forvalues iii = 1/`loc_count' {
			// Get location information
			local location_id = location_id[`iii']
			local children = children[`iii']
			
			// Launch jobs
				foreach year_id of local year_ids {
					// Calculate cluster resources needed.
						if `year_id' != 2015 & `year_id' != 2005 local mem = `mem_job'
						else local mem = 2 * `mem_job' // more memory for 2005 and 2015 because we calc % change
						local slot = ceil(`mem' / 2)
						
						capture confirm file "`tmp_dir'/checks/loclvl`loclvl'_agg_`location_id'_`year_id'.txt"

							if _rc {
								sleep 200
									! qsub -P proj_dalynator -N "DALY_`location_id'_`year_id'" -pe multi_slot `slot' -l mem_free=`mem' -o /share/temp/sgeoutput/`username'/output "`code_dir'/stata_shell.sh" "`code_dir'/1_parallel.do" "`gbd_round_id' `envir' `gbd' `cod' `epi' `risk' `scalars' `mem' `loclvl' `location_id' `year_id' `shock_version' `cause_set_id' \"`children'\"" "`location_id'_`year_id'" 

							}
					
					
				}

		}

		// check level has finished
			local total_jobs = `loc_count' * `num_y'
			local i = 0
			while `i' == 0 {
				local draws : dir "`tmp_dir'/checks" files "loclvl`loclvl'_agg*.txt", respectcase
				local n : word count `draws'
				di "Checking `c(current_time)': `n' of `total_jobs', location level `loclvl' draws"
				if (`n' == `total_jobs') local i = 1
				else sleep 60000
			}
			file open finish using "`tmp_dir'/checks/all_agg_level_`loclvl'_complete.txt", write replace
			file close finish
	}


// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

	// wait for summary results
	local num = `num_loc' * `num_y'

		local i = 0
		while `i' == 0 {
			local draws : dir "`tmp_dir'/checks" files "*summary*.txt", respectcase
			local n : word count `draws'
			di "Checking `c(current_time)': `n' of `num' location-year_id summaries"
			if (`n' == `num') local i = 1
			else sleep 60000
		}
		
// UPLOAD
if "`upload'" == "yes" {
	// LAUNCH UPLOAD JOBS
if "`epi'"!="0" local measures 1 2 3 4
else local measures 1 4

foreach type in single_year multi_year {
	foreach measure of local measures {
		! qsub -P proj_dalynator -N "upload_dalynator_`measure'_`type'" -pe multi_slot 4 -l mem_free=8G -o /share/temp/sgeoutput/`username'/output "`code_dir'/stata_shell.sh" "`code_dir'/2_upload_risks.do" "`gbd' `server' `measure' `type' `cod_table' `risk_table' `etiology_table' `summary_table'"

	}
}

** number of jobs * 2 for multi year
local num_u : word count `measures'
local jobs = `num_u' * 2

		local i = 0
		while `i' == 0 {
			local uploads : dir "`tmp_dir'/checks" files "uploaded*.txt", respectcase
			local n : word count `uploads'
			di "Checking `c(current_time)': `n' of `jobs' complete"
			if (`n' == `jobs') local i = 1
			else sleep 60000
		}

		!echo "DALYnator v`gbd' is uploaded (cod=`cod', epi=`epi', risk=`risk') `message'" | mailx -s "DALYnator v`gbd' uploaded" `username'@uw.edu

}		

noi di c(current_time) + ": DALYnator has DALYnated"

cap log close


