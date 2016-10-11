

clear all
set more off
	set type double, perm
	if c(os) == "Unix" {
		global prefix "/home/j"
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}

	adopath + "$prefix/WORK/10_gbd/00_library/functions"
	ssc install metaprop

			get_location_metadata, location_set_id(9) clear 
			rename ihme_loc_id iso3
			keep location_id iso3 location_name 
			tempfile location_data 
			save `location_data'

		//template for output
			clear 
			tempfile etio_props
			save `etio_props', emptyok replace 

		import excel "$prefix/WORK/04_epi/01_database/02_data/imp_gbs/04_models/02_inputs/gbs_etiology_for_custom_database.xlsx", firstrow clear 

			merge m:1 iso3 using `location_data'
			count if _merge == 1 
			if `r(N)' > 1 BREAK 
			keep if _merge == 3
			drop _merge Country

			tempfile data 
			save `data', replace


* local etio influenza 
foreach etio in all_specified influenza URI GI other_infectious {
	use `data', clear 

	gen cases_`etio' = value_prop_`etio' * cases 
	metaprop cases_`etio' cases, random lcols(iso3) title("Proportion `etio'") saving("$prefix/WORK/04_epi/01_database/02_data/imp_gbs/04_models/02_inputs/gbs_etiology_metaanalysis_forest_plots/gbs_prop_`etio'", replace)
	
		gen mean = `r(ES)'
		gen lci = `r(ci_low)'
		gen uci = `r(ci_upp)'

	preserve
		keep if _n == 1 
		gen etiology = "`etio'"
		keep etiology mean lci uci 
	append using `etio_props'
	save `etio_props', replace 
	restore 

	} //next etiology 

use `etio_props', clear

//Squeeze specified etiologies (ie, not "other_neurological") into the "all specified" envelope
	preserve
	levelsof mean if etiology == "all_specified", local(total)
	drop if etiology == "all_specified"
	collapse (sum) mean 
	levelsof mean, local(causes)
	restore
	local squeeze = `total' / `causes'

	di in red "squeeze factor = `squeeze'"
	replace mean = mean * `total' / `causes' if etiology != "all_specified"
	replace lci = lci * `total' / `causes' if etiology != "all_specified"
	replace uci = uci * `total' / `causes' if etiology != "all_specified"


//other neurological disorders is difference between 100% and the "all_specified" (and all_specified is not an input for final models)
	levelsof lci if etiology == "all_specified", local(lci_all)
	levelsof uci if etiology == "all_specified", local(uci_all)
	replace etiology = "other_neurological" if etiology == "all_specified"
	replace mean = 1 - mean if etiology == "other_neurological"
	replace lci = 1 - `uci_all' if etiology == "other_neurological"
	replace uci = 1 - `lci_all' if etiology == "other_neurological"

order etiology


export excel "$prefix/WORK/04_epi/01_database/02_data/imp_gbs/04_models/02_inputs/gbs_etiology_metaanalysis.xlsx", firstrow(var) replace 






