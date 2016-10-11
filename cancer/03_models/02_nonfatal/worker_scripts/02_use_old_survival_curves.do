** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		Calculate survival by geographic area, year, age, sex, cancer
** **************************************************************************
		
** **************************************************************************
// save a copy of current mesothelioma and all-cause data
	keep if acause == "neo_meso" | acause == "_neo"
	tempfile master_data
	save `master_data', replace

// get old data for each cancer type
	foreach oc in Bladder Brain Colon Esophagus Gallbladder Hodgkins Kidney Larynx Leukemia Liver Lung Mouth Mult_myel Nasopharynx Nonhodg_lymph Other_mal Other_naso Pancreas Skin_mal Skin_non Stomach Thyroid {
		if "`oc'" == "Bladder" local acause_name "neo_bladder"
		if "`oc'" == "Brain" local acause_name "neo_brain"
		if "`oc'" == "Colon" local acause_name "neo_colorectal"
		if "`oc'" == "Esophagus" local acause_name "neo_esophageal"
		if "`oc'" == "Hodgkins" local acause_name "neo_hodgkins"
		if "`oc'" == "Kidney" local acause_name "neo_kidney"
		if "`oc'" == "Larynx" local acause_name "neo_larynx"
		if "`oc'" == "Leukemia" local acause_name "neo_leukemia"
		if "`oc'" == "Liver" local acause_name "neo_liver"
		if "`oc'" == "Lung" local acause_name "neo_lung"
		if "`oc'" == "Mouth" local acause_name "neo_mouth"
		if "`oc'" == "Mult_myel" local acause_name "neo_myeloma"
		if "`oc'" == "Nasopharynx" local acause_name "neo_nasopharynx"
		if "`oc'" == "Nonhodg_lymph" local acause_name "neo_lymphoma"
		if "`oc'" == "Other_mal" local acause_name "neo_other"
		if "`oc'" == "Other_naso" local acause_name "neo_otherpharynx"
		if "`oc'" == "Pancreas" local acause_name "neo_pancreas"
		if "`oc'" == "Skin_mal" local acause_name "neo_melanoma"
		if "`oc'" == "Skin_non" local acause_name "neo_nmsc_scc"
		if "`oc'" == "Stomach" local acause_name "neo_stomach"
		if "`oc'" == "Thyroid" local acause_name "neo_thyroid"
		foreach s in M F {
			display "Appending in `oc'_`s'"
			// Get data
				use "$j/Project/GBD/Systematic Reviews/ANALYSES/MALIGNANT NEOPLASMS/SEQUELAE/`oc'_`s'/survival_difference_`oc'_`s'.dta", clear
			// Reformat
				keep if year == 2010
				gen acause = "`acause_name'"
				gen survived_years = months / 12
				rename best survival_best
				rename worst survival_worst
				if "`s'" == "M" gen sex = 1
				if "`s'" == "F" gen sex = 2
				keep acause sex survived_years survival_best survival_worst
				order acause sex survived_years survival_best survival_worst
			// Append and resave
				append using `master_data'
				tempfile master_data
				save `master_data', replace
		}
	}

	foreach oc in Breast Cervical Corpus Ovary Prostate Testis {
		if "`oc'" == "Breast" local acause_name "neo_breast"
		if "`oc'" == "Cervical" local acause_name "neo_cervical"
		if "`oc'" == "Corpus" local acause_name "neo_uterine"
		if "`oc'" == "Ovary" local acause_name "neo_ovarian"
		if "`oc'" == "Prostate" local acause_name "neo_prostate"
		if "`oc'" == "Testis" local acause_name "neo_testicular"
		display "Appending `oc'"
		// Get data
			use "$j/Project/GBD/Systematic Reviews/ANALYSES/MALIGNANT NEOPLASMS/SEQUELAE/`oc'/survival_difference_`oc'.dta", clear
		// Reformat
			keep if year == 2010
			gen acause = "`acause_name'"
			gen survived_years = months / 12
			rename best survival_best
			rename worst survival_worst
			if "`oc'" == "Breast" | "`oc'" == "Cervical" | "`oc'" == "Corpus" | "`oc'" == "Ovary" {
				gen sex = 2
			}
			if "`oc'" == "Prostate" | "`oc'" == "Testis" {
				gen sex = 1
			}
			keep acause sex survived_years survival_best survival_worst
			order acause sex survived_years survival_best survival_worst
		// Append and resave
			append using `master_data'
			tempfile master_data
			save `master_data', replace
	}

** ****
** END
** ****
