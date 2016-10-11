
insheet using "tetanus_impairment.csv", comma names clear

keep if severity=="mod_sev"

metaprop num denom, random ftt cimethod(exact)
 
insheet using "tetanus_impairment.csv", comma names clear

keep if severity=="mild"

metaprop num denom, random ftt cimethod(exact)
