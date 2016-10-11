// July 2016
// Merge smoothed fraction married data (to modern contraception prevalence data.  Save for crosswalking.	
	
	
	// open template file
	use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\template.dta", clear
	// merge on prevalence data
	merge 1:m iso3 year agegroup using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\modern_contra\modern_contra_extracted_and_report_data.dta", keep(1 3) nogen
	
	// merge on population data
	merge m:1 iso3 year agegroup using "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\population.dta", keep(1 3) nogen
		// drop countries that are not ihme_countries

		drop  sex region_name
	// relace prevalences equal to 0 and 1 so that can take logit 
	foreach type in modall_prev modcurrmarr_prev modevermarr_prev {
		replace `type' = 0.000000001 if `type'==0
		replace `type' = 0.999999999 if `type'==1
	}
	save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\input\modern_contra\modern_contra_for_crosswalking.dta", replace
	
