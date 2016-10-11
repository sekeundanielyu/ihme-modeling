/*
AUTHOR: Andrea Stewart

DATE: 27 Jan 2014

PURPOSE: transform.
*/

capture program drop dismod_ecodes
program define dismod_ecodes
	version 13
	syntax
	
	** as long as this stays in the same folder as Ian's load_params file we can use his list of e-codes
	load_params
	** add on the parent causes
	local e_codes inj_homicide inj_mech inj_trans_road inj_animal ${nonshock_e_codes}
	** remove the proportion models
	foreach model in inj_war inj_disaster {
		local e_codes = subinstr("`e_codes'", "`model'", "", .)
	}
	
	global dismod_e_codes `e_codes'
	
	
	end
	
	