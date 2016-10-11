

adopath + "$prefix/WORK/10_gbd/00_library/functions"
clear all
	set more off
	set mem 2g
	set maxvar 32000
	set type double, perm
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	local input_dir "$prefix/WORK/04_epi/01_database/02_data/imp_id/04_models/02_inputs"


	preserve 
	get_location_metadata, location_set_id(9) clear 
	rename ihme_loc_id iso3
	gen HIC = 0 
	replace HIC = 1 if super_region_name == "High-income"
	keep location_id iso3 location_name developed HIC
	tempfile location_data 
	save `location_data'
	restore 

	
*****************************************************************************
	***	Load and prep data
*****************************************************************************

	import excel "`input_dir'/ID_sev_data.xlsx", clear firstrow 
		rename nid 			studyid 
		rename sample_size 	N
		rename cases		n_cases

		merge m:1 location_id using `location_data', keep(3) nogen 

	tempfile data 
	save `data', replace 


*****************************************************************************
	***	Calculate fractions and do meta-analysis 
*****************************************************************************


	use `data', clear 

	//Get reference category, aka threshold 70
	foreach thresh_denom in 50 70 {
		preserve
		levelsof studyid if level == `thresh_denom', local(ids_at_thresh) sep(",")
		keep if level <= `thresh_denom'
		keep if inlist(studyid, `ids_at_thresh') //Only want study with threshold of interest 
		collapse (sum) N = n_cases, by(studyid sex iso3 HIC)
		tempfile denominator_`thresh_denom'
		save `denominator_`thresh_denom'', replace 
		restore 
		}
	
* local thresh_num 20
foreach thresh_num in 20 35 50 85 {

		use `data', clear 

		if inlist(`thresh_num', 50, 85) local thresh_denom 70
		if inlist(`thresh_num', 20, 35) local thresh_denom 50

		levelsof studyid if level == `thresh_num', local(ids_at_thresh) sep(",")

		//<50 is done as threshold, others are discrete 
		if inlist(`thresh_num', 20, 35, 85) keep if level == `thresh_num' 
		else if `thresh_num' == 50 keep if level <= 50

		keep if inlist(studyid, `ids_at_thresh') //Only want study with threshold of interest (relevant to <50)
		collapse (sum) cases = n_cases, by(studyid sex iso3 HIC)
		tempfile numerator 
		save `numerator', replace 

		merge 1:1 studyid sex using `denominator_`thresh_denom'', nogen keep(3)
		sort studyid

		gen mean = cases / N 
		gen sd = sqrt(mean * (1 - mean) / N)
		gen uci = mean + 1.96*sd 
		gen lci = mean - 1.96*sd


		//meta-analysis: for all but borderline do by high-income status 
		if `thresh_num' == 85 {
			metan mean lci uci, random lcols(iso3) rcols(cases) textsize(90) title("70-85 as proportion of <70") saving("`input_dir'/sev_splits_forest_plots/sev_`thresh_num'", replace)
			local mean_`thresh_num' = `r(ES)'
			local uci_`thresh_num' = `r(ci_upp)'
			local lci_`thresh_num' = `r(ci_low)'
			local se_`thresh_num' = `r(seES)'
			}
		else {
			metan mean lci uci if HIC == 1 , random lcols(iso3) rcols(cases) by(HIC) textsize(90) title("%<`thresh_num' of <`thresh_denom', High-income") saving("`input_dir'/sev_splits_forest_plots/sev_`thresh_num'_HIC", replace)
			local mean_HIC_`thresh_num' = `r(ES)'
			local uci_HIC_`thresh_num' = `r(ci_upp)'
			local lci_HIC_`thresh_num' = `r(ci_low)'
			local se_HIC_`thresh_num' = `r(seES)'
			metan mean lci uci if HIC == 0 , random lcols(iso3) rcols(cases) by(HIC) textsize(90) title("%<`thresh_num' of <`thresh_denom', LMIC") saving("`input_dir'/sev_splits_forest_plots/sev_`thresh_num'_LMIC", replace)
			local mean_LMIC_`thresh_num' = `r(ES)'
			local uci_LMIC_`thresh_num' = `r(ci_upp)'
			local lci_LMIC_`thresh_num' = `r(ci_low)'
			local se_LMIC_`thresh_num' = `r(seES)'
			}

		}


*****************************************************************************
	***	Create 1000 draws from mean + 95%CI calculated by meta-analysis
*****************************************************************************
	preserve
	clear 
	set obs 1000
	foreach sev in 85 HIC_20 LMIC_20 HIC_35 LMIC_35 HIC_50 LMIC_50 {
		gen prop_`sev' = rnormal(`mean_`sev'', `se_`sev'') 
		}

*****************************************************************************
	***	Calculate discrete categories as proportion of <70 envelope. 
*****************************************************************************

		//Since <20 and 20-34 were calculated as proportion of <50, we should adjust 
		gen LMIC_id_prof =  prop_LMIC_20 *  prop_LMIC_50
		gen LMIC_id_sev =  prop_LMIC_35 *  prop_LMIC_50
		gen HIC_id_prof =  prop_HIC_20 *  prop_HIC_50
		gen HIC_id_sev =  prop_HIC_35 *  prop_HIC_50

		//50-70 is inverse of <50 
		gen HIC_id_mild = 1 - prop_HIC_50
		gen LMIC_id_mild = 1 - prop_LMIC_50

		//35-50 is <50 minus <20 and 20-34
		gen HIC_id_mod = prop_HIC_50 - HIC_id_prof - HIC_id_sev
		gen LMIC_id_mod = prop_LMIC_50 - LMIC_id_prof -LMIC_id_sev

				
			//Ideally, they should add to one (not including the borderline)
				egen test_HIC = rowtotal(HIC*)
				egen test_LMIC = rowtotal(LMIC*)

				count if !inrange(test_HIC, 0.99, 1.01) | !inrange(test_LMIC, 0.99, 1.01) 
				if `r(N)' > 0 di in red "CHECK SUM OF DISCRETE SEVERITY PROPS" BREAK 

		//70-85 is same for HIC and LMIC 
		gen HIC_id_bord = prop_85
		gen LMIC_id_bord = prop_85


	keep *id*

	//Transform into format for custom code 
	
	xpose, varname clear 

	split _varname, parse("_") limit(3) gen(x)
	rename x1 income 
	egen healthstate = concat(x2 x3), punct("_")

	order income healthstate 

	save "`input_dir'/fraction_draws_2015", replace
