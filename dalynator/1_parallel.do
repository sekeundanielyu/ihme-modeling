// Purpose:	Calculate DALYs using CodCorrect/COMO/PAF inputs and upload to gbd database for visualization in GBD Compare and querying for publications
// Code:		do "/home/j/WORK/10_gbd/01_dalynator/01_code/prod/1_parallel.do"
noi di c(current_time) + ": START"
qui {
// TEST LOCALS
	if "`1'" == "" {
		// GBD round
		local gbd_round_id 3
		// dev/prod
			local envir prod
		// dalynator version
			local gbd dev
		// cod/epi/rei_id version (acceptable combinations: cod, cod and epi, cod and risk, or all 3)
			local cod 41
			local epi 96
			local risk metab_bmi
		// regional scalars version
			local scalars 12
		// memory
			local mem 20
		// type
			local loclvl 3
		// location_id
			local location_id 101
		// year_id
			local year_id 1990
		// shock version folder
			local shock_version 5
		// cause set id
			local cause_set_id 3 // GBD reporting
		// Children locations
			local children "."

	}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// PREP STATA (SHOULDN'T NEED TO MODIFY PAST THIS POINT)
	
	// master locals (overrides test above if submitted from master)
		if "`1'" != "" {
			local gbd_round_id `1'
			local envir `2'
			local gbd `3'
			local cod `4'
			local epi `5'
			local risk `6'
			local scalars `7'
			local mem `8'
			local loclvl `9'
			local location_id `10'
			local year_id `11'
			local shock_version `12'
			local cause_set_id `13'
			local children `14'
		}
		
	// memory (leave some breathing room for scheduler)
		clear all
		set more off
		set maxvar 32000
	// directories
		if c(os) == "Unix" {
			global j "/home/j/"
			set odbcmgr unixodbc
		}
		else if c(os) == "Windows" {
			global j "J:"
		}
		adopath + "$j/WORK/10_gbd/00_library/functions"
		local cod_dir "/share/central_comp/codcorrect/`cod'/draws"
		local epi_dir "/ihme/centralcomp/como/`epi'/draws/cause/total_csvs"
		local risk_dir "/share/central_comp/pafs/Rose/`risk'"
		local code_dir "$j/WORK/10_gbd/01_dalynator/01_code/`envir'"
		local in_dir "$j/WORK/10_gbd/01_dalynator/02_inputs"
		local out_dir "$j/WORK/10_gbd/01_dalynator/03_results/`gbd'"
		local tmp_dir "/share/central_comp/dalynator/`gbd'"
		local pred_ex_dir "/share/gbd/WORK/02_mortality/03_models/5_lifetables/products/"
		local shock_dir "/share/central_comp/shock_aggregator/`shock_version'/draws/"

	// define epi vars
	if inlist(`year_id',1990,1995,2000,2005,2010,2015) {
		foreach metric in yld daly {
			local `metric' ""
			local `metric's ""
			if "`epi'" != "0" local `metric' "`metric'"
			if "`epi'" != "0" local `metric's "`metric'*"
		}
		local imp ""
		local imps ""
	}
		local sex_ids "1 2"
	
		capture log close
		log using "`tmp_dir'/logs/log_loclvl`loclvl'_`location_id'_`year_id'.smcl", replace

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// MOST DETAILED LEVEL OF LOCATION (ie no children locations)
if "`children'" == "." {
	
	// *********************************************************************************************************************************************************************
	// *********************************************************************************************************************************************************************
	// COD
		if "`cod'" != "0" {
		noi di c(current_time) + ": prep cod"

		// load deaths
		// saved by location year
				use "`cod_dir'/death_`location_id'_`year_id'.dta", clear
				cap renpfix death draw
				keep age_group_id sex_id cause_id draw*
				gen location_id = `location_id'
				gen year_id = `year_id'

				foreach var of varlist draw* {
					qui replace `var' = 0 if `var' == .
				}
			
				// age_group_id/sex_id restrictions
				// we want to apply restrictions first then add shocks - we don't restrict shocks
					merge m:1 cause_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, keep(1 3) nogen keepusing(male female yll_age_group_id_start yll_age_group_id_end)
					drop if age_group_id < yll_age_group_id_start | age_group_id > yll_age_group_id_end | (sex_id == 1 & male == 0) | (sex_id == 2 & female == 0)
					drop male female yll_age_group_id_start yll_age_group_id_end


			tempfile no_shocks_`location_id'_`year_id'
			save `no_shocks_`location_id'_`year_id'', replace

		** append shocks - note they are aggregated
			insheet using "`shock_dir'/shocks_`location_id'_`year_id'.csv", comma double clear
			append using `no_shocks_`location_id'_`year_id''
			fastcollapse draw*, type(sum) by(location_id year_id age_group_id sex_id cause_id)
	
				renpfix draw death
						
				// Maternal custom aggregation
				// Capture - this broke Vermont 2005 where there were no maternal causes of death coming from CoDCorrect
				cap fastcollapse death* if inlist(cause_id,369,367,370,371,368,379), type(sum) by(location_id year_id age_group_id sex_id) append flag(dup)
				cap replace cause_id = 930 if dup==1 // maternal direct
				cap drop dup

				cap fastcollapse death* if inlist(cause_id,375,741), type(sum) by(location_id year_id age_group_id sex_id) append flag(dup)
				cap replace cause_id = 931 if dup==1 // maternal indirect + HIV
				cap drop dup

				cap fastcollapse death* if inlist(cause_id,931,930), type(sum) by(location_id year_id age_group_id sex_id) append flag(dup)
				cap replace cause_id = 929 if dup==1 // maternal indirect and direct
				cap drop dup

				// calculate YLLs
					merge m:1 location_id year_id age_group_id sex_id using "`pred_ex_dir'/yll_exp.dta", keep(1 3) nogen
					foreach i of numlist 0/999 {
						gen double yll_`i' = death_`i' * pred_ex
					}

				// save
					keep location_id year_id age_group_id sex_id cause_id death_* yll_*
					compress
					tempfile prepped
					save `prepped', replace
			}

	// *********************************************************************************************************************************************************************
	// *********************************************************************************************************************************************************************
	// EPI
		if "`epi'" != "0" & inlist(`year_id',1990,1995,2000,2005,2010,2015) {
		noi di c(current_time) + ": prep epi"
			** residuals now included in COMO
			local n = 0
			foreach sex_id of local sex_ids {
				import delimited using "`epi_dir'/3_`location_id'_`year_id'_`sex_id'.csv", asdouble varname(1) clear
				merge m:1 location_id year_id age_group_id sex_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/envelope_`gbd'.dta, keep(3) nogen keepusing(pop_scaled)
				forvalues i = 0/999 {
					replace draw_`i' = draw_`i' * pop_scaled
				}
				
				renpfix draw yld
				keep location_id year_id age_group_id sex_id cause_id yld*
				compress
				local n = `n' + 1
				tempfile `n'
				save ``n'', replace
			}
			clear
			forvalues i = 1/`n' {
				append using ``i''
			}


			foreach var of varlist yld* {
				qui replace `var' = 0 if `var' == .
			}

			keep location_id year_id age_group_id sex_id cause_id yld_*
			
			
	// *********************************************************************************************************************************************************************
	// *********************************************************************************************************************************************************************
	// COMBINE COD AND EPI

		// combine cod/epi
			noi di c(current_time) + ": combine cod/epi"
			merge 1:1 location_id year_id age_group_id sex_id cause_id using `prepped', nogen
			foreach var of varlist death* yll* `ylds' {
				qui replace `var' = 0 if `var' == .
			}
			
			compress
			save `prepped', replace			
	}

	// *********************************************************************************************************************************************************************
	// *********************************************************************************************************************************************************************
	// rei_id
		if "`risk'" != "0" & inlist(`year_id',1990,1995,2000,2005,2010,2015) {
			noi di c(current_time) + ": prep risks"
			
			// Read PAFs
			use "`risk_dir'/`location_id'_`year_id'.dta", clear

			if "`epi'" == "0" {
			drop paf_yld*
			}

			// merge on epi/cod data
			merge m:1 location_id year_id age_group_id sex_id cause_id using `prepped', keep(3) nogen
			
			// Calculate attributable burden
			foreach type in "death" "yll" {
				if "`type'" == "death" local paf_var = "yll"
				else local paf_var = "`type'"
				
				forvalues draw = 0/999 {
					quietly replace `type'_`draw' = `type'_`draw' * paf_`paf_var'_`draw'
					quietly replace `type'_`draw' = 0 if `type'_`draw' == .
				}
			}
			
		if "`epi'" != "0" {
				forvalues draw = 0/999 {
					quietly replace yld_`draw' = yld_`draw' * paf_yld_`draw'
					quietly replace yld_`draw' = 0 if yld_`draw' == .
				}

		}				

			drop paf_*

			foreach var of varlist death* yll* `ylds' {
				qui replace `var' = 0 if `var' == .
			}

			// Aggregate up cause hierarchy
			merge m:1 cause_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, keep(1 3) keepusing(cause_id_dup most_detailed) nogen
			drop cause_id
			foreach i of numlist 4 3 2 1 {
				merge m:1 cause_id_dup using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, keep(1 3) keepusing(cause_id_dup level parent_id) nogen
				quietly count if level == `i'
				if r(N) == 0 continue
				fastcollapse death* yll* `ylds' if level == `i', type(sum) by(location_id year_id age_group_id sex_id parent_id rei_id) append flag(dup)
				replace cause_id_dup = parent_id if dup == 1
				drop dup level parent_id
			}
			merge m:1 cause_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, keep(1 3) keepusing(cause_id) nogen

		// *********************************************************************************************************************************************************************
		// *********************************************************************************************************************************************************************
		// COMBINE COD, EPI, RISK

			noi di c(current_time) + ": combine cod/epi/risk"
			// Append onto epi cod
			append using `prepped' 
			
			foreach var of varlist death* yll* `ylds' {
				qui replace `var' = 0 if `var' == .
			}
			
			compress
			save `prepped', replace
		}

}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// AGGREGATE LEVELS OF LOCATION
if "`children'" != "." {

	// append results. Collapse after each country to save memory. This is less computationally
	// efficient, but allows us to use way fewer slots. I think it's only about ~50% slower after some testing.
		clear
		local count 0
		foreach geo of local children {
			noi di c(current_time) + ": appending `geo'"
			append using "`tmp_dir'/temp/agg_`geo'_`year_id'.dta"
			replace location_id = `location_id'
			if `count' > 0 fastcollapse death* yll* `ylds' `imps', type(sum) by(location_id year_id age_group_id sex_id cause_id rei_id)
			local count 1
		}
		cap gen rei_id = .
		keep location_id year_id age_group_id sex_id cause_id rei_id death_* yll_* `ylds' `imps'

** We only want to work with the shocks and scaling if we indeed have regional scalars
** IE we can avoid this step for global etc.

capture confirm file "`in_dir'/region_scalars/`scalars'/`location_id'_`year_id'_scaling_pop.dta"
if _rc == 0 {

	// before scaling subtract out shocks/imported cases 
		tempfile with_shock_`location_id'_`year_id'
		save `with_shock_`location_id'_`year_id'', replace

		noi di c(current_time) + ": Subtract shocks and imported cases before applying regional scalars"
		insheet using "`shock_dir'/shocks_`location_id'_`year_id'.csv", comma double clear
		gen rei_id = .
		// currently, some shocks propogate restrictions (ie nutrition deficiencies in early and late neonates _merge==1)
		// we decided to not apply restrictions to shocsk - make sure we keep merged results and using data
		merge 1:m location_id year_id age_group_id sex_id cause_id rei_id using `with_shock_`location_id'_`year_id'', assert(2 3) keep(2 3)

		forvalues i = 0/999 {
			replace death_`i' = death_`i' - draw_`i' if _merge==3
			replace yll_`i' = yll_`i' - draw_`i' if _merge==3
		}
		drop _merge draw*


	// scale regions (If we're at a location with scalars)
		capture confirm file "`in_dir'/region_scalars/`scalars'/`location_id'_`year_id'_scaling_pop.dta"
		if _rc == 0 {
			noi di c(current_time) + ": Region scalars"
			merge m:1 location_id year_id age_group_id sex_id using "`in_dir'/region_scalars/`scalars'/`location_id'_`year_id'_scaling_pop.dta", keep(1 3) nogen
			replace scaling_factor = 1 if scaling_factor == .
			foreach var of varlist death* yll* `ylds' `imps' {
				replace `var' = `var' * scaling_factor
			}
			drop scaling_factor
		}

	// now add back on shocks and imported cases
		tempfile after_scale_`location_id'_`year_id'
		save `after_scale_`location_id'_`year_id'', replace

		noi di c(current_time) + ": Add shocks and imported cases back on after applying scalars"
		insheet using "`shock_dir'/shocks_`location_id'_`year_id'.csv", comma double clear
		gen rei_id = .
		merge 1:m location_id year_id age_group_id sex_id cause_id rei_id using `after_scale_`location_id'_`year_id'', keep(2 3)
		
		forvalues i = 0/999 {
			replace death_`i' = death_`i' + draw_`i' if _merge==3
			replace yll_`i' = yll_`i' + draw_`i' if _merge==3
		}
		drop _merge draw*
	} // end confirm shocks loop 
} // end children loop

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// ALL
	// save draws for aggregation
		cap gen rei_id = . // Might not rei_id var if we haven't run rei_id
		keep location_id year_id age_group_id sex_id cause_id rei_id death_* yll_* `ylds' `imps'
		order location_id year_id age_group_id sex_id cause_id rei_id death_* yll_* `ylds' `imps'
		noi di c(current_time) + ": save draws for aggregation"
		compress
	cap confirm file "`tmp_dir'/checks/loclvl`loclvl'_agg_`location_id'_`year_id'.txt"
	if _rc {	
		saveold "`tmp_dir'/temp/agg_`location_id'_`year_id'.dta", replace
		file open finish using "`tmp_dir'/checks/loclvl`loclvl'_agg_`location_id'_`year_id'.txt", write replace
		file close finish
	}
		
		noi di c(current_time) + ": Fill in draws with aggregates"
		drop if age_group_id > 21
	// create all age_group_ids group
		noi di c(current_time) + ": all age_group_ids"	
		fastcollapse death* yll* `ylds' `imps' if age_group_id <= 21, type(sum) by(location_id year_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = 22 if dup == 1
		drop dup
		
	// create aggregate age_group_id groups
		noi di c(current_time) + ": agg age_group_ids"
		gen new_age_group_id = 1 if age_group_id < 6 & age_group_id >=2
		replace new_age_group_id = 23 if age_group_id >= 6 & age_group_id < 8
		replace new_age_group_id = 24 if age_group_id >= 8 & age_group_id < 15
		replace new_age_group_id = 25 if age_group_id >= 15 & age_group_id < 19
		replace new_age_group_id = 26 if age_group_id >= 19 & age_group_id <= 21
		fastcollapse death* yll* `ylds' `imps' if new_age_group_id != ., type(sum) by(location_id year_id new_age_group_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = new_age_group_id if dup == 1
		drop new_age_group_id dup
		
	// create custom agg age_group_id groups
		noi di c(current_time) + ": agg additional age_group_ids"
		gen new_age_group_id = 159 if age_group_id >= 7 & age_group_id < 10
		fastcollapse death* yll* `ylds' `imps' if new_age_group_id != ., type(sum) by(location_id year_id new_age_group_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = new_age_group_id if dup == 1
		drop new_age_group_id dup
		
		gen new_age_group_id = 158 if age_group_id < 9 & age_group_id >= 2
		fastcollapse death* yll* `ylds' `imps' if new_age_group_id != ., type(sum) by(location_id year_id new_age_group_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = new_age_group_id if dup == 1
		drop new_age_group_id dup

		gen new_age_group_id = 163 if age_group_id >= 9 & age_group_id < 18
		fastcollapse death* yll* `ylds' `imps' if new_age_group_id != ., type(sum) by(location_id year_id new_age_group_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = new_age_group_id if dup == 1
		drop new_age_group_id dup

		// custom age group for maternal 10-54
		gen new_age_group_id = 169 if age_group_id >= 7 & age_group_id < 16
		fastcollapse death* yll* `ylds' `imps' if new_age_group_id != ., type(sum) by(location_id year_id new_age_group_id sex_id cause_id rei_id) append flag(dup)
		replace age_group_id = new_age_group_id if dup == 1
		drop new_age_group_id dup
		
	// create both sex group
		noi di c(current_time) + ": both sexes"
		fastcollapse death* yll* `ylds' `imps', type(sum) by(location_id year_id age_group_id cause_id rei_id) append flag(dup)
		replace sex_id = 3 if dup == 1
		drop dup
		
	// create age-standardized group
		noi di c(current_time) + ": age standardize"
		expand 2 if age_group_id <= 21, gen(dup)
		merge m:1 age_group_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/age_W_`gbd'.dta, keep(1 3) nogen
		merge m:1 location_id year_id age_group_id sex_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/envelope_`gbd'.dta, keep(1 3) nogen keepusing(pop_scaled)
		foreach var of varlist death* yll* `ylds' `imps' {
			qui replace `var' = `var' * age_group_weight / pop_scaled if dup == 1
		}
		replace age_group_id = 27 if dup == 1
		drop dup
		fastcollapse death* yll* `ylds' `imps' if age_group_id == 27, type(sum) by(location_id year_id age_group_id sex_id cause_id rei_id) append flag(dup)
		drop if dup == 0 & age_group_id == 27
		drop dup
				
		// calculate DALYs
		if inlist(`year_id',1990,1995,2000,2005,2010,2015) & "`epi'" != "0" {
				noi di c(current_time) + ": calculate DALYs"
					foreach i of numlist 0/999 {
						qui gen double daly_`i' = yll_`i' + yld_`i'
					}
			}
		
		foreach var of var death* yll* `ylds' `dalys' `imps' {
			qui replace `var' = 0 if `var'==.
		}

	// Calculate CFs and PAFs (use MATA to avoid tempfiles)
	merge m:1 cause_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/causes_`gbd'.dta, keep(1 3) keepusing(cause_id level) nogen
	keep location_id year_id age_group_id sex_id cause_id rei_id level death_* yll_* `ylds' `dalys'

	gen denominator = .
	if "`cod'" != "0" {
		noi di c(current_time) + ": calculate CFs"
		replace denominator = (level == 0) // level ==0 is always "all causes"
		drop level
		fastfraction death* yll* `ylds' `dalys', by(location_id year_id age_group_id sex_id rei_id) denominator(denominator) prefix(cf_)
	}
	
	if "`risk'" != "0" & inlist(`year_id',1990,1995,2000,2005,2010,2015) {
		noi di c(current_time) + ": calculate PAFs"
		// Need to generate PAFs side by side to CFs 
		replace denominator = (rei_id == .)
		fastfraction death* yll* `ylds' `dalys', by(location_id year_id age_group_id sex_id cause_id) denominator(denominator) prefix(paf_) 
		
		// Move PAF vars to CFs
		if "`cod'" != "0" {
			quietly foreach var of var death* yll* `ylds' `dalys' { 
				replace cf_`var' = paf_`var' if rei_id != .
			}
		
			drop paf_*
		}
		else {
			rename paf_* cf_*
		}
	}
	drop denominator

	// save final draws
		noi di c(current_time) + ": save final draws"
		keep location_id year_id age_group_id sex_id cause_id rei_id death_* yll_* `ylds' `imps' `dalys' cf*
		order location_id year_id age_group_id sex_id cause_id rei_id death_* yll_* `ylds' `imps' `dalys' cf*
		compress
	cap confirm file "`tmp_dir'/checks/loclvl`loclvl'_draws_`location_id'_`year_id'.txt"
	if _rc {
		saveold "`tmp_dir'/draws/draws_`location_id'_`year_id'.dta", replace
		file open finish using "`tmp_dir'/checks/loclvl`loclvl'_draws_`location_id'_`year_id'.txt", write replace
		file close finish
	}
	// calculate percent change of 1990 to 2015
		if `year_id' == 2015 {
			
			tempfile temp
			save `temp', replace
			
			noi di c(current_time) + ": waiting for 1990 draws for percent change"
			
			local i = 0
			while `i' == 0 {
				capture confirm file "`tmp_dir'/checks/loclvl`loclvl'_draws_`location_id'_1990.txt"
				if (! _rc) local i = 1
				if (`i' == 0) sleep 60000
			}
			
			noi di c(current_time) + ": calculate percent change 1990 to 2015"
			
			foreach metric in death yll `yld' `daly' {
				renpfix `metric' end_`metric'
				renpfix cf_`metric' end_cf_`metric'
			}
			
			foreach metric in `imp' {
				renpfix `metric' end_`metric'
			}
			
			foreach metric in death yll `yld' `daly' {
				fastrowmean end_`metric'*, mean_var_name(y_`metric')
				fastrowmean end_cf_`metric'*, mean_var_name(y_cf_`metric')
			}

			merge 1:1 location_id age_group_id sex_id cause_id rei_id using "`tmp_dir'/draws/draws_`location_id'_1990.dta", keep(3) nogen

		foreach var of var death* yll* `ylds' `dalys' `imps' {
		qui replace `var' = 0 if `var'==.
		}

			foreach metric in death yll `yld' `daly' {
				fastrowmean `metric'*, mean_var_name(x_`metric')
				fastrowmean cf_`metric'*, mean_var_name(x_cf_`metric')
			}

		** use MATA to calc % change
		
			foreach metric in death yll `yld' `imp' `daly' {
			
					unab vars_end : end_`metric'*
					mata end_`metric' = .
					mata end_`metric' = st_data(., st_varindex(tokens("`vars_end'")))
					mata end_`metric' = editmissing(end_`metric',0)

					unab vars : `metric'*
					mata `metric' = .
					mata `metric' = st_data(., st_varindex(tokens("`vars'")))
					mata `metric' = editmissing(`metric',0) 

					mata roc_`metric' = (end_`metric' :- `metric') :/ `metric'
					drop `metric'*
					mata roc_`metric' = editmissing(roc_`metric',0) 
					mata st_store(.,st_addvar("double",tokens("`vars'")), roc_`metric')
				
			}
			
			** cf
			
			foreach metric in death yll `yld' `daly' {
			
					unab vars_cf_end : end_cf_`metric'*
					mata end_cf_`metric' = st_data(., st_varindex(tokens("`vars_cf_end'")))
					mata end_cf_`metric' = editmissing(end_cf_`metric',0)
					
					unab vars_cf : cf_`metric'*
					mata cf_`metric' = st_data(., st_varindex(tokens("`vars_cf'")))
					mata cf_`metric' = editmissing(cf_`metric',0)
					
					mata roc_cf_`metric' = (end_cf_`metric' :- cf_`metric') :/ cf_`metric'
					mata roc_cf_`metric' = editmissing(roc_cf_`metric',0) 
					drop cf_`metric'*
					mata st_store(.,st_addvar("double",tokens("`vars_cf'")), roc_cf_`metric')	
					
			}

			foreach metric in death yll `yld' `daly' {
				gen double change_`metric' = (y_`metric' - x_`metric')/x_`metric'
				gen double change_cf_`metric' = (y_cf_`metric' - x_cf_`metric')/x_cf_`metric'
			}

			drop end*

			replace year_id = 9999
			tempfile roc1
			save `roc1', replace
			
		} // end 1990-2015 PC change loop


		if `year_id' == 2015 {
			
			use `temp', clear
			
			noi di c(current_time) + ": waiting for 2005 draws for percent change"
			
			local i = 0
			while `i' == 0 {
				capture confirm file "`tmp_dir'/checks/loclvl`loclvl'_draws_`location_id'_2005.txt"
				if (! _rc) local i = 1
				if (`i' == 0) sleep 60000
			}
			
			noi di c(current_time) + ": calculate percent change 2005 to 2015"
			
			foreach metric in death yll `yld' `daly' {
				renpfix `metric' end_`metric'
				renpfix cf_`metric' end_cf_`metric'
			}
			
			foreach metric in `imp' {
				renpfix `metric' end_`metric'
			}

			foreach metric in death yll `yld' `daly' {
				fastrowmean end_`metric'*, mean_var_name(y_`metric')
				fastrowmean end_cf_`metric'*, mean_var_name(y_cf_`metric')
			}
			
			merge 1:1 location_id age_group_id sex_id cause_id rei_id using "`tmp_dir'/draws/draws_`location_id'_2005.dta", keep(3) nogen

		foreach var of var death* yll* `ylds' `dalys' `imps' {
		qui replace `var' = 0 if `var'==.
		}

			foreach metric in death yll `yld' `daly' {
				fastrowmean `metric'*, mean_var_name(x_`metric')
				fastrowmean cf_`metric'*, mean_var_name(x_cf_`metric')
			}

			foreach metric in death yll `yld' `imp' `daly' {
			
					unab vars_end : end_`metric'*
					mata end_`metric' = .
					mata end_`metric' = st_data(., st_varindex(tokens("`vars_end'")))
					mata end_`metric' = editmissing(end_`metric',0)

					unab vars : `metric'*
					mata `metric' = .
					mata `metric' = st_data(., st_varindex(tokens("`vars'")))
					mata `metric' = editmissing(`metric',0) 

					mata roc_`metric' = (end_`metric' :- `metric') :/ `metric'
					drop `metric'*
					mata roc_`metric' = editmissing(roc_`metric',0) 
					mata st_store(.,st_addvar("double",tokens("`vars'")), roc_`metric')
				
			}
			
			** cf
			
			foreach metric in death yll `yld' `daly' {
			
					unab vars_cf_end : end_cf_`metric'*
					mata end_cf_`metric' = st_data(., st_varindex(tokens("`vars_cf_end'")))
					mata end_cf_`metric' = editmissing(end_cf_`metric',0)
					
					unab vars_cf : cf_`metric'*
					mata cf_`metric' = st_data(., st_varindex(tokens("`vars_cf'")))
					mata cf_`metric' = editmissing(cf_`metric',0)
					
					mata roc_cf_`metric' = (end_cf_`metric' :- cf_`metric') :/ cf_`metric'
					mata roc_cf_`metric' = editmissing(roc_cf_`metric',0) 
					drop cf_`metric'*
					mata st_store(.,st_addvar("double",tokens("`vars_cf'")), roc_cf_`metric')	
					
			}

			foreach metric in death yll `yld' `daly' {
				gen double change_`metric' = (y_`metric' - x_`metric')/x_`metric'
				gen double change_cf_`metric' = (y_cf_`metric' - x_cf_`metric')/x_cf_`metric'
			}

			drop end*

			replace year_id = 9100
			tempfile roc2
			save `roc2', replace
			
			append using `roc1'
			append using `temp'
		} // end 2005-2015 PC change loop

		if `year_id' == 2005 {
			
			tempfile temp
			save `temp', replace
			
			noi di c(current_time) + ": waiting for 1990 draws for percent change"
			
			local i = 0
			while `i' == 0 {
				capture confirm file "`tmp_dir'/checks/loclvl`loclvl'_draws_`location_id'_1990.txt"
				if (! _rc) local i = 1
				if (`i' == 0) sleep 60000
			}
			
			noi di c(current_time) + ": calculate percent change 1990 to 2005"
			
			foreach metric in death yll `yld' `daly' {
				renpfix `metric' end_`metric'
				renpfix cf_`metric' end_cf_`metric'
			}
			
			foreach metric in `imp' {
				renpfix `metric' end_`metric'
			}

			foreach metric in death yll `yld' `daly' {
				fastrowmean end_`metric'*, mean_var_name(y_`metric')
				fastrowmean end_cf_`metric'*, mean_var_name(y_cf_`metric')
			}
			
			merge 1:1 location_id age_group_id sex_id cause_id rei_id using "`tmp_dir'/draws/draws_`location_id'_1990.dta", keep(3) nogen

		foreach var of var death* yll* `ylds' `dalys' `imps' {
		qui replace `var' = 0 if `var'==.
		}

			foreach metric in death yll `yld' `daly' {
				fastrowmean `metric'*, mean_var_name(x_`metric')
				fastrowmean cf_`metric'*, mean_var_name(x_cf_`metric')
			}

			foreach metric in death yll `yld' `imp' `daly' {
			
					unab vars_end : end_`metric'*
					mata end_`metric' = .
					mata end_`metric' = st_data(., st_varindex(tokens("`vars_end'")))
					mata end_`metric' = editmissing(end_`metric',0)

					unab vars : `metric'*
					mata `metric' = .
					mata `metric' = st_data(., st_varindex(tokens("`vars'")))
					mata `metric' = editmissing(`metric',0) 

					mata roc_`metric' = (end_`metric' :- `metric') :/ `metric'
					drop `metric'*
					mata roc_`metric' = editmissing(roc_`metric',0) 
					mata st_store(.,st_addvar("double",tokens("`vars'")), roc_`metric')
				
			}
			
			** cf
			
			foreach metric in death yll `yld' `daly' {
			
					unab vars_cf_end : end_cf_`metric'*
					mata end_cf_`metric' = st_data(., st_varindex(tokens("`vars_cf_end'")))
					mata end_cf_`metric' = editmissing(end_cf_`metric',0)
					
					unab vars_cf : cf_`metric'*
					mata cf_`metric' = st_data(., st_varindex(tokens("`vars_cf'")))
					mata cf_`metric' = editmissing(cf_`metric',0)
					
					mata roc_cf_`metric' = (end_cf_`metric' :- cf_`metric') :/ cf_`metric'
					mata roc_cf_`metric' = editmissing(roc_cf_`metric',0) 
					drop cf_`metric'*
					mata st_store(.,st_addvar("double",tokens("`vars_cf'")), roc_cf_`metric')	
					
			}

			foreach metric in death yll `yld' `daly' {
				gen double change_`metric' = (y_`metric' - x_`metric')/x_`metric'
				gen double change_cf_`metric' = (y_cf_`metric' - x_cf_`metric')/x_cf_`metric'
			}
			
			drop end*

			replace year_id = 9101
			tempfile roc
			save `roc', replace
			append using `temp'
		} // end 1990-2005 PC change loop

