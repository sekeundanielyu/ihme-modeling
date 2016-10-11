				
** Purpose: Specially handles india data to assign rural/urban status 					
** *******************************************************************

// make map of new location_ids
	preserve
		use "$j/WORK/07_registry/cancer/00_common/data/location_ids.dta", clear 
		keep if iso3 == "IND"
		keep subdiv location_id 
		keep if subdiv != "" & subdiv != "."
		replace subdiv = subinstr(subdiv, ",", "", .)
		duplicates drop
		tempfile new_lids
		save `new_lids', replace
	restore

// make urbanicity weights
	preserve
		use "$j/WORK/07_registry/cancer/01_inputs/sources/IND/00_IND_documentation/IND_registry_locations.dta", clear
		replace preferred_registry = registry  if preferred_registry == ""
		keep subdiv location_id preferred fraction_urban
		duplicates drop
		rename preferred_registry registry
		replace fraction_urban = .5 if fraction_urban == . 
		gen fraction_rural = 1- fraction_urban
		reshape long fraction, i(location subdiv registry) j(urbanicity) string
		tempfile india_fractions
		save `india_fractions', replace
	restore

// merge with dataset
	preserve
		keep if iso3 == "IND" & !regexm(subdiv, "Urban") & !regexm(subdiv, "Rural")
		// generate obs number for later comparison
			gen obs = _n
		// join data with weights (this will create two instances of each datapoint, each joined by a different weight)
			joinby subdiv registry using `india_fractions'
		// recalculate numbers
			drop cases1 pop1
			foreach m of varlist cases* pop* {
				gen orig_`m' = `m'
				recast double `m'
				replace `m' = fraction*`m'
				bysort obs: egen test_new_`m' = total(`m')
				bysort obs: egen test_old_`m' = mean(orig_`m')
				gen test = abs(test_new_`m'/ test_old_`m')
				count if test != . & abs(1 - test) > 0.00005
				if r(N) > 0 BREAK
				drop test* orig_`m'
			}
			egen cases1 = rowtotal(cases*)
			egen pop1 = rowtotal(pop*)
		// correct metadata
			replace subdiv = subdiv +" Urban" if urbanicity == "_urban"
			replace subdiv = subdiv +" Rural" if urbanicity == "_rural"
			drop location_id
			merge m:1 subdiv using `new_lids', keep(1 3) assert(2 3) nogen
			drop fraction urbanicity
			tempfile reaggregated_india_data
			save `reaggregated_india_data', replace
	restore

// Combine with the rest of the data
	drop if iso3 == "IND" & !regexm(subdiv, "Urban") & !regexm(subdiv, "Rural")
	append using `reaggregated_india_data'

** *******************
** End Subroutine
** ******************
