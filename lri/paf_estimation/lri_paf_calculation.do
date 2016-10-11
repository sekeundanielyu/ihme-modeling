// Purpose: Calculate LRI PAFs including DisMod output, static odds ratios, and CFR correction

// do "/home/j/temp/LRI/Code/launch_paf_calculation.do"
set more off
set maxvar 32000
** Set directories
	if c(os) == "Windows" {
		global j "J:"
		
		set mem 1g
	}
	if c(os) == "Unix" {
		global j "/home/j"
		set mem 2g

		set odbcmgr unixodbc
	}
qui include "$j/WORK/10_gbd/00_library/functions/get_draws.ado"	

// influenza and RSV me_ids //
local id 1259 1269

// Loop influenza and RSV by location, year, and sex 
// Creates a pair of PAF csvs for each modelable_entity_id 

foreach me_id in `id' {

// Get DisMod proportion draws //
	get_draws, gbd_id_field(modelable_entity_id) source(dismod) gbd_id(`me_id') location_ids(`1') year_ids(`2') sex_ids(`3') clear
		tempfile draws
		save `draws'
		
// DisMod models have a covariate for 'severity' //
	local best = model_version_id[1]
	
	import delimited "/share/epi/panda_cascade/prod/`best'/full/locations/1/outputs/both/2000/model_effect.csv", clear
			gen model_version_id = `best'
			keep if study_covariate_id == "217.0" | study_covariate_id == "933.0"
			gen se = (upper_effect-mean_effect)/invnormal(0.975)
			gen _0id = 1
// Create 1000 draws of this severity scalar, is in log-space //
	do "$j/Project/Causes of Death/CoDMod/Models/B/codes/small codes/gen matrix of draws.do" mean_effect se effect
		svmat effect, names(scalar_)
		qui forval i = 1/1000 {
				local j = `i' - 1
				replace scalar_`i' = exp(scalar_`i')
				rename scalar_`i' scalar_`j'
		}
		keep scalar_* model_version_id

		merge 1:m model_version_id using `draws', force
		drop _m
		save `draws', replace
		
// Previously created file with 1000 draws of the odds ratio of LRI given pathogen presence //			
	use "$j/temp/LRI/Files/odds_draws.dta", clear
		keep if modelable_entity_id==`me_id'

	merge 1:1 age_group_id using `draws', nogen
		gen rei_id = 190
		replace rei_id = 187 if `me_id' == 1259
		gen rei_name = "eti_lri_flu"
		replace rei_name = "eti_lri_rsv" if `me_id' == 1269
		local rei = rei_name[1]
	
	preserve
	
// Generate YLD PAF is proportion * (1-1/odds ratio) //
		forval i = 0/999 {
			gen paf_`i' = draw_`i' * (1-1/rr_`i')
			replace paf_`i' = 1 if paf_`i' > 1
	/// No etiology in neo-nates ///
			replace paf_`i' = 0 if age_group_id<=3
		}
		drop rr_* draw_* scalar_*
		keep if age_group_id <22
		cap drop modelable_entity_id
		export delimited "/snfs2/HOME/Etiologies/PAFs/`rei'/paf_yld_`1'_`2'_`3'.csv", replace

	restore

// Generate YLL PAF is proportion * severity_scalar * cfr_scalar * (1-1/odds ratio) //
// This is a previously created file with 1000 draws of the ratio of case fatality among viral to bacterial
// causes of LRI by age //
		merge 1:1 age_group_id using "$j/temp/LRI/Files/cfr_scalar_draws.dta", nogen
		
		forval i = 0/999 {
			gen paf_`i' = draw_`i' * (1-1/rr_`i') * scalarCFR_`i' * scalar_`i'
			replace paf_`i' = 1 if paf_`i' > 1
	/// No etiology in neo-nates, consistent with GBD 2013 ///
			replace paf_`i' = 0 if age_group_id<=3
		}

		drop rr_* draw_* scalar_*
		
		keep if age_group_id <22
		cap drop modelable_entity_id
		export delimited "/snfs2/HOME/Etiologies/PAFs/`rei'/paf_yll_`1'_`2'_`3'.csv", replace
}

