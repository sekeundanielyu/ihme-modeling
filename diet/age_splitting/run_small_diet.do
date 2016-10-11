// Clear memory and set memory and variable limits
	clear all
	macro drop _all
	set maxvar 32000
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}

	
//get isos
	quiet run "$j/WORK/10_gbd/00_library/functions/create_connection_string.ado"
	create_connection_string, server("modeling-epi-db") database("shared")
	local conn_string = r(conn_string)
	odbc load, exec("SELECT * FROM shared.location_hierarchy_history") `conn_string' clear
	keep if end_date==. & location_set_id==9 //most recent locations covariate set for countries we estimate for that are most detailed subnational
	keep if is_estimate==1
	//keep the maximumed version
	qui sum location_set_version_id
	keep if location_set_version_id==`r(max)'
	gen iso3 = ihme_loc_id
	tempfile full_iso
	save `full_iso', replace
	

	
 // import data
	use `diet_data', clear

	local risk_factors diet_fish diet_grains diet_legumes diet_milk diet_nuts diet_redmeat diet_transfat diet_veg diet_fruit diet_fiber diet_pufa diet_calcium diet_satfat

	cap drop developed level 
	merge m:1 location_id using `full_iso', keep(3) nogen assert(2 3) keepusing(developed level)
	
	//only work with national data
	keep if level==3
	
	destring develop, replace
	
	tempfile data
	save `data', replace
		
foreach risk_factor in `risk_factors' {
	local develop 3
		di in red "`risk_factor' | develop `develop'"
		use `data', clear
		
		keep if ihme_risk == "`risk_factor'"
		// drop fao data
		drop if svy=="FAO" | svy == "PHVO"
		// drop other excluded data
		drop if data_status == "Exclude"
		
		save "`output'/`risk_factor'_d`develop'_age_trend_dataset.dta", replace
		
		
		local project 			"`risk_factor'_d`develop'_age_trend2" 
		local datafile 			"`output'/`risk_factor'_d`develop'_age_trend_dataset.dta" 
		local sample_interval	10
		local num_sample		2000
		global proportion 1
		local midmesh 0 1 3 10 20 40 60

		local prjfolder		"`output'/`project'"
		global prjfolder 	"`prjfolder'"
		global datafile		`datafile'
		
		
		cap mkdir "`prjfolder'"
			
		use "$datafile", clear
		
		// drop region as it will be used for a different value in Dismod ODE
			cap drop region	
			if $proportion == 1 replace parameter_type = "incidence"

			rename nid nid_old
			encode svy, gen(nid)

		gen meas_value = mean
		gen meas_stdev = standard_error
		gen x_sex = 0 if sex == "Both"
		replace x_sex = .5 if sex == "Male"
		replace x_sex = -.5 if sex == "Female"
		gen age_lower = age_start
		gen age_upper = age_end
		gen time_lower = year_start
		gen time_upper = year_end
		gen super = "none"
		gen region = "none"
		gen subreg = iso3 + "_" + string(nid)

		tostring meas_stdev, replace force
		cap gen integrand = parameter_type

				cap gen x_sex = 0
				cap gen x_ones = 1
				local o = _N
				local age_s 0
				di `o'
		qui forval i = 1/3 {
				local o = `o' + 1
				set obs `o'
				replace integrand = "mtall" in `o'
				replace super = "none" in `o'
				replace region = "none" in `o'
				replace subreg = "none" in `o'
				replace time_lower = 2000 in `o'
				replace time_upper = 2000 in `o'
				replace age_lower = `age_s' in `o'
				local age_s = `age_s' + 20
				replace age_upper = `age_s' in `o'
				replace x_sex = 0 in `o'
				replace x_ones = 0 in `o'
				replace meas_value = .01 in `o'
				replace meas_stdev = "inf" in `o'
			}	
				qui sum age_upper
				local maxage = r(max)
				if `maxage' > 90 local maxage 100
				replace age_upper = `maxage' in `o'

				cap keep citation nid iso3 super region subreg integrand time_* age_* meas_* x_* 
		outsheet using "`prjfolder'/data_in.csv", comma replace



			local studycovs
			foreach var of varlist x_* {
							local studycovs "`studycovs' `var'"
			}
			qui sum age_upper
			global mesh `midmesh' `maxage'
			global sample_interval `sample_interval'
			global num_sample `num_sample'
			global studycovs `studycovs'
			qui		do "`codefolder'/make_diet_effect_ins.do"
			qui		do "`codefolder'/make_diet_rate_ins.do"
			qui		do "`codefolder'/make_value_in.do"
			qui		do "`codefolder'/make_plain_in.do"
			
			
		insheet using "$j/temp/dismod_ode/pred_in.csv", comma clear case
			if $proportion == 1 keep if integrand == "incidence"
			foreach var of local studycovs {
					cap gen `var' = 0
			}
		qui {
			gen age = age_lower
			keep if  mod(age_lower,5) == 0  | age_lower <4
			drop if age_lower>80
			replace age_upper = 0.01 if age == 0
			replace age_lower = 0.01 if age == 1
			replace age_upper = 0.1 if age == 1
			replace age_lower = 0.1 if age == 2
			replace age_upper = 1 if age == 2
			replace age_lower = 1 if age == 3
			replace age_upper = 5 if age == 3
			replace age_upper = age_lower + 5 if age_upper >=5
			replace age_upper = 100 if age_upper == 85
			replace age = age_lower
		}
		outsheet using "`prjfolder'/pred_in.csv", comma replace
			cd "`prjfolder'"
			
			! /usr/local/dismod_ode/bin/sample_post.py
			
		insheet using "`prjfolder'/sample_out.csv", comma case clear
			drop if _n < `num_sample' - 1000 + 1
			replace index = _n - 1
		outsheet using "`prjfolder'/sample_out.csv", comma replace

		insheet  name value using "`prjfolder'/value_in.csv", comma case clear
			drop if _n == 1
			replace value = "1000" if name == "num_sample"
		outsheet using "`prjfolder'/value_tmp.csv", comma replace
		di "1"
			! /usr/local/dismod_ode/bin/stat_post.py scale_beta=false
		di "2"
			! /usr/local/dismod_ode/bin/data_pred data_in.csv value_tmp.csv plain_tmp.csv rate_tmp.csv effect_tmp.csv sample_out.csv data_pred.csv
		di "3"	
			! /usr/local/dismod_ode/bin/data_pred pred_in.csv value_tmp.csv plain_tmp.csv rate_tmp.csv effect_tmp.csv sample_out.csv pred_out.csv
			sleep 2000
		di "4"	
			! /usr/local/dismod_ode/bin/predict_post.py 10
		di "5"
			! /usr/local/dismod_ode/bin/data_pred model_in.csv value_tmp.csv plain_tmp.csv rate_tmp.csv effect_tmp.csv sample_out.csv model_out.csv
			sleep 2000
		di "6"
			! /usr/local/dismod_ode/bin/plot_post.py  "`project'"
		di "7"	

}

 