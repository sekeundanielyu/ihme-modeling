********************************************************
** Description:
** Combines the reshaped population and death data into one file with one observation
** for each census pair. It formats the reshaped data so that each observation has
** the population at the first census, the population at the second census and the average annual deaths.
**
********************************************************

** Set up Stata

cap program drop combine_reshaped
program define combine_reshaped

clear
set more off
set mem 500m
set maxvar 32000
pause on

********************************************************
** Set parameters

syntax, popdata(string) deathsdata(string) saveas(string)

********************************************************
** Analysis code

use "`popdata'", clear
count 
if (`r(N)'==0) { 
	local pop_count = 0 
} 
else { 
	count if source_type != "NA"
	local pop_count = `r(N)'
}

use "`deathsdata'", clear
count
if (`r(N)'==0) { 
	local death_count = 0 
} 
else { 
	count if source_type != "NA"
	local death_count = `r(N)'
}

if (`pop_count' > 0 & `death_count' > 0) { 
	
	levelsof id if regexm(source_type, "VR")==1 | regexm(source_type, "SURVEY") | regexm(source_type,"survey") | source_type == "UNKNOWN", local(source_types_loc)
	tempfile vrdata
	save `vrdata', replace

	** Load the pop data and extra copies of the census data to match with other national-level sources 
	if "`iso3'" != "all" use "`popdata'" if strpos(ihme_loc_id,"`iso3'") != 0, clear
	else use "`popdata'", clear
	tempfile master
	save `master'
	tempfile master_new
	save `master_new'
	
	clear 
	tempfile new_pop
	save `new_pop', replace emptyok
	
	foreach stl of local source_types_loc {
		di in red "Processing `stl'"
		use `master', clear
		// Updated coding to get the string positions correct given the flexibility required with ihme_loc_id
		keep if source_type=="CENSUS" & ihme_loc_id == substr("`stl'",1,strpos("`stl'", "&&")-1) & sex == substr("`stl'", strpos("`stl'", "&&")+2, strpos("`stl'", "@@") - strpos("`stl'", "&&")-2)
		replace id = "`stl'"
		save `new_pop', replace
		use `master_new', clear
		append using `new_pop'
		save `master_new', replace
	}
	use `master_new', clear
	drop source_type sex

	merge 1:1 id pop_years using "`vrdata'"
	drop _merge
	drop if deaths_years == "NA"

	quietly {

	forvalues j = 0/100 {
		rename agegroup`j' agegroupv_`j'
	}

	g allagegroups1 = ""
	g allagegroups2 = ""
	g allagegroupsv = ""
	forvalues j = 0/100 {
		// Getting a comma separated list of the different age groups involved in each separate set of data
		replace allagegroups1 = allagegroups1 + "," + string(agegroup1_`j') if agegroup1_`j' ~= .	
		replace allagegroups2 = allagegroups2 + "," + string(agegroup2_`j') if agegroup2_`j' ~= .	
		replace allagegroupsv = allagegroupsv + "," + string(agegroupv_`j') if agegroupv_`j' ~= .	
	}

	replace allagegroups1 = allagegroups1 + ","
	replace allagegroups2 = allagegroups2 + ","
	replace allagegroupsv = allagegroupsv + ","

	g newagegroups = ""
	// Get a list of the age groups that are common among all three sources of data
	forvalues j = 0/100 {
		replace newagegroups = newagegroups + ",`j'" if strpos(allagegroups1,",`j',") ~= 0 & strpos(allagegroups2,",`j',") ~= 0 & strpos(allagegroupsv,",`j',") ~= 0
	}
	replace newagegroups = newagegroups + ","

	replace newagegroups = subinstr(newagegroups,",0,1,5,",",0,5,",1)

	drop agegroup* allagegroups*

	forvalues j = 0/100 {
		g agegroup`j' = .
	}

	
	// Generate new age groups where each age group number corresponds to the number order it is in the age hierarchy chain
	// Allows for up to 100 age groups. 
	// The value stored in agegroup is the age for each age cutpoint, so to speak
	gen count = 0
	forvalues j = 0/100 {
		forvalues k = 0/100 {
			replace agegroup`k' = `j' if strpos(newagegroups,",`j',") ~= 0 & count == `k'
		}
		replace count = count + 1 if strpos(newagegroups,",`j',") ~= 0
	}

	drop newagegroups

	forvalues j = 0/100 {
		g newpop1_`j' = .
		g newpop2_`j' = .
		g newdeaths_`j' = .
	}

	}

	// Loop this calculation of new pop/deaths -- we are using the original values to get the agerange-specific changes
	foreach iteration in pop1 pop2 deaths {
	forvalues j = 0/50 {
		di "`j'"
		quietly {
		local jplus = `j'+1

		levelsof agegroup`j', local(ag1)
		levelsof agegroup`jplus', local(ag2)
		
		foreach a1 of local ag1 {
			foreach a2 of local ag2 {
				di "A1 AND A2 `a1' `a2'"
				if(`a1' < `a2') {
					// Take the population or deaths of the beginning part of age group minus that of the population or deaths at the end of the age group
					local endloc = `a2' - 1
					if "`iteration'" != "deaths" local prefix "_" // Toggle by differential variable naming
					else local prefix ""
					egen temp`a1'`a2' = rowtotal(`iteration'`prefix'`a1'- `iteration'`prefix'`endloc')
					replace new`iteration'_`j' = temp`a1'`a2' if agegroup`j' == `a1' & agegroup`jplus' == `a2' & new`iteration'_`j' == .
					drop temp`a1'`a2'
				}			
			}
			// Aggregate all populations/deaths together to get the population/deaths from beginning to end if it's an open-ended range
			egen temp`a1'`a2' = rowtotal(`iteration'`prefix'`a1'-`iteration'`prefix'100) 
			replace new`iteration'_`j' = temp`a1'`a2' if agegroup`j' == `a1' & agegroup`jplus' == . & new`iteration'_`j' == .
			drop temp`a1'`a2'
		}
		}
	}
	}

	drop pop1* pop2* deaths0-deaths100

	// Format into the variable names we will use further on
	forvalues j = 0/100 {
		rename newpop1_`j' c1_`j'
		rename newpop2_`j' c2_`j'
		rename newdeaths_`j' vr_`j'		
	}


	g year1 = substr(pop_years,strpos(pop_years," ")-4,4)
	g year2 = substr(pop_years,-4,.)

	g month1 = substr(pop_years,1,strpos(pop_years,"/")-1)
	g month2 = substr(substr(pop_years,strpos(pop_years," "),.),1,strpos(substr(pop_years,strpos(pop_years," "),.),"/")-1)

	g day1 = substr(substr(pop_years,strpos(pop_years,"/")+1,.),1,strpos(substr(pop_years,strpos(pop_years,"/")+1,.),"/")-1)
	g day2 = substr(substr(substr(pop_years,strpos(pop_years," "),.),strpos(substr(pop_years,strpos(pop_years," "),.),"/")+1,.),1,strpos(substr(substr(pop_years,strpos(pop_years," "),.),strpos(substr(pop_years,strpos(pop_years," "),.),"/")+1,.),"/")-1)

	destring year1, replace
	destring year2, replace
	destring month1, replace
	destring month2, replace
	destring day1, replace
	destring day2, replace

	g date1 = year1 + (month1/12) + (day1/365)
	g date2 = year2 + (month2/12) + (day2/365)

	g time = date2 - date1

	g numofvr = wordcount(deaths_years)
	g vryear = deaths_years if numofvr == 1
	destring vryear, replace

	g popyearhat = 1
	forvalues j = 0/100 {
		// Popyearhat gets the projected population in the VR year, presuming a straight-line interpolation in population
		// This interpolates forwards from the beg year if VR is closer to that, and backwards from the end year if VR is closer to that.
		replace popyearhat = c1_`j'*exp((vryear-date1)*(1/time)*log(c2_`j'/c1_`j')) if numofvr == 1 & (vryear ~= year1 & vryear ~= year2 & vryear ~= (year2-1)) & (vryear-date1) <= (date2-vryear)
		replace popyearhat = c2_`j'*exp(-1*(date2-vryear)*(1/time)*log(c2_`j'/c1_`j')) if numofvr == 1 & (vryear ~= year1 & vryear ~= year2 & vryear ~= (year2-1)) & (vryear-date1) > (date2-vryear)
		
		// This treats new deaths differently depending on when the vr was taken in relation to the census years 
		// Denominator is the census of the year that VR matches, or popyearhat if it's in between the two dates
		replace vr_`j' = (vr_`j'/c2_`j')*sqrt(c1_`j'*c2_`j') if numofvr == 1 & (vryear == year2 | vryear == (year2-1))
		replace vr_`j' = (vr_`j'/c1_`j')*sqrt(c1_`j'*c2_`j') if numofvr== 1 & (vryear == year1)
		replace vr_`j' = (vr_`j'/popyearhat)*sqrt(c1_`j'*c2_`j') if numofvr == 1 & (vryear ~= year1 & vryear ~= year2 & vryear ~= (year2-1)) & (vryear-date1) <= (date2-vryear)
	}

	drop year1 year2 month1 month2 day1 day2 date1 date2 numofvr vryear popyearhat

	duplicates drop *, force
	duplicates drop ihme_loc_id sex pop_years source_type, force
	replace ihme_loc_id = ihme_loc_id + "&&" + source_type 

	save "`saveas'", replace
} 
else { 
	clear
	gen temp = . 
	save "`saveas'", replace 
}

di "DONE"

end
