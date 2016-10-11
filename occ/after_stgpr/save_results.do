*Save results on epi database

**housekeeping
clear all
set more off
set maxvar 32000

**set directories
	if c(os) == "Windows"		 {
		global j "J:"
		set mem 1g
		}
	
	if c(os) == "Unix"		 {
		global j "/home/j"
		set max_memory 1600g, permanently
		set odbcmgr unixodbc
		}


program define parse_syntax
	syntax, model(int) description(string) exposure(string) [group(string)]

	global model `model'
	global description `description'
	global exposure `exposure'
	global group `group'

	do /home/j/WORK/10_gbd/00_library/functions/save_results.do
	save_results, modelable_entity_id(`model') description(`description') in_dir(/ihme/scratch/users/strUser/`exposure'/`group'/) metrics(proportion) risk_type(exp) mark_best(yes)

end

parse_syntax, `0'



