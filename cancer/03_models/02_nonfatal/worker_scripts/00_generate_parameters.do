** *********************************************************************************************************************************************************************
** *********************************************************************************************************************************************************************
** Purpose:		used by 00_launch to create parameter files 

** *************************************************************************************************************
** 
** *************************************************************************************************************
// Provide feedback
	noisily display "Creating parameter files..."

// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" global j "/home/j"
	else if c(os) == "Windows" global j "J:"
	
// Set common directories, functions, and globals (shell, finalize_worker, finalization_folder...)
	do "$j/WORK/07_registry/cancer/03_models/02_yld_estimation/01_code/subroutines/set_paths.do"

// set refresh_population (NOTE: refresh_population set to 0 will bypass creation of a new population data file)
	if "$refresh_population" == "" global refresh_population = 0

// Ensure that all output directories are present, including directory for scalars and logs
	capture mkdir "$long_term_copy_parameters"
	capture mkdir "$parameters_folder"
	capture mkdir "$long_term_copy_scalars"
	capture mkdir "$scalars_folder"

// Toggle connection settings
	clear
	run "[filepath]/create_connection_string.ado"
	create_connection_string
	local cod_conn = r(conn_string)	
	create_connection_string, server("modeling-epi-db")
	local epi_conn = r(conn_string)	


** *************************************************************************************************************
** Generate database of constants
** *************************************************************************************************************

// Determine codcorrect version
	if "$codcorrect_version" == "" {
		odbc load, exec("SELECT * FROM cod.output_version WHERE is_best = 1 AND isnull(best_end)") `cod_conn' clear
		levelsof(output_version_id), local(codcorrect_version) clean
		global codcorrect_version = "`codcorrect_version'"
	}

//  Create document
	clear
	set obs 1
	gen codcorrect_version = $codcorrect_version

// years
	gen min_year = $min_year
	gen max_year = $max_year

// survival
	gen max_survival_months = $max_survival_months

// upload measure_ids
	gen incidence_measure_id = 6
	gen prevalence_measure_id = 5
	gen proportion_measure_id = 18
	gen mortality_measure_id = 1
	gen yll_measure_id = 4
	gen yld_measure_id = 3
	gen daly_measure_id = 2

// save
	save "$parameters_folder/constants.dta", replace
	save "$long_term_copy_parameters/constants.dta", replace 

** *************************************************************************************************************
** Population
** *************************************************************************************************************
// Population

	noisily di "   Refreshing population..."
	
	// get data 
		if $refresh_population do "$code_prefix/00_common/get_demographics.do"
		else use "$cancer_storage/00_common/populations.dta", clear
	
	// adjust age
		di "adjusting age"
			drop age_group_name
			rename gen age = . 
			replace age = 0 if age_group == 2
			replace age = .01 if age_group == 3
			replace age = .1 if age_group == 4
			replace age = 1 if age_group == 5
			replace age = (age_group -5)*5 if age_group > 5 & age_group < 22
			replace age = 99 if age_group == 22
			drop if age == .
			
	// drop irrelevant variables
	drop path_to_top env
			
	// save
	save "$parameters_folder/populations.dta", replace
	save "$long_term_copy_parameters/populations.dta", replace

** *************************************************************************************************************
** Locations
** *************************************************************************************************************
// Create Location Map
	// get epi-modeled countries
		import delimited using "[filepath]/codcorrect/$codcorrect_version/_temp/location_hierarchy.csv", clear
		keep location_id is_estimate
		rename is_estimate epi_model
		tempfile epi_locations
		save `epi_locations', replace
	
	// merge with mi-modeled locations
		import delimited using "$common_cancer_data/modeled_locations.csv", clear
		keep location_id location_type parent_id parent_type ihme_loc_id model developed super_region_id
		rename model mi_model
		merge 1:1 location_id using `epi_locations', keep(3) assert(1 3) nogen
		count if mi_model == 0 & epi_model == 1 & !inlist(location_type, "global", "superregion", "region", "dev_status")
		if r(N) {
			di "STOP: not all Epi models have MI model inputs"
			BREAK
		}
		gen model = epi_model
		drop mi_model epi_model
		save "$parameters_folder/locations.dta", replace
		save "$long_term_copy_parameters/locations.dta", replace

