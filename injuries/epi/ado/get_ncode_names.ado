
// PURPOSE: Get a map from injuries N-codes to their corresponding names


cap program drop get_ncode_names
program define get_ncode_names
	version 12
	syntax , prefix(string)
	
	import excel n_code=D name=E using "`prefix'/WORK/00_dimensions/00_schema/dimensions.xlsx", sheet("sequelae") clear cellrange(D2)
	keep if regexm(n_code,"^N[0-9]")
	
// Drop unused N-code that remains in the mapping
	drop if n_code == "N29"
	
end
