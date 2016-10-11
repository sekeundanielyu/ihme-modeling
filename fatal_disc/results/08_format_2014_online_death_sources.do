// Purpose: Prep online death sources found for PSE, AND, ARE, MHL, and QAT


*******************************************************************************
** SET-UP
*******************************************************************************
	clear all
	cap restore not
	set more off

	if c(os) == "Windows" {
		global prefix ""
	}
	else if c(os) == "Unix" {
		global prefix ""
	}

// set directories
	global datadir ""

local indir ""
local outdir ""
local date = c(current_date)

	do "create_connection_string.ado"
	create_connection_string
	local conn_string `r(conn_string)'
	odbc load, clear `conn_string' exec("SELECT ihme_loc_id, local_id FROM shared.location_hierarchy_history WHERE location_set_version_id = 11")
	
	tempfile old_sub_codes
	save `old_sub_codes', replace


** PSE
	insheet using "pse_death_count_investigation.csv", clear names
	
	** reshape so that we can get the average, min, and max for each year
	reshape long year_, i(source website table comments nid) j(year)
	rename year_ war_best
	
	drop source website table comments
	
	** get minimum and maximum values for each year
	bysort year: egen war_deaths_high = max(war_best)
	bysort year: egen war_deaths_low = min(war_best)
	
	** get average value for each year
	bysort year: egen war_deaths_best = mean(war_best)
	
	drop war_best
	contract year war_deaths_best war_deaths_low war_deaths_high
	drop _freq
	
	** if there's only one estimate, we don't want to make the upper and lower bounds equal to that one estimate;
	** that would incorrectly assume we're totally confident in that estimate
	gen dropconfidence = 1 if war_deaths_best == war_deaths_low & war_deaths_best == war_deaths_high
	foreach var of varlist war_deaths_low war_deaths_high {
		replace `var' = . if dropconfidence == 1
	}
		drop dropconfidence
	generate iso3 = "PSE"
	
	gen NID = 253026
	
	tempfile pse
	save `pse', replace
	
* Andorra, United Arab Emirates, Marshall Islands, and Qatar
local countries1 = "AND ARE MHL QAT"
	tempfile and_are_mhl_qat
	foreach country of local countries1 {
		import excel "and_are_mhl_qat_death_count_investigation.xlsx", firstrow clear sheet( "`country'")
		keep if type == "Conflict"
		count
		if `r(N)' > 0 {
			
			* format
			reshape long year_, i(source website type table_number_or_text_section comments) j(year)
			rename year_ war_best
			drop source website type table_number_or_text_section comments
			
			* get minimum and maximum values for each year (confidence intervals)
			bysort year: egen war_deaths_high = max(war_best)
			bysort year: egen war_deaths_low = min(war_best)
			
			* get average value for each year
			bysort year: egen war_deaths_best = mean(war_best)
			
			drop war_best
			contract year war_deaths_best war_deaths_low war_deaths_high
			drop _freq
			
			* if there's only one estimate, we don't want to make the upper and lower bounds equal to that one estimate;
			* that would incorrectly assume we're totally confident in that estimate
			gen dropconfidence = 1 if war_deaths_best == war_deaths_low & war_deaths_best == war_deaths_high
			foreach var of varlist war_deaths_low war_deaths_high {
				replace `var' = . if dropconfidence == 1
			}
			drop dropconfidence
			generate iso3 = "`country'"
			
			gen NID = 666662
			
			cap append using `and_are_mhl_qat'
			save `and_are_mhl_qat', replace
		}
	
	}

