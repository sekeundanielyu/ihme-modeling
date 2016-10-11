

// PURPOSE: Get injuries E-codes, with options to get different lists of E-codes


cap program drop get_ecode_names
program define get_ecode_names
	version 12
	syntax , prefix(string) dimtab(string) detail(string) 
	
	** dimtab should indicate which tab of the dimensions spreadsheet you want ecodes from as they differ- options are sequelae and causes, default is sequelae
	if ("`dimtab'" != "causes") local dimtab "sequelae"
	
	** detail should indicate whether to include broader categories on injuries (e.g. inj_trans_road) that have smaller sub-categories (e.g. inj_trans_road_pedest, etc.), default no, specify yes
	** problem with this is that there are like 4 levels of detail, but they are complicated in that an exhaustive list doesn't exist at more detailed levels, so you'd have to keep e_codes from multpile levels-- if we need this to work we can fix it later (ADD LEVEL OF DETAIL BY EDITING CODE)**************
	if ("`detail'" != "yes") local detail "no"
	
	** load spreadsheet
	if ("`dimtab'" == "causes") {
	import excel group=B e_code=C name=E using "`prefix'/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet("causes") clear 
	drop if _n == 1
	keep if regexm(group,"C")
	}
	else {
	import excel e_code=B name=E using "`prefix'/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet("sequelae") clear
	keep if regexm(e_code,"inj_")
	}
	
end
