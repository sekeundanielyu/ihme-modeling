// Map ICD codes with Nick K's 2015 map

cap program drop map_dual_icd
program define map_dual_icd
	version 12
	syntax , n_var(string) e_var(string) icd_ver(string)

	quietly {
		preserve
			use "$prefix/WORK/06_hospital/01_inputs/programs/extract/icd_me_map_kassebaum/ncode_icd_map.dta", clear
				rename icd_code `n_var'
				replace `n_var' = subinstr(`n_var',".","",.)
				keep if icd_ver == "`icd_ver'"
				tempfile ncode_icds 
				save `ncode_icds', replace
			use "$prefix/WORK/06_hospital/01_inputs/programs/extract/icd_me_map_kassebaum/ecode_icd_map.dta", clear
				rename icd_code `e_var'
				replace `e_var' = subinstr(`e_var',".","",.)
				keep if icd_ver == "`icd_ver'"
				tempfile ecode_icds 
				save `ecode_icds', replace
		restore
			merge m:1 `n_var' using `ncode_icds'
			count if _merge == 3
	}
		di in red "`r(N)' cases matched to N-code."
	quietly {	
		keep if _merge == 3
		drop _merge
		//rename `e_var' e_icd_code
		merge m:1 `e_var' using `ecode_icds'
		count if _merge == 3
	}
		di in red "`r(N)' cases also matched to E-code."
		keep if _merge == 3
		drop _merge
	rename acause final_ecode_1
	rename inj_ncode final_ncode_1

end