* Philippines conflict
import excel "phl_death_count_investigation.xlsx", clear sheet( "Sheet1") firstrow
	keep if type == "conflict"
	
	foreach var of varlist year_* {
		destring `var', replace
	}
	
	reshape long year_, i(type Cause Specificname source website table_number_or_text_section comments) j(year)
	rename year_ war_best
	drop type Cause Specificname source website table_number_or_text_section comments
	
	* get minimum and maximum values for each year (confidence intervals)
	bysort year: egen war_deaths_high = max(war_best)
	bysort year: egen war_deaths_low = min(war_best)
	
	* get average value for each year
	bysort year: egen war_deaths_best = mean(war_best)
	
	drop war_best
	contract year war_deaths_best war_deaths_low war_deaths_high
	drop _freq
	
	* if there's only one estimate, we don't want to make the upper and lower bounds equal to that one estimate;
	* that would incorrectly assume we're totally confident in that estimate
	gen dropconfidence = 1 if war_deaths_best == war_deaths_low & war_deaths_best == war_deaths_high
	foreach var of varlist war_deaths_low war_deaths_high {
		replace `var' = . if dropconfidence == 1
	}
	drop dropconfidence
	generate iso3 = "PHL"
	
	gen NID = 253027
	
	tempfile phl
	save `phl', replace
	
* SYR 2011-2013
	* this dataset was used temporarily- from wikipedia
	* insheet using "syr_2011to2013_conflict_deaths.csv", clear
	* rename deaths war_deaths_best
	* keep iso3 year war_deaths_best
	
	import excel "Syria_death_count.xlsx", clear sheet( "Syria_strUser") firstrow
	foreach var of varlist BattleName EventDate {
		tostring `var', replace
	}
	tempfile syr
	save `syr', replace
	
	import excel "Syria_death_count.xlsx", clear sheet( "Syria_strUser") firstrow
	tostring Content, replace
	append using `syr'
	rename ISO iso3
	replace duplicates = 1 if year_start >= 2011
		replace duplicates = 2 if duplicates != . & year_start == 1982
	
	keep iso3 year_start year_end numberofdeaths lowestimate highestimate duplicates
		
		* take into account that some estimates are for multiple years
		preserve
			keep if duplicates != .
			generate expand_multiplier = year_end - year_start + 1
			expand expand_multiplier
			sort iso3 year_start year_end numberofdeaths
			replace numberofdeaths = 20000 if year_start == 1982 & year_end == 1982
			bysort iso3 year_start year_end numberofdeaths: gen nn = _n
			replace year_start = year_start + nn - 1 if expand_multiplier > 1
			
			foreach deathestimate of varlist numberofdeaths lowestimate highestimate {
				replace `deathestimate' = `deathestimate'/expand_multiplier
			}
		
			* get just one number per year:
				* get minimum and maximum values for each year (confidence intervals)
				drop year_end
				rename year_start year
				bysort year: egen war_deaths_high = max(numberofdeaths)
				bysort year: egen war_deaths_high2 = max(highestimate)
					replace war_deaths_high = war_deaths_high2 if war_deaths_high2 > war_deaths_high & war_deaths_high2 != .
				bysort year: egen war_deaths_low = min(numberofdeaths)
				bysort year: egen war_deaths_low2 = min(lowestimate)
					replace war_deaths_low = war_deaths_low2 if war_deaths_low2 < war_deaths_low & war_deaths_low2 != .
				
				* get average value for each year
				bysort year: egen war_deaths_best = mean(numberofdeaths)

				contract year war_deaths_best war_deaths_low war_deaths_high
				drop _freq
				
				* if there's only one estimate, we don't want to make the upper and lower bounds equal to that one estimate;
				* that would incorrectly assume we're totally confident in that estimate
				gen dropconfidence = 1 if war_deaths_best == war_deaths_low & war_deaths_best == war_deaths_high
				foreach var of varlist war_deaths_low war_deaths_high {
					replace `var' = . if dropconfidence == 1
				}
				drop dropconfidence
				tempfile duplicate_estimates_fixed
				generate iso3 = "SYR"
				save `duplicate_estimates_fixed', replace
			restore
			
		* add up the estiamtes for years that have 
			drop if duplicates != .
			rename (year_start numberofdeaths lowestimate highestimate) (year war_deaths_best war_deaths_low war_deaths_high)
			keep iso3 year war_deaths_best war_deaths_low war_deaths_high
			append using `duplicate_estimates_fixed'
			keep if iso3 == "SYR"
			collapse (sum) war_deaths_best war_deaths_low war_deaths_high, by(iso3 year)
			
			foreach var of varlist war_deaths_low war_deaths_high {
				replace `var' = . if `var' == 0
			}
			
			gen NID = 253028
			
			save `syr', replace
			
* LBY 2011- 2013	
	import excel "Libya_2011-2013_IISS_Armed_Conflict_Data.xlsx", firstrow clear sheet( "Libya")
	drop Source Duplicate
	rename (ISO Year Best Low High) (iso3 year war_deaths_best war_deaths_low war_deaths_high)
	drop if iso3 == ""
	tempfile lby
	save `lby', replace
	