** *************************************************************************************************************
** Modelable Entities
** *************************************************************************************************************
// // Get modelable_entity_ids	
	// get modelable_entity_id data from database
		#delim ;
		odbc load, exec("SELECT distinct me.modelable_entity_id, me.modelable_entity_name, c.cause_id, c.acause
							FROM epi.modelable_entity me 
							JOIN epi.modelable_entity_cause mc USING (modelable_entity_id) 
							JOIN shared.cause c USING (cause_id)
							WHERE acause like 'neo_%' AND acause not like 'neonatal%'
					") `epi_conn' clear;
		#delim cr

	// mark data that are adjusted due to ectomies
		gen ectomy_rate = .
		replace ectomy_rate = 1 if inlist(modelable_entity_id, 1724, 1711, 1702, 1731, 1777)
		gen sequela = 1 if inlist(modelable_entity_id, 1725, 1726)
	
	// generate stages
		gen stage = "primary" if regexm(lower(modelable_entity_name), "primary")
		replace stage = "in_remission" if regexm(lower(modelable_entity_name), "controlled") | regexm(lower(modelable_entity_name), "control phase")
		replace stage = "disseminated" if regexm(lower(modelable_entity_name), "metastatic")
		replace stage = "terminal" if regexm(lower(modelable_entity_name), "terminal")
		replace stage = "procedure_proportion" if regexm(lower(modelable_entity_name), "proportion") & !regexm(acause, "neo_liver_")
		replace stage = "" if stage == "in_remission"  & regexm(lower(modelable_entity_name), "adjustment")
		replace stage = "none" if sequela == 1

	// create list of modelable entity ids for later sequela query
		levelsof modelable_entity_id, clean local(me_ids)		
		local first_entry = 1
		foreach m in `me_ids' {
			if `first_entry' local me_id_list = "`m'"
			else local me_id_list = "`me_id_list', `m'"
			local first_entry = 0
		}

	// subset procedure data 
		preserve
			keep if stage == "procedure_proportion"
			drop ectomy stage
			keep modelable_entity_id cause_id
			rename modelable_entity_id procedure_proportion_id
			tempfile procedures 
			save `procedures', replace
		restore, preserve
		// save a list of modelable_entity_ids specific to -ectomies for later merge with cause map
			keep if ectomy_rate == 1
			keep modelable_entity_id cause_id
			rename modelable_entity_id procedure_rate_id
			tempfile ectomies 
			save `ectomies', replace
		restore
		// drop data that are no longer relevant
		drop if !inlist(stage, "primary", "in_remission", "disseminated", "terminal")
		drop ectomy

	// save
		save "$parameters_folder/modelable_entity_ids.dta", replace
		save "$long_term_copy_parameters/modelable_entity_ids.dta", replace

	// save version to drop models without modelable_entity_ids
		preserve
			keep cause_id
			duplicates drop
			tempfile to_model
			save `to_model', replace
		restore

	// create sequela_id map for comparison with previous GBD iterations (2013 and earlier)
		#delim ;
		odbc load, exec("SELECT distinct sequela_id, modelable_entity_id
							FROM epi.sequela 
							WHERE modelable_entity_id IN (`me_id_list')
					") `epi_conn' clear;
		#delim cr
		save "$long_term_copy_parameters/sequela_ids.dta", replace