clear mata
		// calculate summary
		foreach metric in death yll `yld' `imp' `daly' {
			noi di c(current_time) + ": calculate summary `metric'"
			fastrowmean `metric'*, mean_var_name(mean_`metric')
			fastpctile `metric'*, pct(2.5 97.5) names(lower_`metric' upper_`metric')

			noi di c(current_time) + ": calculate summary cf_`metric'"	
			fastrowmean cf_`metric'*, mean_var_name(mean_`metric'_cf)		
			fastpctile cf_`metric'*, pct(2.5 97.5) names(lower_`metric'_cf upper_`metric'_cf)
			
		}
		
			
	// calculate median percent change
	if `year_id' == 2015 {
		foreach metric in death yll `yld' `imp' `daly' {
			replace mean_`metric' = change_`metric' if year_id==9999
			replace mean_`metric'_cf = change_cf_`metric' if year_id==9999
			replace mean_`metric' = 0 if mean_`metric'==. & year_id==9999
			replace mean_`metric'_cf = 0 if mean_`metric'_cf==. & year_id==9999
			** 2005 - 2015
			replace mean_`metric' = change_`metric' if year_id==9100
			replace mean_`metric'_cf = change_cf_`metric' if year_id==9100
			replace mean_`metric' = 0 if mean_`metric'==. & year_id==9100
			replace mean_`metric'_cf = 0 if mean_`metric'_cf==. & year_id==9100
			drop change_`metric' change_cf_`metric'
		}
	}

	if `year_id' == 2005 {
		foreach metric in death yll `yld' `imp' `daly' {
			replace mean_`metric' = change_`metric' if year_id==9101
			replace mean_`metric'_cf = change_cf_`metric' if year_id==9101
			replace mean_`metric' = 0 if mean_`metric'==. & year_id==9101
			replace mean_`metric'_cf = 0 if mean_`metric'_cf==. & year_id==9101
			drop change_`metric' change_cf_`metric'
		}
	}

		clear mata
		
	// save summary
		noi di c(current_time) + ": save summary"
		keep location_id year_id age_group_id sex_id cause_id rei_id mean* upper* lower*
		order location_id year_id age_group_id sex_id cause_id rei_id mean* upper* lower*
		sort location_id year_id age_group_id sex_id cause_id rei_id
		compress
		save "`out_dir'/summary/summary_`location_id'_`year_id'.dta", replace

	// Prep summary for upload
		noi di c(current_time) + ": calc rates"
		merge m:1 location_id year_id age_group_id sex_id using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/envelope_`gbd'.dta, keep(1 3) nogen keepusing(pop_scaled)

		foreach var in mean_death mean_yll mean_yld mean_daly upper_death upper_yll upper_yld upper_daly lower_death lower_yll lower_yld lower_daly {
			cap gen `var'_rt = .
			cap replace `var'_rt = `var' / pop_scaled if (year_id < 9000 & age_group_id != 27)
			cap replace `var'_rt = `var' if age_group_id == 27
		}

	noi di c(current_time) + ": begin reshape for db"
		keep location_id year_id age_group_id sex_id cause_id rei_id mean* upper* lower*
		order location_id year_id age_group_id sex_id cause_id rei_id mean* upper* lower*
		sort location_id year_id age_group_id sex_id cause_id rei_id
		compress
		reshape long mean_ upper_ lower_, i(location_id year_id age_group_id sex_id cause_id rei_id) j(measure) string
	noi di c(current_time) + ": reshape done"
		gen metric = ""
			replace metric = "percent" if regexm(measure,"_cf")
			replace metric = "rate" if regexm(measure,"_rt")
			replace metric = "number" if metric == ""
		replace measure = subinstr(measure,"_cf","",.)
		replace measure = subinstr(measure,"_rt","",.)
		rename mean_ val
		rename lower_ lower
		rename upper_ upper
		drop if val == 0

		merge m:1 measure using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/measures.dta, keep(3) assert(2 3) nogen
		merge m:1 metric using $j/WORK/10_gbd/01_dalynator/02_inputs/scratch/metrics.dta, keep(3) assert(2 3) nogen

		foreach var in val lower upper {
			tostring `var', replace force format(%16.0g)
			replace `var' = "\N" if `var' == "" | `var' == "."
		}
		
		drop if val=="\N" & lower=="\N" & upper=="\N"
		replace val="0" if (upper!="\N" | lower!="\N") & val=="\N"

		// bulemia in central europe -> draws of 0 so drop for infile to db
		drop if val=="0" & upper=="0" & lower=="0"

		sort measure_id metric_id year_id location_id sex_id age_group_id cause_id rei_id
		drop measure metric
		replace rei_id = 0 if rei_id==.

		** 1990 - 2015
		gen year_start_id = 1990 if year_id == 9999
		gen year_end_id = 2015 if year_id == 9999
		** 2005 - 2015
		replace year_start_id = 2005 if year_id == 9100
		replace year_end_id = 2015 if year_id == 9100
		** 1990 - 2005
		replace year_start_id = 1990 if year_id == 9101
		replace year_end_id = 2005 if year_id == 9101

		order measure_id year_id year_start_id year_end_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower
		compress
		** outsheet by measure for fastest db loading
		levelsof measure_id, local(measures) c
		foreach measure of local measures {
			cap mkdir "`tmp_dir'/temp/upload/`measure'"
			cap mkdir "`tmp_dir'/temp/upload/`measure'/single_year"
			cap mkdir "`tmp_dir'/temp/upload/`measure'/multi_year"

		** DALYs - summary table - no risks - single year
		if "`epi'"!="0" {
			if inlist(`measure',2) & inlist(`year_id',1990,1995,2000,2005,2010,2015) {
				outsheet measure_id year_id location_id sex_id age_group_id cause_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/single_year/upload_summary_`location_id'_`year_id'.csv" if (rei_id == 0 & year_id<9000 & measure_id==`measure'), replace nolabel noquote nonames comma
			}
		}

		** single year CoD
		if inlist(`measure',1,4) {
			outsheet measure_id year_id location_id sex_id age_group_id cause_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/single_year/upload_cod_`location_id'_`year_id'.csv" if (rei_id == 0 & year_id<9000 & measure_id==`measure'), replace nolabel noquote nonames comma
		}

