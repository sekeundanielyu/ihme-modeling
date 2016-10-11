
** Description: combining codem deaths and nbr deaths


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
	
	local acause varicella
	local custom_version v18

	
// Make folders on cluster
		capture mkdir "/ihme/codem/data/`acause'/`custom_version'"
		
// Getting codem deaths for data rich countries 
	
		use "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/temp/varicella_69107.dta", clear
		append using "$prefix/WORK/04_epi/01_database/02_data/`acause'/GBD2015/temp/varicella_69110.dta"
		drop envelope pop measure_id model_version
		tempfile data_rich
		save `data_rich', replace
		
	    keep location_id year_id
		duplicates drop location_id year_id, force
		gen replace=1
		tempfile replace
		save `replace', replace
		
//	Combining nhm deaths and codem deaths (the combined results will go into codcorrect)

    // get nbr death draws
	insheet using /ihme/codem/data/`acause'/`custom_version'/draws/death_draws.csv, comma names clear
	// drop data rich countries
	merge m:1 location_id year_id using `replace', nogen
	drop if replace==1
    drop replace 
	
    append using `data_rich'
	
	outsheet using /ihme/codem/data/`acause'/`custom_version'/death_draws.csv, comma names replace

// save_results

do /home/j/WORK/10_gbd/00_library/functions/save_results.do
save_results, cause_id(342) description(varicella nbr & codem combined) mark_best(no) in_dir(/ihme/codem/data/`acause'/`custom_version')


