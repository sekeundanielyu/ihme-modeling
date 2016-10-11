
** **************************************************************************
** RUNTIME CONFIGURATION
** **************************************************************************
// Set preferences for STATA
	// Clear memory and set memory and variable limits
		clear all
		set mem 12g
		set maxvar 32000
	// Set to run all selected code without pausing
		set more off
	// Set graph output color scheme
		set scheme s1color
	// Remove previous restores
		capture restore, not
	// Define J drive (data) for cluster (UNIX) and Windows (Windows)
		if c(os) == "Unix" {
			global prefix "/home/j"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global prefix "J:"
		}
		
// Close previous logs
	cap log close
	
// Create timestamp for logs
	local c_date = c(current_date)
	local c_time = c(current_time)
	local c_time_date = "`c_date'"+"_" +"`c_time'"
	display "`c_time_date'"
	local time_string = subinstr("`c_time_date'", ":", "_", .)
	local timestamp = subinstr("`time_string'", " ", "_", .)
	display "`timestamp'"
	
// Create macros to contain toggles for various blocks of code:
	local create_age_trend 0
	local prep_datasets 1

// Store filepaths/values in macros
	local age_codebook_data 		"$prefix/WORK/05_risk/risks/envir_lead_blood/data/exp/codebook/age_codebook.xlsx"
	local updated_population_file 	"$prefix/Project/Mortality/Population/USABLE_POPULATION_GLOBAL_1970-2013_archive.dta"
	local age_pattern				"$prefix/WORK/05_risk/risks/envir_lead_blood/data/exp/age_trend/pred_out.csv"
	local lead_data 				"$prefix/WORK/05_risk/risks/envir_lead_blood/data/exp/raw/gbd2013_lead_exp.dta"
	local temp_dir 					"/ihme/gbd/WORK/05_risk/temp/lead/data/blood/"
	local logs 						"/ihme/gbd/WORK/05_risk/temp/lead/logs/blood/"
	
// Locals from shell script
	 local iso3 = 			"${iso3}"	
	//local iso3 = "TWN"
	
// Set to log
	log using "`logs'/`iso3'_age_sex_split_`timestamp'.log", replace
	
** **************************************************************************
** CREATE A DATASET TO INFORM AGE-TREND IN BRADMOD
** **************************************************************************	
	
if `create_age_trend' == 1 {

	// output a dataset to run through Bradmod and inform our age trend
	
	// import data
		use `lead_data', clear
		
	// Keep all country years that have multiple age/sex groups from which to inform our age trend
		gen year = floor((year_start + year_end) / 2)
		tostring year, gen(year_string)
		gen country_year = iso3 + "_" + year_string
		levelsof country_year, local(country_years)
			foreach country_year in `country_years' {
			
				di in red "`country_year'"
				tab age_start if country_year == "`country_year'"
				drop if r(r) < 2 & country_year == "`country_year'"
				
			}
			
	drop if standard_error == .
	
	// Output age trend dataset for input to Bradmod
		save `output'/lead_age_trend_dataset.dta, replace

		
}

** **************************************************************************
** PREP DATASETS TO FEED INTO AGE AND AGE/SEX SPLITTING MODULES
** **************************************************************************	

if `prep_datasets' == 1	{

	// Using updated population file from Mortality team  in order to have population before 1970 
		use iso3 year sex pop* using `updated_population_file', clear 
			replace sex = proper(sex)
		reshape long pop_, i(iso3 year sex) j(age) string // reshape this file long to match normal population file
			replace pop = pop * 1000 // estimates currently stored in thousands, convert to real numbers
			rename pop mean_pop
			drop if age == "100_" | age == "95_99" | age == "90_94" | age == "85_89" | age == "80_84" 
			
			// replace age names to match GBD standards
				replace age = "0_" if age == "0"
				replace age = ".1_" if age == "nn"
				replace age = ".01_" if age == "pnn"
				generate splitat = strpos(age, "_")
				replace age = substr(age,1,splitat - 1)
				drop split
	
	destring age, force replace
	drop if age == .
	tempfile pop
	save `pop'				
			
	
	// Load age/age-sex codebook
		preserve
		import excel using `age_codebook_data', firstrow sheet("age_split") clear
		tempfile age_codebook
		save `age_codebook', replace
		restore
		
		preserve
		import excel using `age_codebook_data', firstrow sheet("age_sex_split") clear
		tempfile age_sex_codebook
		save `age_sex_codebook', replace
		restore


	preserve
	************ Load age pattern
	insheet using `age_pattern', comma clear nodouble
	keep integrand age_lower age_upper pred_lower pred_median pred_upper
	gen age = string(round(age_lower,.001))
	tempfile shape
	save `shape'
	restore

	tostring age, replace force
	merge m:1 age using `shape', keep(match) nogen

	// replace age/sex as a numeric for later use
		destring age, replace
		gen sexnum = 1 if sex == "Male"
		replace sexnum = 2 if sex == "Female"
		replace sexnum = 3 if sex == "Both"
		drop sex
		rename sexnum sex
		
	// Modifications
		drop age_lower age_upper
			// Merge on the correct age bounds using the prepared age codebook
				merge m:1 age using `age_codebook', nogen
		sort iso3 year age_start_split
		rename pred_median shp
			drop pred* // this drops the confidence interval bounds, currently not using them because I am not propagating uncertainty in this version of age/sex splitting. 
			
	save `shape', replace

	use `lead_data' if iso3_parent == "`iso3'", clear
	

	rename mean exp_mean
	gen year = floor((year_start + year_end) / 2) // generate a mid-year value to indicate which year to pull the age shape from
	
	// use iso3 parent as iso3 since we don't have a shape for subnational - remove this when we can generate a new shape with subnational values
		rename iso3 iso3_child
		rename iso3_parent iso3

