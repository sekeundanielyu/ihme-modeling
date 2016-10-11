********************************************************
** Description:
** Prepares the death data for the death distribution methods
** by finding the average annual number of deaths between the census pairs

********************************************************

** Set up Stata

cap program drop reshape_deaths
program define reshape_deaths

// quietly {

clear
set mem 500m
set maxvar 32000
set more off

********************************************************
** Set parameters

syntax, popdata(string) data(string) saveas(string) iso3(string)

********************************************************
** Analysis code
local test = 0
if `test' == 1 {
	local popdata "J:\WORK\02_mortality\03_models\ddm\data\temp\d02_reshaped_population_ZWE.dta"
	local data "J:\WORK\02_mortality\03_models\ddm\data\temp\d01_formatted_deaths_ZWE.dta"
	local iso3 "ZWE"
	local saveas "J:\WORK\02_mortality\03_models\ddm\data\temp\d02_reshaped_deaths_ZWE.dta"

}


g temp = .
save "`saveas'", replace

use "`popdata'", clear
local pop_count = _N

use "`data'", clear

** drop household deaths
cap drop if source_type == "HOUSEHOLD" | source_type == "household"
local deaths_count = _N

qui if (`pop_count' != 0 & `deaths_count' != 0) { 

	** Create iso3-sex-source identifier; Find out what sources are present that should be matched with census 
	replace ihme_loc_id = ihme_loc_id + "&&" + sex + "@@" + source_type
	drop sex
	levelsof ihme_loc_id if regexm(source_type, "VR")==1 | regexm(source_type, "SURVEY") | regexm(source_type,"survey") | source_type == "UNKNOWN", local(source_types_loc)
	tempfile deathdata
	save `deathdata', replace

	** Load the pop data and extra copies of the census data to match with other national-level sources 
	if("`iso3'" != "all") use "`popdata'" if ihme_loc_id == "`iso3'", clear
	else use "`popdata'", clear
	replace ihme_loc_id = ihme_loc_id + "&&" + sex + "@@" + source_type

	tempfile master
	save `master'
	tempfile master_new
	save `master_new'
	
	clear 
	tempfile new_pop
	save `new_pop', replace emptyok	

	foreach stl of local source_types_loc {
		tokenize "`stl'", parse("&&") // Grab the country iso3
		use `master', clear
		keep if source_type=="CENSUS" & substr(ihme_loc_id,1,strpos(ihme_loc_id,"&&")-1) == "`1'" & sex == substr("`stl'", strpos("`stl'", "&&")+2, strpos("`stl'", "@@") - strpos("`stl'", "&&")-2)
		replace ihme_loc_id = "`stl'"
		save `new_pop', replace
		use `master_new', clear
		append using `new_pop'
		save `master_new', replace
	}
	use `master_new', clear
	drop sex
	save `master', replace

	clear 
	tempfile beforeshape
	save `beforeshape', emptyok
	tempfile beforefreq
	save `beforefreq', emptyok
	
	** Loop through iso3-sex-sources
	use `master', clear
	levelsof ihme_loc_id, local(ihme_loc_id)
	foreach c of local ihme_loc_id {
		noisily: di "`c'"
		preserve
		keep if ihme_loc_id == "`c'"
		levelsof pop_years, local(c_years)

		foreach cy of local c_years {
			local y1 = substr("`cy'",strpos("`cy'"," ")-4,4)
			local y2 = substr("`cy'",-4,.)

			save `beforeshape', replace

			use `deathdata', clear
			keep if ihme_loc_id == "`c'"

			keep if year >= `y1' & year <= `y2'

			if(_N > 1) {

				** First take only the death years with the most frequently occuring source type
				save `beforefreq', replace
				capture drop _freq
				contract source_type
				gsort - _freq
				levelsof source_type if _n == 1, clean local(sdloc)
				use `beforefreq', clear
				keep if source_type == "`sdloc'"
			
				** Then within that source type take only those years from the most frequently occuring source 
				** with the exception of China data from the Demographic Yearbook 
                ** (and CHN provinces) - AS, 1 August 2013
				** We do this because differing age groups among sources created problems
				save `beforefreq', replace
				capture drop _freq
				contract deaths_source
				gsort - _freq
				levelsof deaths_source if _n == 1, clean local(vrsource)
				use `beforefreq', clear
				
				if((strpos("`c'","CHNDYB") == 0) | (strpos("`c'","X") != 1)) {	
					keep if deaths_source == "`vrsource'"
				}   
			}
			if(_N == 0) {
				drop *
				set obs 1
				forvalues j = 0/100 {
					g deaths`j' = .
					g agegroup`j' = .			
				}		
				g deaths_years = "NA"
				g ihme_loc_id = "`c'"
				g pop_years = "`cy'"
				g deaths_source = "NA"
				g deaths_footnote = "NA"
				g source_type = "NA"
				g deaths_nid = "NA"
				g sex = substr("`c'",strpos("`c'","&&")+2,strpos("`c'","@@")-strpos("`c'","&&")-2)

			}
			else if(_N == 1) {
				levelsof year, clean local(vr_years)	
				drop year

				g sex = substr("`c'",strpos("`c'","&&")+2,strpos("`c'","@@")-strpos("`c'","&&")-2)
				g pop_years = "`cy'"
				g deaths_years = "`vr_years'"		
			}
			else {		
				
				** Compile the sources and footnotes for each year 
				local count_y = 0
				levelsof year, clean local(vr_years)
				levelsof source_type, clean local(stloc)
				
				foreach vary of local vr_years {
					levelsof deaths_source if year == `vary', clean local(vrsource`count_y')	
					levelsof deaths_footnote if year == `vary', clean local(fn`count_y')
					levelsof deaths_nid if year == `vary', clean local(nid`count_y')
					local count_y = `count_y'+1
				}
				local count_y = `count_y'-1
				** Note that this average annual deaths when the censuses may not be an integer number of years apart
			
				** Determine a kind of least common denominator, i.e. use the coarsest age group from age groups of death 
				** and population data for the census pair and average annual deaths

				g allagegroups = ""
				forvalues q = 0/100 {
					replace allagegroups = allagegroups + "," + string(agegroup`q') if agegroup`q' ~= .
				}
				replace allagegroups = allagegroups + ","
				levelsof allagegroups, local(allagegroups)
				local newagegroups = ""
				forvalues q = 0/100 {
					local inall = 0
					local all = 0
					foreach ag of local allagegroups {
						local all = `all'+1
						if(strpos("`ag'",",`q',") ~= 0) {
							local inall = `inall'+1
						}
					}	
			
					if(`inall' == `all') {
						local newagegroups = "`newagegroups'" + "`q' "
					}
					
				}
				
				local newagegroups = rtrim("`newagegroups'")

				tempfile beforeadd
				save `beforeadd', replace
				clear
				set obs 1
				g id = 1
				local cyear1 = substr("`cy'",strpos("`cy'"," ")-4,4)
				local cyear2 = substr("`cy'",-4,.)
				forvalues cyr = `cyear1'/`cyear2' {
					g year`cyr' = .
				}
				reshape long year, i(id)
				drop year id
				rename _j year
				drop if strpos("`vr_years'",string(year)) ~= 0
				tempfile afteradd
				save `afteradd', replace
				use `beforeadd', clear
				append using `afteradd'
				
				foreach vcombo1 of local vr_years {
					foreach vcombo2 of local vr_years {
						if(`vcombo1' < `vcombo2') {
							di "`vcombo1' `vcombo2'"
							forvalues j = 0/100 {
								egen vcombotemp = mean(deaths`j') if year == `vcombo1' | year == `vcombo2'
								sort vcombotemp
								replace deaths`j' = vcombotemp[_cons] if ihme_loc_id == "" & year > `vcombo1' & year < `vcombo2'
								drop vcombotemp
							}
							continue, break
						}
					}
				}
				

				summ year if ihme_loc_id ~= ""
				return list
				local minvryear = `r(min)'
				local maxvryear = `r(max)'
				
				local count1 = 0
				local count2 = 0
				
				forvalues cyr = `cyear1'/`cyear2' {
					if(`cyr' < `minvryear') {
						local count1 = `count1' + 1  
					}
					else if(`cyr' > `maxvryear') {
						local count2 = `count2' + 1
					}
				}
				
				local count1 = `count1' + 1
				local count2 = `count2' + 1
				
				forvalues j = 0/100 {
					replace deaths`j' = `count1'*deaths`j' if year == `minvryear' 
					replace deaths`j' = `count2'*deaths`j' if year == `maxvryear'
				}

				replace ihme_loc_id = "`c'" if ihme_loc_id == ""

				collapse (sum) deaths0-deaths100, by(ihme_loc_id)

				forvalues j = 0/100 {
					replace deaths`j' = deaths`j'/(`cyear2'-`cyear1'+1)
				}

				forvalues q = 0/100 {
					g agegroup`q' = ""
				}			
				local count = 0
				foreach newa of local newagegroups {
					replace agegroup`count' = "`newa'"
					destring agegroup`count', replace
					local count = `count'+1	
				}

				forvalues q = 0/100 {
					destring agegroup`q', replace
				}

				g pop_years = "`cy'"
				g deaths_years = "`vr_years'"
				g deaths_source = "`vrsource0'"
				g deaths_footnote = "`fn0'"
				g deaths_nid = "`nid0'"
				g source_type = "`stloc'"
				g sex = substr("`c'",strpos("`c'","&&")+2,strpos("`c'","@@")-strpos("`c'","&&")-2)

				forvalues couy = 1/`count_y' {
					replace deaths_source = deaths_source + "#`vrsource`couy''" if !regexm(deaths_source,"`vrsource`couy''")
					replace deaths_footnote = deaths_footnote + "#`fn`couy''" if !regexm(deaths_footnote,"`fn`couy''")
					replace deaths_nid = deaths_nid + "#`nid`couy''" if !regexm(deaths_nid,"`nid`couy''")
				}
			}

			tempfile aftershape
			save `aftershape', replace
				
			use "`saveas'", clear
			append using `aftershape'
			save "`saveas'", replace
			
			use `beforeshape', clear
		
		}
		restore
	}

	use "`saveas'", clear

	drop temp

	gen id = ihme_loc_id
	replace ihme_loc_id = substr(ihme_loc_id,1,strpos(ihme_loc_id,"&&")-1)

	sort ihme_loc_id pop_years sex
	save "`saveas'", replace
} 

di "DONE"
// }

end
