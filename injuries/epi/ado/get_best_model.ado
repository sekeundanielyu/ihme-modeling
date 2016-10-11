
// PURPOSE: Load the results of the best dismod model for a sequela given the sequela name, iso3 sex and year


capture program drop get_best_model
program define get_best_model
	version 13
	syntax , draws_dir(string) acause(string) healthstate(string) grouping(string) parameter(string) location(string) sex(string) year(string)
	
	if c(os) == "Unix" {
		set odbcmgr unixodbc
	}	
	
	** identify the best model for this sequela as it is marked in the "model versions" table on the SQL database
	odbc load, exec("select model_version_id,sequela_id,acause from model_versions left join v_sequelae using (sequela_id) where acause='`acause'' and is_best=1") dsn(epi) clear
	local model=model_version_id in 1
	** in case you need this id later in your code, we are storing it as a global here
	global `acause'_mod_id = `model'
		
	** grab the dismod results for this model
	if "`grouping'" == " " local grouping "cases"
	if "`healthstate'" == " " local healthstate "_parent"

	
	capture insheet using "`draws_dir'/WORK/04_epi/02_models/02_data/`acause'/`grouping'/`healthstate'/`model'/draws/`parameter'_`location'_`year'_`sex'.csv", comma names clear
	if _rc {
		display "The draws for this model (`acause' model `model') were not saved"
		di "return code: " _rc
	}
	
	end
	
	
	