// Create separate datasets, because age splitting and age-sex splitting currently happen in two different steps
	preserve
	drop if sex == 3 
	tempfile age_split_data
	save `age_split_data', replace
	if _N == 0 {
	
		local age_split = 0 // toggle this block of code not to run because there are no datapoints needing age only splitting for this country
		restore
		
	}
	
	else {
	
		local age_split = 1 // toggle this block of code to run because there are datapoints needing age only splitting for this country 
		restore
		
	}
	
	preserve
	drop if sex != 3 
	tempfile age_sex_split_data
	save `age_sex_split_data', replace
	if _N == 0 {
	
		local age_sex_split = 0 // toggle this block of code not to run because there are no datapoints needing age sex splitting for this country
		restore
		
	}
	
	else {
	
		local age_sex_split = 1 // toggle this block of code to run because there are datapoints needing age sex splitting for this country 
		restore
		
	}


}

** **************************************************************************
** SPLIT SEX-SPECIFIC DATA BY AGE
** **************************************************************************	

if `age_split' == 1 {

	use `age_split_data', clear
			
	sort iso3 year
	
	set matsize 11000
	cap drop seri
	gen seri=_n
	gen ageend= age_e
	gen agestart= age_s
	qui tab seri
	local n=r(r)
	mat new_ages=J(`n',21,0)
	mat new_means=J(`n',21,0)
	mat ageg=[0,.0099\.01,.099\.1,.99\1,4\5,9\10,14\15,19\20,24\25,29\30,34\35,39\40,44\45,49\50,54\55,59\60,64\65,69\70,74\75,79\80,100] //current DisMod age groups as I understand them 
	 
	 
	forval j=1/`n' {
	
				mat new_ages[`j',1]=`j'
				mat new_means[`j',1]=`j'
				local iso3=iso3[`j']
				local sex=sex[`j']
				local year=year[`j']
				local start=agestart[`j']
				local end=ageend[`j']
				di in green "******************Working on `iso3' `sex' `year' Ages: `start' - `end', row `j'******************"
				local pass 0
				local i = 1
				
				while `i'<21 {
				
					local min=ageg[`i',1] 
					local max=ageg[`i',2] 
					
					if (`end' <= `max' & `pass' == 1) { 
					
						mat new_ages[`j',`i'+1] = `end' - `min' + 1
						local current_agr = `end' - `min' + 1	
						di in yellow "min: `min' | end: `end'  -> years = `current_agr' "
						local pass 0
						
						preserve
						use if iso3 == "`iso3'" & sex == `sex' & year == `year' using `shape', clear
						drop if age_start_split > `end' | age_end_split < `start'
						mean shp [pw=mean_pop]
						matrix mean_matrix = e(b)
						local average = mean_matrix[1,1]
						drop if age != `min'
						local current_age = shp 
						local correction_factor = `current_age' / `average'
						restore
						
						local new_mean = exp_mean[`j'] * `correction_factor' 
						mat new_means[`j',`i'+1] = `new_mean'
						di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
						
					}
					
					if (`pass' == 1) {
					
						mat new_ages[`j',`i'+1] = `max' - `min' + 1
						local current_agr = `max' - `min' + 1
						di in yellow "min: `min' | max: `max'  -> years = `current_agr'" _c
						
						preserve
						use if iso3 == "`iso3'" & sex == `sex' & year == `year' using `shape', clear
						drop if age_start_split > `end' | age_end_split < `start'
						mean shp [pw=mean_pop]
						matrix mean_matrix = e(b)
						local average = mean_matrix[1,1]
						drop if age != `min'
						local current_age = shp 
						local correction_factor = `current_age' / `average'
						restore
						
						local new_mean = exp_mean[`j'] * `correction_factor' 
						mat new_means[`j',`i'+1] = `new_mean'
						di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
			
					}
					
					if (`start' >= `min' & `start' <= `max' & `pass' == 0) { 
					
						di in yellow "start: `start' /// " _c
						
						if `end'<=`max' { 
						
							mat new_ages[`j',`i'+1] = `end' - `start' + 1
							local pass 0
							local current_agr = `end' - `start' + 1
							di in yellow "end: `end' -> years = `current_agr'" 
							
							preserve
							use if iso3 == "`iso3'" & sex == `sex' & year == `year' using `shape', clear
							drop if age_start_split > `end' | age_end_split < `start'
							mean shp [pw=mean_pop]
							matrix mean_matrix = e(b)
							local average = mean_matrix[1,1]
							drop if age != `min'
							local current_age = shp 
							local correction_factor = `current_age' / `average'
							restore
							
							local new_mean = exp_mean[`j'] * `correction_factor' 
							mat new_means[`j',`i'+1] = `new_mean'
							di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
							
						}
						
						if (`end' >= `max' & `start' >= `min') {
						
							mat new_ages[`j',`i'+1] = `max' - `start' + 1
							local pass 1
							local current_agr = `max' - `start' + 1
							di in yellow "min: `min' | max: `max'  -> years = `current_agr'" _c
							
							preserve
							use if iso3 == "`iso3'" & sex == `sex' & year == `year' using `shape', clear
							drop if age_start_split > `end' | age_end_split < `start'
							mean shp [pw=mean_pop]
							matrix mean_matrix = e(b)
							local average = mean_matrix[1,1]
							drop if age != `min'
							local current_age = shp 
							local correction_factor = `current_age' / `average'
							restore
							
							local new_mean = exp_mean[`j'] * `correction_factor' 
							mat new_means[`j',`i'+1] = `new_mean'
							di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"							
						
						}
						
						else local pass 1
						
					}

					local i=`i'+1
				
				}
	}
	
	svmat new_ages,names(agegr)
	svmat new_means,names(exp_mean_new)
	drop agegr1
	reshape long agegr exp_mean_new, i( seri ) j( age )
	drop if agegr <= 0  | agegr == . // drop any age groups that don't actually have any years contributed to them
	rename age age_code

	// Merge on the age codebook to replace age start and age end with their split value
		merge m:1 age_code using `age_codebook', keep(mat) nogen
		
	// Temporary commands to make this easier to look at during my exploratory analysis
		drop acause grouping healthstate study_status page_num table_num source_type data_type parameter_type orig* notes case*
		drop ageend agestart
		order seri age* iso3 sex year* exp* 
		
	// logic in the above loop adds an additional year to the calculated difference between ages. This is erroneous in the bottom 3 age groups, so I will replace with the correct amount of years in that age group
		replace agegr = (age_end_split - age_start_split) if age_end_split == .0099 | age_end_split == .099 | age_end_split == .99 
		
	// Replace the old age groups with the new split ones (keep on the old age groups for reference)
		foreach var of varlist age_start age_end {
		
			rename `var' `var'_orig
			rename `var'_split `var'
			
		}
	
	// Tempfile and save to prep for appending both datasets at the end
		tempfile age_split_complete
		save `age_split_complete', replace

}

** **************************************************************************
**  SPLIT DATA BY AGE AND SEX
** **************************************************************************	

if `age_sex_split' == 1 {

	use `age_sex_split_data', clear
	
	** keep if iso3 == "USA" // for speed testing, remove later
		
	sort iso3 year
	
	set matsize 11000
	cap drop seri
	gen seri=_n
	gen ageend= age_e
	gen agestart= age_s
	qui tab seri
	local n=r(r)
	clear matrix // reset matrices so that they can be reused without conformability errors
	mat new_ages=J(`n',42,0)
	mat new_means=J(`n',42,0)
	mat ageg=[0,.0099\.01,.099\.1,.99\1,4\5,9\10,14\15,19\20,24\25,29\30,34\35,39\40,44\45,49\50,54\55,59\60,64\65,69\70,74\75,79\80,100] 
	
 
	forval j=1/`n' {
	
		forvalues sex = 1/2 {	
	
				mat new_ages[`j',1]=`j'
				mat new_means[`j',1]=`j'
				local iso3=iso3[`j']
				local year=year[`j']
				local start=agestart[`j']
				local end=ageend[`j']
				di in green "******************Working on `iso3' `sex' `year' Ages: `start' - `end', row `j'******************"
				local pass 0
				local i = 1
				
				while `i'<21 {
				
					if `sex' == 1 {
						local if_female = 0
					}
					else if `sex' == 2 {
						local if_female = 20
					}					
				
					local min=ageg[`i',1] 
					local max=ageg[`i',2] 
					
					if (`end' <= `max' & `pass' == 1) { 
					
						mat new_ages[`j',`i'+1+`if_female'] = `end' - `min' + 1
						local current_agr = `end' - `min' + 1	
						di in yellow "min: `min' | end: `end'  -> years = `current_agr' "
						local pass 0
						
						preserve
						use if iso3 == "`iso3'" & year == `year' using `shape', clear
						drop if age_start_split > `end' | age_end_split < `start'
						mean shp [pw=mean_pop]
						matrix mean_matrix = e(b)
						local average = mean_matrix[1,1]
						drop if age != `min' | sex != `sex'
						local current_age = shp 
						local correction_factor = `current_age' / `average'
						restore
						
						local new_mean = exp_mean[`j'] * `correction_factor' 
						mat new_means[`j',`i'+1+`if_female'] = `new_mean'
						di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
						
					}
					
					if (`pass' == 1) {
					
						mat new_ages[`j',`i'+1+`if_female'] = `max' - `min' + 1
						local current_agr = `max' - `min' + 1
						di in yellow "min: `min' | max: `max'  -> years = `current_agr'" _c
						
						preserve
						use if iso3 == "`iso3'" & year == `year' using `shape', clear
						drop if age_start_split > `end' | age_end_split < `start'
						mean shp [pw=mean_pop]
						matrix mean_matrix = e(b)
						local average = mean_matrix[1,1]
						drop if age != `min' | sex != `sex'
						local current_age = shp 
						local correction_factor = `current_age' / `average'
						restore
						
						local new_mean = exp_mean[`j'] * `correction_factor' 
						mat new_means[`j',`i'+1+`if_female'] = `new_mean'
						di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
			
					}
					
					if (`start' >= `min' & `start' <= `max' & `pass' == 0) { 
					
						di in yellow "start: `start' /// " _c
						
						if `end'<=`max' { 
						
							mat new_ages[`j',`i'+1+`if_female'] = `end' - `start' + 1
							local pass 0
							local current_agr = `end' - `start' + 1
							di in yellow "end: `end' -> years = `current_agr'" 
							
							preserve
							use if iso3 == "`iso3'" & year == `year' using `shape', clear
							drop if age_start_split > `end' | age_end_split < `start'
							mean shp [pw=mean_pop]
							matrix mean_matrix = e(b)
							local average = mean_matrix[1,1]
							drop if age != `min' | sex != `sex'
							local current_age = shp 
							local correction_factor = `current_age' / `average'
							restore
							
							local new_mean = exp_mean[`j'] * `correction_factor' 
							mat new_means[`j',`i'+1+`if_female'] = `new_mean'
							di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"
							
						}
						
						if (`end' >= `max' & `start' >= `min') {
						
							mat new_ages[`j',`i'+1+`if_female'] = `max' - `start' + 1
							local pass 1
							local current_agr = `max' - `start' + 1
							di in yellow "min: `min' | max: `max'  -> years = `current_agr'" _c
							
							preserve
							use if iso3 == "`iso3'" & year == `year' using `shape', clear
							drop if age_start_split > `end' | age_end_split < `start'
							mean shp [pw=mean_pop]
							matrix mean_matrix = e(b)
							local average = mean_matrix[1,1]
							drop if age != `min' | sex != `sex'
							local current_age = shp 
							local correction_factor = `current_age' / `average'
							restore
							
							local new_mean = exp_mean[`j'] * `correction_factor' 
							mat new_means[`j',`i'+1+`if_female'] = `new_mean'
							di in red "age splitting resulted in correction factor of `correction_factor', this adjusted the mean from " exp_mean[`j'] " to `new_mean'"							
						
						}
						
						else local pass 1
						
					}

					local i=`i'+1
				
				}
				
		}	
		
	}
	
	svmat new_ages,names(agegr)
	svmat new_means,names(exp_mean_new)
	drop agegr1 exp_mean_new1
	reshape long agegr exp_mean_new, i( seri ) j( age )
	drop if agegr <= 0  | agegr == . // drop any age groups that don't actually have any years contributed to them
	rename age age_code
	
	// Merge on the age codebook to replace age start and age end with their split value
		merge m:1 age_code using `age_sex_codebook', keep(mat) nogen
		
	// Temporary commands to make this easier to look at during my exploratory analysis
		drop acause grouping healthstate study_status page_num table_num source_type data_type parameter_type orig* notes case*
		drop ageend agestart
		order seri age* iso3 sex year* exp* 
		

		replace agegr = (age_end_split - age_start_split) if age_end_split == .0099 | age_end_split == .099 | age_end_split == .99
		
	// Replace the old age groups with the new split ones (keep on the old age groups for reference)
		foreach var of varlist age_start age_end {
		
			rename `var' `var'_orig
			rename `var'_split `var'
			
		}
		
	// Replace sexes with new split sexes
		rename sex sex_orig
		rename sex_split sex

	// Tempfile and save to prep for appending both datasets at the end
		tempfile age_sex_split_complete
		save `age_sex_split_complete', replace

}

** **************************************************************************
** COMPILE DATASETS AND SAVE
** **************************************************************************	

if (`age_split' == 1 & `age_sex_split' == 1) {

// Append both the age split and age/sex split datasets
	use `age_split_complete', clear
	append using `age_sex_split_complete'
	
// switch back to iso3_child to use subnational values - see line 184: iso3 parent as iso3 since we don't have a shape for subnationa
	rename  iso3 iso3_parent 	
	rename  iso3_child iso3


// Rename variables to replace the old means with the age-split ones (keep on the old mean for reference)
	rename exp_mean mean_orig
	rename exp_mean_new mean

// Cleanup
	rename agegr years_contributed
	drop seri age age_code year
	order *orig years_contributed, last
	order iso3 iso3_display year_start year_end sex age_start age_end
	gsort iso3 year_start sex age_start
	
// Output results to feed into ST-GPR
	save "`temp_dir'/`iso3'_gbd2013_lead_exp_split.dta", replace
	
}

if (`age_split' == 0 & `age_sex_split' == 1) {

// Use the age/sex split dataset
	use `age_sex_split_complete', clear
	
// switch back to iso3_child to use subnational values - see line 184: iso3 parent as iso3 since we don't have a shape for subnational
	rename  iso3 iso3_parent 	
	rename  iso3_child iso3


// Rename variables to replace the old means with the age-split ones (keep on the old mean for reference)
	rename exp_mean mean_orig
	rename exp_mean_new mean

// Cleanup
	rename agegr years_contributed
	drop seri age age_code year
	order *orig years_contributed, last
	order iso3 iso3_display year_start year_end sex age_start age_end
	gsort iso3 year_start sex age_start
	
// Output results to feed into ST-GPR
	save "`temp_dir'/`iso3'_gbd2013_lead_exp_split.dta", replace
	
}

if (`age_split' == 1 & `age_sex_split' == 0) {

// Use the age split dataset
	use `age_split_complete', clear
	
// switch back to iso3_child to use subnational values - see line 184: iso3 parent as iso3 since we don't have a shape for subnational
	rename  iso3 iso3_parent 	
	rename  iso3_child iso3


// Rename variables to replace the old means with the age-split ones (keep on the old mean for reference)
	rename exp_mean mean_orig
	rename exp_mean_new mean

// Cleanup
	rename agegr years_contributed
	drop seri age age_code year
	order *orig years_contributed, last
	order iso3 iso3_display year_start year_end sex age_start age_end
	gsort iso3 year_start sex age_start
	
// Output results to feed into ST-GPR
	save "`temp_dir'/`iso3'_gbd2013_lead_exp_split.dta", replace
	
}

log close