* Arab countries
	* bring in the data
	clear
	tempfile arabcountries
	local sheet1list = "Libya Yemen Bahrain" 
	foreach sheet of local sheet1list {
		di "`sheet'"
		import excel "middle_east_death_count_investigation1.xlsx", clear firstrow sheet( "`sheet'")
		drop if ISO == ""
		keep if inlist(ISO, "LBY", "YEM", "BHR", "LBN")
		cap tostring BattleName Content Ourpurpose, replace 
		* to make duplicate unique between the 2 investiagtions
		replace Duplicate = Duplicate + 100
		if "`sheet'" != "Libya" {
			append using `arabcountries'
		}
		
		save `arabcountries', replace
	}
	
	import excel using "middle_east_death_count_investigation2.xlsx", clear firstrow sheet( "Lebanon_year_range")
	tostring Content Ourpurpose, replace
	* to make duplicate unique between the 2 investiagtions
	replace Duplicate = Duplicate + 200
	append using `arabcountries'
		
		* format the data
		keep NID ISO_location_of_death year* Duplicate numberofdeaths lowestimate highestimate
		drop if numberofdeaths == . & lowestimate == . & highestimate == .
		compress
		
		* get best/low/high estimates for duplicated events
		preserve
		keep if Duplicate != .
		
			* get average, minimum and maximum values.  and only want one of each event
			rename (lowestimate highestimate) (numberlowestimate numberhighestimate)
			bysort ISO year_start year_end Duplicate: gen nn = _n
			reshape long number, i(ISO year_start year_end Duplicate nn) j(deathcounttype, string)
		
			bysort ISO year_start year_end Duplicate: egen numberofdeaths = mean(number)
			bysort ISO year_start year_end Duplicate: egen lowestimate = min(number)
			bysort ISO year_start year_end Duplicate: egen highestimate = max(number)
			drop nn deathcounttype number
			duplicates drop
		
		tempfile arabduplicates
		save `arabduplicates', replace
		restore
		drop if Duplicate != . 
		append using `arabduplicates'
		
		* if number of deaths is missing, replace it with the average of low and high.  if we just have a low estimate, replace it with that
		replace numberofdeaths = lowestimate if numberofdeaths == . & lowestimate != . & highestimate == .
		replace numberofdeaths = (lowestimate[_n] + highestimate[_n])/2 if numberofdeaths == . & lowestimate != . & highestimate != .
		assert numberofdeaths != .
		
		* logic check: is the high estimate always higher than the best estimate and low estimate? is the best estimate always higher than the low estimate?
		count if lowestimate != . & numberofdeaths < lowestimate
		assert `r(N)' == 0
		count if highestimate != . & highestimate < numberofdeaths
		assert `r(N)' == 0
		count if highestimate != . & lowestimate != . & highestimate < lowestimate
		assert `r(N)' == 0
		
		* deal with multi-year conflicts by distributing the deaths evenly across the years
		generate eventid = _n
		generate year_multiplier = year_end - year_start + 1
		expand year_multiplier if year_multiplier != 1
		foreach deathsvar of varlist numberofdeaths low high {
			replace `deathsvar' = `deathsvar'/year_multiplier
		}
		bysort eventid: generate yearnumber = _n - 1
		replace year_start = year_start + yearnumber if year_multiplier != 1
		drop year_end year_multiplier yearnumber eventid
		rename year_start year
		
		* get number of deaths in a year by summing it up; we know that there aren't duplicates because we took care of that
		replace lowestimate = numberofdeaths if lowestimate == .
		replace highestimate = numberofdeaths if highestimate == .
		
		collapse (sum) numberofdeaths lowestimate highestimate, by (ISO year)
		
			* i don't believe estimates confidence intervals of 0; if they are, replace them
			generate conf_int_diff = highestimate - lowestimate
			foreach deathvar of varlist lowestimate highestimate {
				replace `deathvar' = . if conf_int_diff == 0
			}
			drop conf_int_diff
			
			* logic check again: is the high estimate always higher than the best estimate and low estimate? is the best estimate always higher than the low estimate?
			count if lowestimate != . & numberofdeaths < lowestimate
			assert `r(N)' == 0
			count if highestimate != . & highestimate < numberofdeaths
			assert `r(N)' == 0
			count if highestimate != . & lowestimate != . & highestimate < lowestimate
			assert `r(N)' == 0
			
		* some formatting 
		rename (numberofdeaths lowestimate highestimate ISO) (war_deaths_best war_deaths_low war_deaths_high iso3)
		
		gen NID = 666665
		
		tempfile arabcountriesfinal
		save `arabcountriesfinal', replace
		
		
	
// clean up
	generate year = 2015
	rename nid NID		// rename so it matches the nid variable in the Lybia data
	egen unique_id = fill(1/38)

	cap replace high = "2000" if high == "2,000"
	cap destring high, replace
	
	bysort unique_id iso3: egen war_deaths_high = max(high)
	bysort unique_id iso3: egen war_deaths_low = min(low)
	bysort unique_id iso3: egen war_deaths_best = mean(best)
	
	replace war_deaths_high = war_deaths_best if high == .
	replace war_deaths_low = war_deaths_best if low == .

	keep iso3 year war* NID
	
	tempfile 2015wardeaths
	save `2015wardeaths', replace

	// Syria 2015 war conflicts
	import excel "supplemental_syria_fatalities_2015.xlsx", clear cellrange(A2:J33) firstrow sheet("fatalities_year_split")

	keep if NID == 225048
	
	gen war_deaths_best = year_2015
	gen iso3 = "SYR"
	gen year = 2015
	keep NID iso3 year war_deaths_best
	gen war_deaths_high = .
	gen war_deaths_low = .
	
	tempfile 2015syria
	save `2015syria', replace
	
	
	// News research
	import excel "strUser_research.xlsx", clear firstrow
	
	keep iso3 location year_start year_end deaths_total Lowerboundifgiven Upperboundifgiven nid
	rename nid NID
	
	rename deaths_total war_deaths_best
	rename Lowerbound war_deaths_low
	rename Upperbound war_deaths_high
	
	replace year_start = year_end if year_start == .
	
	replace iso3 = iso3 + "_35640" if location == "Mandera"
	replace iso3 = iso3 + "_35623" if location == "Garissa"
	replace iso3 = iso3 + "_44551" if location == "'Asir"
	replace iso3 = iso3 + "_44553" if location == "Eastern Province"
	replace iso3 = iso3 + "_44552" if location == "Najran"
	replace iso3 = iso3 + "_44548" if location == "Northern Borders"
	replace iso3 = iso3 + "_44543" if location == "Riyadh"
	replace iso3 = iso3 + "_43873" if location == "Arunachal Pradesh, Rural"
	replace iso3 = iso3 + "_43880" if location == "Delhi, Urban"
	replace iso3 = iso3 + "_43928" if location == "Manipur, Rural"
	replace iso3 = iso3 + "_43931" if location == "Nagaland, Rural"
	replace iso3 = iso3 + "_35437" if location == "Kanagawa"
	
	
	// Collapse all events together by start & end year, then distribute into single years
	collapse (sum) war_deaths*, by(iso3 year_start year_end NID) fast
	
	gen year = year_end
	keep if year == 2015
	
	replace war_deaths_low = . if war_deaths_low == 0
	replace war_deaths_high = . if war_deaths_high == 0
	
	tempfile strUser_research
	save `strUser_research', replace
	
	
* bring all together
	clear
	append using `pse' 
	append using `and_are_mhl_qat' 
	append using `phl' 
	append using `syr' 
	append using `lby' 
	append using `2015wardeaths'
	append using `2015syria'
	append using `arabcountriesfinal'
	append using `strUser_research'

	* final formatting
	gen dataset_ind = 100
		
	* drop any years beyond the current year
	local date = c(current_date)
	gen date = substr( "`date'",8,4)
	destring date, replace

	drop date
	
	* drop if missing data for "best" -- didn't find estimates for these years
	drop if war_deaths_best == .
	tempfile online2014data
	save `online2014data', replace

	
drop I
gen cause = "war"


drop if year<1950

// Some oddities and assertions
assert war_deaths_best==0 if year==.
drop if year==.
assert year!=.

assert war_deaths_low<=war_deaths_best if war_deaths_low != .
assert war_deaths_best<=war_deaths_high if war_deaths_high != .

assert NID != .
assert cause != ""
assert dataset_ind==100
	
save "online_supplement_2015.dta", replace
save "online_supplement_2015_`date'.dta", replace
	







