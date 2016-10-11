
** drop duplicate report data and odd prevalence points in modern contra use
use "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\master_modern_contra_with_covariates.dta", clear


drop if iso3 == "BTN" & year == 2000 & survey == "National Health Survey" // these points are all really low or high (2.3) and there is another survey from this year from bhutan

// drop duplicate data
drop if filename == "HND_RHS_1996_WN.DTA"
drop if filename == "JAM_RHS_1993_WN_Y2011M03D24.dta"
drop if filename == "JAM_RHS_1989_WN_Y2011M03D24.dta" & modall_prev > .9

ya i 
drop if iso3 == "USA" & modall_prev != . & report_data != 1

save "J:\Project\Coverage\Contraceptives\2015 Contraceptive Prevalence Estimates\gpr_data\output\master_modern_contra_with_covariates_dedupped.dta", replace