** *************************************************************************************************************
** Causes and MI models
** *************************************************************************************************************
	// get list of available mi models.
		import delimited using "$cancer_storage/03_models/01_mi_ratio/03_results/06_model_selection/model_selection.csv", clear varnames(1)
		keep acause
		gen mi_cause_name = acause
		tempfile mi_models
		save `mi_models', replace

	// get cause data from database
		#delim ;
		odbc load, exec("SELECT cause_id, acause, cause_metadata_value, cause_metadata_type, sort_order
						FROM shared.cause
							JOIN  shared.cause_metadata USING (cause_id)
							JOIN shared.cause_metadata_type USING (cause_metadata_type_id)
                            join shared.cause_hierarchy using (cause_id)
							WHERE cause_metadata_type_id IN (1, 5, 6, 12, 13, 17) 
                            AND acause like 'neo_%' AND acause not like 'neonatal%' 
                            AND cause_set_id = 9 
						") `epi_conn' clear;
		#delim cr

	// keep relevant data 
		keep if substr(acause, 1, 4) == "neo_"
		rename cause_metadata_value mv
		destring mv, replace
		reshape wide mv, i(cause_id acause sort_order) j(cause_metadata_type) string
		rename mv* *
		keep if secret_cause != 1
		drop secret_cause

	// mark which cause-sex pairs are used in modeling
		foreach var of varlist male female {
			rename `var' possible`var'
		}
		
		reshape long possible, i(acause) j(sex) string
		replace sex = "1" if sex == "male"
		replace sex = "2" if sex == "female"
		destring(sex), replace
		gen model = possible
		if trim("$acauses") != "" {
			replace model = 0
			foreach cause of global acauses {
				di "`cause'"
				replace model = 1 if regexm(acause, "`cause'") & possible != 0
			}
		}
		
		foreach exlusion of global exclusions_acause_M {
			replace model = 0 if acause == "`acause'" & sex == 1
		}
		foreach exlusion of global exclusions_acause_F {
			replace model = 0 if acause == "`acause'" & sex == 2
		}

	// GBD 2015 exceptions
		replace model = 0 if inlist(acause, "neo_leukemia_ll", "neo_leukemia_ml")

	// Generate list of cause names to use for downloading of CoD output. 
		gen CoD_model = acause
		replace CoD_model = "neo_nmsc" if acause == "neo_nmsc_scc"

	// Merge with MI model list
		merge m:1 acause using `mi_models', keep(1 3)
		replace model = 0 if _merge == 1
		replace model = 1 if regexm(acause, "neo_liver_")
		replace mi_cause_name = "neo_liver" if regexm(acause, "neo_liver_")
		drop _merge

	// Merge with list of possible modelable_entity_ids
		merge m:1 cause_id using `to_model', keep(1 3)
		replace model = 0 if _merge == 1
		drop _merge
	
	// merge with modelable_entity_ids
		merge m:1 cause_id using `procedures', keep(1 3) assert(1 3) nogen
		merge m:1 cause_id using `ectomies', keep(1 3) assert(1 3) nogen
		replace procedure_proportion_id = . if model == 0
		replace procedure_rate_id = . if model == 0

	// generate cancer procedure
		gen cancer_procedure = ""
		replace cancer_procedure = "hysterectomy" if procedure_rate_id !=. & acause == "neo_cervical"    
		replace cancer_procedure = "laryngectomy" if procedure_rate_id !=. & acause == "neo_larynx"
		replace cancer_procedure = "prostatectomy" if procedure_rate_id !=. & acause == "neo_prostate"
		replace cancer_procedure = "mastectomy" if procedure_rate_id !=. & acause == "neo_breast"
		replace cancer_procedure = "stoma" if procedure_rate_id !=. & acause == "neo_colorectal"
		replace cancer_procedure = "cystectomies" if procedure_rate_id !=. & acause == "neo_bladder" 

		generate to_adjust = 1 if cancer_procedure != ""  & !inlist(acause, "neo_cervical", "neo_prostate")
	
	// Save
		keep acause cause_id sex model yld_age_start yld_age_end mi_cause_name CoD_model cancer_procedure procedure_proportion_id procedure_rate_id to_adjust
		order acause cause_id sex model yld_age_start yld_age_end mi_cause_name CoD_model cancer_procedure procedure_proportion_id procedure_rate_id to_adjust
		sort acause sex
		save "$parameters_folder/causes.dta", replace
		save "$long_term_copy_parameters/causes.dta", replace

	// save copy to facilitate format of mi boundaries
		keep if model == 1
		keep acause mi_cause_name
		duplicates drop
		tempfile mi_names
		save `mi_names', replace

** *************************************************************************************************************
** MI Boundaries
** *************************************************************************************************************
// Import mi boundaries and save
import excel using "$j/WORK/07_registry/cancer/03_models/01_mi_ratio/00_documentation/MI lower bound/MI lower bound.xlsx", firstrow sheet("MI lower bound") clear

// format
rename (mi_lower_bound_developed mi_lower_bound_developing) (mi_lower_bound1 mi_lower_bound0)
keep acause mi_lower_bound*
reshape long mi_lower_bound, i(acause) j(developed)
rename developed lower_bound_group

// add mi_cause_name to faciitate merge during mi formatting
merge m:1 acause using `mi_names', keep(1 3) assert(2 3) nogen

// Save
save "$parameters_folder/mi_range.dta", replace
save "$long_term_copy_parameters/mi_range.dta", replace

** *************************************************************************************************************
** END of generate_parameters
** *************************************************************************************************************
