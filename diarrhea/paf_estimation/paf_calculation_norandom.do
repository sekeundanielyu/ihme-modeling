// Purpose: Calculate diarrhea PAFs including DisMod output, misclassification correction, and odds ratios from GEMS
// This particular version of this file is for case definition of qPCR Ct value below lowest inversion in accuracy.
// It also uses the fixed effects only from the mixed effects logistic regression models.

// do "/home/j/temp/GEMS/Code/launch_paf_calculation.do"

// Set up //
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
do "$j/WORK/10_gbd/00_library/functions/get_draws.ado"			

local year 1990 1995 2000 2005 2010 2015

/// Perform for each estimation year ///

foreach y in `year' {
//// import fixed effects from mixed effects conditional logistic regression ////
	import delimited "$j/temp/GEMS/Regressions/me_fixed_bimodal_nonsig.csv", clear
	
	/// Make sure there are relative limits to ORs ///
		qui forval i = 1/1000 {
			replace lnor_`i' = 100 if lnor_`i' > 100
			replace lnor_`i' = ln(0.5) if lnor_`i' < ln(0.5) // PAF should not be less than -proportion
		}
		cap drop _m
		tempfile odds
		save `odds'

	/// Pull DisMod estimates ///
	get_draws, gbd_id_field(modelable_entity_id) source(dismod) gbd_id(`4') location_ids(`1') year_ids(`y') sex_ids(`3') clear
		tempfile draws
		save `draws'
		
		local best = model_version_id[1]
		
	/// This is pulling in the coefficient for hospitalized cases from the 'best' DisMod model ////
	import delimited "/share/epi/panda_cascade/prod/`best'/full/locations/1/outputs/both/2000/model_effect.csv", clear
			gen model_version_id = `best'
			keep if study_covariate_id == "217.0" | study_covariate_id == "933.0"
			gen se = upper_effect-mean_effect
			gen _0id = 1
	// Uncertainty for scalar //	
			qui forval i = 1/1000 {
					gen scalar_`i' = exp(rnormal(mean_effect, se))
			}
			keep scalar* model_version_id
			merge 1:m model_version_id using `draws', force
			drop _m
		
			gen agecat = 1
			replace agecat = 2 if age_group_id==5
			replace agecat = 3 if age_group_id>5
			keep if age_group_id < 22
		
		/// This is a pre-created matrix of sensitivity and specificity draws comparing lab to qPCR case definition ///
			merge m:1 modelable_entity_id using "$j/temp/GEMS/adjustment_matrix_bimodal.dta"
			keep if _m==3
			cap drop _m cause_id
			merge m:m age_group_id modelable_entity_id using `odds'
			
			keep if _m==3
			cap drop _m dup
			sort age_group_id

	//// Calculate YLDs ////
		preserve
			qui	forval i = 1/1000{
					local j = `i'-1
					gen proportion_`j' = (draw_`j'+ specificity_`i' - 1)/(sensitivity_`i' + specificity_`i' - 1)
					replace proportion_`j' = 1 if proportion_`j' > 1
					replace proportion_`j' = 0.001 if proportion_`j' < 0
					gen paf_`j' = proportion_`j' * (1-1/exp(lnor_`i'))
					replace paf_`j' = 1 if paf_`j' >1
				}
			drop scalar_* sensitivity_* specificity_* draw_* lnor_* proportion_*
			gen cause_id = 302

			local rei = rei[1]
			keep age_group_id cause_id rei_id sex_id rei_name location_id paf_*

			bysort age_group_id: gen num = _n
			drop if num > 1
			drop num

	export delimited "/snfs2/HOME/Etiologies/Bimodal/`rei'/paf_yld_`1'_`y'_`3'.csv", replace

	//// Calculate YLLs ////
		restore
				qui forval i = 1/1000{
					local j= `i' - 1
					replace draw_`j' = draw_`j' * scalar_`i'
					gen proportion_`j' = (draw_`j'+ specificity_`i' - 1)/(sensitivity_`i' + specificity_`i' - 1)
					replace proportion_`j' = 1 if proportion_`j' > 1
					replace proportion_`j' = 0.001 if proportion_`j' < 0
					gen paf_`j' = proportion_`j' * (1-1/exp(lnor_`i'))

					replace paf_`j' = 1 if paf_`j' >1
				}
			drop scalar_* sensitivity_* specificity_* draw_* lnor_* proportion_*
			gen cause_id = 302

			local rei = rei[1]
			keep age_group_id cause_id rei_id sex_id rei_name location_id paf_*
			bysort age_group_id: gen num = _n
			drop if num > 1
			drop num

	export delimited "/snfs2/HOME/Etiologies/Bimodal/`rei'/paf_yll_`1'_`y'_`3'.csv", replace

}	