if "`risk'" != "0" {
			** single year risk
	if inlist(`year_id',1990,1995,2000,2005,2010,2015) {
			outsheet measure_id year_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/single_year/upload_risk_`location_id'_`year_id'.csv" if (rei_id!=0 & ((rei_id<171 | rei_id>190)) & year_id<9000 & measure_id==`measure'), replace nolabel noquote nonames comma			

			** and etiology - we have all measures if ran with YLDs
	if "`epi'"!="0" {
		if inlist(`measure',1,2,3,4) {
			outsheet measure_id year_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/single_year/upload_eti_`location_id'_`year_id'.csv" if ((rei_id>=171 & rei_id<=190) & year_id<9000 & measure_id==`measure'), replace nolabel noquote nonames comma
		}
	}

	if "`epi'"=="0" {
		if inlist(`measure',1,4) {
			outsheet measure_id year_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/single_year/upload_eti_`location_id'_`year_id'.csv" if ((rei_id>=171 & rei_id<=190) & year_id<9000 & measure_id==`measure'), replace nolabel noquote nonames comma
		}
	}

	} // end risk and eti year loop	
}

				** multi year CoD
				if inlist(`year_id',2005,2015) {
					preserve
					keep if rei_id == 0
					drop rei_id
					if inlist(`measure',1,4) {
						outsheet measure_id year_start_id year_end_id location_id sex_id age_group_id cause_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/multi_year/upload_cod_`location_id'_`year_id'.csv" if (year_id>9000 & measure_id==`measure'), replace nolabel noquote nonames comma
					}

						if "`epi'"!="0" {
							if inlist(`measure',2) {
								outsheet measure_id year_start_id year_end_id location_id sex_id age_group_id cause_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/multi_year/upload_summary_`location_id'_`year_id'.csv" if (year_id>9000 & measure_id==`measure'), replace nolabel noquote nonames comma
							}
						}

					restore
			if "`risk'" != "0" {
				** multi year risk
					outsheet measure_id year_start_id year_end_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/multi_year/upload_risk_`location_id'_`year_id'.csv" if (rei_id!=0 & ((rei_id<171 | rei_id>190)) & year_id>9000 & measure_id==`measure'), replace nolabel noquote nonames comma

				** multi year eti
				if "`epi'"!="0" {
				if inlist(`measure',1,2,3,4) {
					outsheet measure_id year_start_id year_end_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/multi_year/upload_eti_`location_id'_`year_id'.csv" if ((rei_id>=171 & rei_id<=190) & year_id>9000 & measure_id==`measure'), replace nolabel noquote nonames comma
				}
				}

				if "`epi'"=="0" {
				if inlist(`measure',1,4) {
					outsheet measure_id year_start_id year_end_id location_id sex_id age_group_id cause_id rei_id metric_id val upper lower using "`tmp_dir'/temp/upload/`measure'/multi_year/upload_eti_`location_id'_`year_id'.csv" if ((rei_id>=171 & rei_id<=190) & year_id>9000 & measure_id==`measure'), replace nolabel noquote nonames comma
				}
				}

			} // end risk!=0 loop

				} // end multi year loop
		} // end for each measure loop

		file open finish using "`tmp_dir'/checks/loclvl`loclvl'_summary_`location_id'_`year_id'.txt", write replace
		file close finish

		noi di c(current_time) + ": END"
		cap log close

} //end quiet loop




