********************************************************
** Description:
** Prepares the population data for the death distribution methods
** by creating census pairs.  
** 
**
**
********************************************************

** Set up Stata

cap program drop reshape_pop
program define reshape_pop

clear
set mem 500m
set more off

********************************************************
** Set parameters

syntax, data(string) saveas(string) iso3(string)

********************************************************
** Analysis code

g temp = .
save "`saveas'", replace

use "`data'", clear
if("`iso3'" ~= "all" & _N>0) {
	keep if ihme_loc_id == "`iso3'"
    
    ** drop all household deaths
    drop if source_type == "HOUSEHOLD"
}

qui if(_N>0) { 
	replace ihme_loc_id = ihme_loc_id + "&&" + sex + "@@" + source_type 
	drop sex 
	duplicates drop *, force
	levelsof ihme_loc_id, local(ihme_loc_id)

	foreach c of local ihme_loc_id {
		noisily: di "`c'"
		preserve
		keep if ihme_loc_id == "`c'"
		g DATE = string(month) + "/" + string(day) + "/" + string(year)
		levelsof DATE, clean local(date)

		local wcdate = wordcount("`date'")			

		foreach d1 of local date {
			local mindist = 100000000
			local tempyear = 0 
			
			** Determine which census to pair with d1 by finding the two closest censuses

			** Find the closest census to the census taken on d1
			foreach d2 of local date {
				local year1 = substr("`d1'",-4,.)
				local year2 = substr("`d2'",-4,.)
				
				levelsof pop_source if year == `year1', clean local(csource1)
				levelsof pop_source if year == `year2', clean local(csource2)

				if((`year2'-`year1') < `mindist' & (`year2'-`year1') > 0) {
					local mindist = `year2'-`year1'
					local tempyear = `year2'
				}
			}
				

			** Find the next closest census to the census taken on d1
			local mindist2 = 100000000
			
			foreach d2 of local date {
				local year1 = substr("`d1'",-4,.)
				local year2 = substr("`d2'",-4,.)
				
				levelsof pop_source if year == `year1', clean local(csource1)
				levelsof pop_source if year == `year2', clean local(csource2)
				
				if((`year2'-`year1') < `mindist2' & (`year2'-`year1') > 0 & `tempyear' ~= `year2') {
					local mindist2 = `year2'-`year1'
				}
			}

			** Now that we know which censuses to pair, start reshaping the data
			
			foreach d2 of local date {
				local year1 = substr("`d1'",-4,.)
				local year2 = substr("`d2'",-4,.)
				
				levelsof pop_source if year == `year1', clean local(csource1)
				levelsof pop_source if year == `year2', clean local(csource2)	

				if(((`year2'-`year1') == `mindist' | (`year2'-`year1') == `mindist2')) {

					tempfile beforeshape
					save `beforeshape', replace
					keep if DATE == "`d1'" | DATE == "`d2'"
					levelsof pop_source if year == `year1', clean local(csource1)
					levelsof pop_footnote if year == `year1', clean local(fn1)
					levelsof pop_nid if year == `year1', clean local(nid1)
					levelsof pop_source if year == `year2', clean local(csource2)
					levelsof pop_footnote if year == `year2', clean local(fn2)
					levelsof pop_nid if year == `year2', clean local(nid2)
					
					drop month day DATE pop_source pop_footnote pop_nid

					reshape wide pop* agegroup*, i(ihme_loc_id) j(year)

					forvalues j = 0/100 {
						rename pop`j'`year1' pop1_`j'
						rename pop`j'`year2' pop2_`j'
					}
					forvalues j = 0/100 {
						rename agegroup`j'`year1' agegroup1_`j'
						rename agegroup`j'`year2' agegroup2_`j'
					}
				
					g pop_years = "`d1' `d2'"
					g pop_source = "`csource1' `csource2'"
					g pop_footnote = "`fn1'#`fn2'"
					g pop_nid = "`nid1' `nid2'"
					tempfile aftershape
					save `aftershape', replace
				
					use "`saveas'", clear
					append using `aftershape'
					save "`saveas'", replace
				
					use `beforeshape', clear
				}
			}
		}
		restore
	}

	use "`saveas'", clear

	if (_N>0) { 
		drop temp

		g id = ihme_loc_id 
		g sex = substr(ihme_loc_id,strpos(ihme_loc_id,"&&")+2,strpos(ihme_loc_id,"@@")-strpos(ihme_loc_id,"&&")-2)
		replace ihme_loc_id = substr(ihme_loc_id,1,strpos(ihme_loc_id,"&&")-1)
        recast str244 pop_footnote pop_source pop_nid, force
		save "`saveas'", replace
	}
} 

di "DONE"
// }
end

