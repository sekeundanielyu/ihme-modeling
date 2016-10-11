
// PURPOSE: Load parameters for hierarchies


capture program drop hierarchy_params
program define hierarchy_params
	version 13
	syntax, prefix(string) repo(string) steps_dir(string)
	

** get N-code names
insheet using "`repo'/ncode_names.csv", comma names clear
// import excel group=C ncode=D name=E using "`prefix'/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet("sequelae") clear allstring
// keep if group == "ncodes"
assert _N == 48
drop if n_code == "N29"
levelsof n_code if regexm(n_code,"N"), clean local(ncodes)
global ncodes `ncodes' N99	

	
** N-codes that expert opinion (Theo, Juanita) says should only be inpatient
global hosp_only N1 N2 N4 N5 N9 N10 N28 N33 N34 N37
	
** ncodes that we are claiming have 100% long-term outcomes and can take out of regression. all_lt_hosp == 9
** indicates both inpatient and "other" cases are set to 100% long-term. all_ lt_hosp == 1 indicates inpatient only.
global all_lt 		N1	N2	N4	N5	N7	N3	N6
global all_lt_sev	9	9	9	9	9	1	1

** codes leading to no long-term injury. Setting the effect of these to 0
global no_lt 		GS958	GS809	N30	N31	N32	N47
global no_lt_sev	9		9		9	9	9	9	

global prepped_filepath "`prefix'/Project/GBD/Systematic Reviews/ANALYSES/INJURIES/Clean Code/data/prepped/pooled_adjusted.dta"

end


