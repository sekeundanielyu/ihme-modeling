// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// Purpose:		Runs GDP - sequelae proportion regression
// Description:	Running regression between GDP and outcome proportions

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	adopath + "$prefix/WORK/10_gbd/00_library/functions"



// *********************************************************************************************************************************************************************
// run code

// load covariate data for GDP per capita in international dollars
	get_covariate_estimates, covariate_id(851) clear
	drop covariate_name_short model_version_id covariate_id age_group_id age_group_name sex_id lower_value upper_value location_name
	tempfile gdp_cov
	save `gdp_cov'

// load results from Edmonds
	import delimited "$prefix/temp/strUser/meningitis/04_models/gbd2015/02_inputs/Major_sequelae_gbd2015.csv", clear
	rename studyyear year_id
	merge m:1 location_id year_id using `gdp_cov', nogen
	rename mean_value gdp
	rename proportionwith1majorsequela prop_major
	gen cases = n * prop_major
	gen lngdp = ln(gdp)

// run regression --  this is a linear regression when in the form of binomial outputs proportion values in logit space so they're bounded between 0 and 1
	glm cases lngdp, family(binomial n)

// save file only with values from Edmonds
	preserve
	drop if missing(prop_major)
	export delimited "$prefix/temp/strUser/meningitis/04_models/gbd2015/02_inputs/prop_major_gdp.csv", replace
	restore

// create prediction variables -- want to predict these values still in logit space because that's where the linear model is
	predict pred_mean, xb
	predict pred_se, stdp

	keep year_id location_id pred_mean pred_se
	keep if year_id == 1990 | year_id == 1995 | year_id == 2000 | year_id == 2005 | year_id == 2010 | year_id == 2015

// create 1000 draws -- need to invlogit these because they've been calculated in logit space
	forvalues i = 0/999 {
		gen draw_`i' = invlogit(rnormal(pred_mean, pred_se))
	}

// clean
	sort location_id year_id
	drop pred*

// save
	export delimited "$prefix/temp/strUser/meningitis/04_models/gbd2015/02_inputs/major_prop_draws.csv", replace

// comparison between 2013 results and this year

	import delimited "J:/WORK/04_epi/01_database/02_data/meningitis/archive_2013/04_models/gbd2014/02_inputs/sequelae_major_prop_initial_draws.csv", clear
	drop in 1/7
	rename v1 iso
	keep if regexm(iso, "2010")

	forvalues i = 2/1001 {
		local a = `i' - 2
		rename v`i' draw_`a'
	}

	gen iso3 = substr(iso, 1, 3)
	order iso iso3
	replace iso3 = substr(iso, 1, 7) if regexm(iso, "CHN")
	replace iso3 = substr(iso, 1, 8) if regexm(iso, "MEX")
	replace iso3 = substr(iso, 1, 7) if regexm(iso, "GBR_43")
	replace iso3 = substr(iso, 1, 8) if regexm(iso, "GBR_46")
	drop iso

	preserve
	get_location_metadata, location_set_id(9) clear
	keep ihme_loc_id location_id
	rename ihme_loc_id iso3
	tempfile ids
	save `ids'
	restore

	merge 1:1 iso3 using `ids', nogen keep(1 3)
	order location_id
	drop iso3
	egen mean_2013 = rowmean(draw_*)
	drop draw_*
	tempfile mean2013
	save `mean2013'

	import delimited "J:/temp/strUser/meningitis/04_models/gbd2015/02_inputs/major_prop_draws.csv", clear
	keep if year_id == 2010
	egen mean_2015 = rowmean(draw_*)
	drop draw_*
	merge 1:1 location_id using `mean2013', nogen keep(3)
	
