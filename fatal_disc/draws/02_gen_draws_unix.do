*** shock uncertainty on adult age groups ***
clear
clear matrix
cap restore, not
set more off
set memory 8000m
set seed 1234567

	if c(os) == "Windows" {
		global prefix ""
	}
	else {
		global prefix ""
	}
 
 local user strUser
 local input_folder ""
 global outdir ""
 local temp_folder ""
 if "`user'"==strUser {
 	global shell_stata "shellstata.sh"
	local code_folder "gbd_2015_shocks"
 }
 else {
 	global shell_stata "shellstata13_strUser.sh"
 	local code_folder "gbd_2015_shocks"
 }


** MUST REMOVE THE OLD FILES FIRST OR NO CHANGES WILL BE IMPLEMENTED
local datafiles: dir "`temp_folder'" files "*.dta"
foreach datafile of local datafiles {
	rm "`datafile'"
}

** Date
local date = string(date("`c(current_date)'", "DMY"), "%tdDD!_NN!_CCYY")



** STEP 1. IMPORT DATA, GET UNCERTAINTY
	use "WAR_DISASTER_DEATHS.dta", clear
	gen sex = 9
	gen age = 26

	// For YEM Data
	expand 2 if iso3 == "YEM" & year == 2015 & cause == "war", gen(new)
	replace deaths_best = 9508 if iso3 == "YEM" & year == 2015 & cause == "war" & new == 1
	replace deaths_best = 15745 - 9508 if iso3 == "YEM" & year == 2015 & cause == "war" & new == 0
	replace age = 91 if iso3 == "YEM" & year == 2015 & cause == "war" & new == 1
	// keep 91 as 0-5
	replace age = 7 if iso3=="YEM" & year==2015 & cause=="war" & new==0
	foreach rate in rate l_rate u_rate {
		replace `rate' = `rate' * (9508/15745) if iso3 == "YEM" & year == 2015 & cause == "war" & new == 1
		replace `rate' = `rate' * (6237/15745) if iso3 == "YEM" & year == 2015 & cause == "war" & new == 0
	}
	drop new

// Create low, best, and high death counts
	gen deaths_low = l_rate * total_population
	gen deaths_high = u_rate * total_population
	
	foreach var of varlist deaths* {
		replace `var' = round(`var', 1)
	}

	
	
		gen sds1 = (deaths_best - deaths_low) / 2
		gen sds2 = (deaths_high - deaths_best) / 2
		egen sds = rowmax(sds1 sds2)
		
		replace deaths_best = round(rate * tot, 1) if sds == 0
		replace deaths_low = round(l_rate * tot, 1) if sds == 0
		replace deaths_high = round(u_rate * tot, 1) if sds == 0
		
		
		replace sds1 = (deaths_best - deaths_low) / 2 if sds == 0
		replace sds2 = (deaths_high - deaths_best) / 2 if sds == 0
		egen sds_rep = rowmax(sds1 sds2)
		replace sds = sds_rep if sds == 0

		// some sds are too large and it pushes up the mean estimate because too many 0 draws are removed;
		// if they are above mean/1.96, then replace with mean/1.96 to ensure that 95% of normal distribution is positive
		gen max_sd = deaths_best / 1.96
		replace sds = max_sd if sds > max_sd

		
		keep if deaths_best != 0

		
		// execute thrsehold at national level
		// this avoids deflating the national level totals that were previously split
		gen nat_iso3 = substr(iso3, 1, 3)
		bysort nat_iso3 year cause: egen max_thresh = max(threshhold)
		drop if max_thresh < 0.000001

	

keep year iso3 cause age sex deaths_best sds
gen id=_n
local nn=_N
tempfile draws
noisily dis in red "Split file"

	// Partition dataset into 10 smaller sets and parallelize draws
	gen split = id - (floor(id / 10) * 10) + 1
	preserve
	forvalues i = 1/10 {
		keep if split == `i'
		drop split id
		
		save "pre_split_`i'.dta", replace
		
		!qsub -P proj_shocks -pe multi_slot 30 -l mem_free=60g -now no -N "split `i'" "$shell_stata" "02_gen_draws_unix_cluster.do" `i'
		
		restore
		drop if split == `i'
		preserve
	}

	// wait 5 minutes
	clear
	sleep 300000
	
	forvalues i = 1/10 {
		local check_file "post_split_`i'.dta"
		
		cap confirm file "`check_file'"
		while _rc {
			sleep 120000
			cap confirm file "`check_file'"
		}
		
		sleep 15000
		append using "`check_file'"
	}


compress
save "draws.dta", replace
save "draws_`date'.dta", replace

