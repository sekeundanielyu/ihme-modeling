
** Description: combining codem deaths and nhm deaths


// Settings
			
				clear all
				set mem 5G
				set maxvar 32000

				set more off

			// Define J drive (data) for cluster (UNIX) and Windows (Windows)
				if c(os) == "Unix" {
					global prefix "/home/j"
					set odbcmgr unixodbc
				}
				else if c(os) == "Windows" {
					global prefix "J:"
				}
			
			// Close any open log file
				cap log close
	
// locals
	
	local acause whooping
	local custom_version v8

// Make folders on cluster
		capture mkdir "/ihme/codem/data/`acause'/`custom_version'"
		

// define filepaths
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/"
	cap mkdir "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015//`custom_version'/results"	
	local outdir "$prefix/WORK/04_epi/01_database/02_data//`acause'/GBD2015//`custom_version'/results"


	// Getting codem deaths for data rich countries 
	
		use "$prefix/WORK/04_epi/01_database/02_data/whooping/GBD2015/temp/whooping_74036.dta", clear
		append using "$prefix/WORK/04_epi/01_database/02_data/whooping/GBD2015/temp/whooping_74039.dta"
		drop envelope pop measure_id cause_id model_version
		
		tempfile data_rich
		save `data_rich', replace
		
	    keep location_id year_id
		duplicates drop location_id year_id, force
		gen replace=1
		tempfile replace
		save `replace', replace
		
//	Combining nhm deaths and codem deaths (the combined results will go into codcorrect)

    // get age-sex splitted nhm death draws
	use "$prefix/WORK/04_epi/01_database/02_data/whooping/GBD2015/`custom_version'/results/age_sex_split_files/death_draws.dta", clear
	
	// rename 
    rename sex sex_id
    rename year year_id
	
	// drop data rich countries
	merge m:1 location_id year_id using `replace', nogen
	drop if replace==1
    drop replace 
	

	// Rename draws
		forvalues i = 1/1000 {
			local i1 = `i' - 1
			rename draw_`i' draw_`i1'
		}

   // add age group ids
gen age_group_id=.
replace age_group_id=2 if age==0
replace age_group_id=3 if age>0 & age<0.1
replace age_group_id=4 if age>0.05 & age<1
replace age_group_id=5 if age==1
replace age_group_id=6 if age==5
replace age_group_id=7 if age==10
replace age_group_id=8 if age==15
replace age_group_id=9 if age==20
replace age_group_id=10 if age==25
replace age_group_id=11 if age==30
replace age_group_id=12 if age==35
replace age_group_id=13 if age==40
replace age_group_id=14 if age==45
replace age_group_id=15 if age==50
replace age_group_id=16 if age==55
replace age_group_id=17 if age==60
replace age_group_id=18 if age==65
replace age_group_id=19 if age==70
replace age_group_id=20 if age==75
replace age_group_id=21 if age==80
	
drop if age_group_id<4 | age_group_id>16
drop age

	
append using `data_rich'


// add cause_id
	gen cause_id=339
	
	outsheet using /ihme/codem/data/`acause'/`custom_version'/death_draws.csv, comma names replace

// save results

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(339) description(pertussis natural history model `custom_version') mark_best(no) in_dir(/ihme/codem/data/`acause'/`custom_version')

