// August 2016
// Merge unmet need data with country template
	
	
	// open template file
	use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\template.dta", clear
	// merge on prevalence data
	merge 1:m iso3 year agegroup using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\unmet_need\unmet_need_extracted_and_report_data.dta", keep(1 3) nogen
	
	// merge on population data
	merge m:1 iso3 year agegroup using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\population.dta", keep(1 3) nogen
		// drop countries that are not ihme_countries

		drop  sex region_name
	// relace prevalences equal to 0 and 1 so that can take logit 
	foreach type in met_need_modern_prev met_need_modern_curr_prev  {
		replace `type' = 0.000000001 if `type'==0
		replace `type' = 0.999999999 if `type'==1
	}
	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\unmet_need\unmet_need_for_crosswalking.dta", replace
	
