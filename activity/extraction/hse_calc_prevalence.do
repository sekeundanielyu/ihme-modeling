// DATE: DECEMBER 20, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM THE HEALTH SURVEY FOR ENGLAND AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 

// Set up
	clear all
	set more off
	set mem 2g
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
		version 11
	}

// Create locals for relevant files and folders
	local data_dir = "$j/DATA/GBR/HEALTH_SURVEY_FOR_ENGLAND"
	local outdir = "$j/WORK/05_risk/risks/activity/data/exp"
	local years: dir "`data_dir'" dirs "*", respectcase
	local count = 0
	
// Prepare country codes database for merge to get subnational IDs later	
	odbc load, exec("SELECT local_id as iso3,name as country_name FROM epi.locations JOIN epi.locations_indicators USING (location_id) WHERE type in ('admin0','urbanicity','admin1') AND version_id=2 AND indic_epi=1") dsn(epi) clear
	
	tempfile countrycodes
	save `countrycodes'
	
// Loop through directories for each year and identify outliers, translate minutes of PA into METS and calculate prevalence estimates
foreach year of local years {
	if "`year'" != "CRUDE" & "`year'" != "1994" & "`year'" != "1995" & "`year'" != "1996" {
		// Prep individual file
		local filenames: dir "`data_dir'/`year'" files "*_IND*.DTA", respectcase
			foreach file of local filenames {
					di in red _newline "`file'"
					use "`data_dir'/`year'/`file'", clear
					renvars, lower
					drop if age < 25 | age == .
					
					gen file = "`data_dir'/`year'/`file'"
					gen year_start = substr("`year'", 1, 4)
					gen year_end = substr("`year'", -4, 4)
					destring year_start year_end, replace
					
				/* // Get subnational IDs
					// Numeric gor
					if inlist("`year'", "2000", "2007", "2006", "2008", "2003", "2005", "1998") {
						decode gor, gen(region)
					}
					// String alphabetical
					if inlist("`year'", "2002", "2009", "2001") {
						gen region = ""
						replace region = "North East" if gor == "A"
						replace region = "North West"
						replace region = "Yorkshire and the Humber"
						replace region = 
						replace region = 
						replace region = 
						replace region = 
						replace region = 
						replace region = 
	Value = B	Label = North West
	Value = D	Label = Yorkshire and The Humber
	Value = E	Label = East Midlands
	Value = F	Label = West Midlands
	Value = G	Label = East of England
	Value = H	Label = London
	Value = J	Label = South East
	Value = K	Label = South West XGO
	Value = W	Label = Wales
	Value = X	Label = Scotland (XSC)
					} 
					// 
					if inlist("`year'", "2010", "2011")
						decode gor1, gen(region)
					}
					// 2007 gor07 - numeric
					// 2006 gor06 - numeric
					2010 2011 gor1 - numeric
					2001 gora string 
					
					
					gen region = `r(varlist)'
					decode gor1, gen(country_name)
					merge m:1 country_name using `country_codes', keep(match)
					*/	
				// Convert questions about activity in last 4 weeks to average number of activities per week
					if inlist("`year'", "1991_1992", "1993", "1998", "2006") {
						recode num20 (-8 = .) // Don't know to missing
						replace num20 = num20 / 4 // convert number of occurrences of moderate or vigorous activity greater than 20 min in the last 4 weeks (excluding work) to average occurences/wk
					}
			
					if inlist("`year'", "1991_1992", "1993", "1998", "2002", "2003", "2006") {
						recode vig* (-8 -9 -1 = .) // Don't know to missing
						replace vig20sp = vig20sp / 4 // convert number of occurrences of sports greater than 20 minutes in the last 4 weeks to average occurrences/wk
					}
				
					if "`year'" == "2008" {
						foreach var in vig10sp vig30sp num10 num30 {
							recode vig* num* (-8 = .) // Don't know to missing
							replace `var' = `var' / 4 // convert occurrences of activity greater than 10 min and 30 min in the last 4 weeks to average occurrences/wk
						}
					}
				
				// Clean categorical sport and work activity questions
					if inlist("`year'", "1991_1992", "1993", "1997", "1998",  "2002", "2003", "2006", "2008") {	
							cap rename workacty workact
						if "`year'" == "2002" {
							recode workact workactg (-1 = .) // Marked as NA for all respondents this year, so question was not actually asked
						}
							recode workact (-8 = .) (-1 = 1) // Assume NA responses mean respondent does not work, so workactivity would be "inactive"
						if "`year'" != "1997" {
							recode sprtact (-8 -1 = .)
						}
					}
					
				// Clean walking variables
					// Walking pace --> MET rating for walking intensity
						if inlist("`year'", "2000", "1991_1992", "2008", "2003", "2006", "1998", "1993", "1997") {
							recode walkpace (-9 -8 5 -1 = .) 
							gen walk_intensity = 3.3 if walkpace == 3 // A fairly brisk pace
							replace walk_intensity = 3.0 if walkpace == 2 | walkpace == 5 // Steady average pace
							replace walk_intensity = 2.0 if walkpace == 1 // A slow pace
							replace walk_intensity = 4.0  if walkpace == 4 // Fast pace
							replace walk_intensity = 3 if walkpace == .
						}
						
					if inlist("`year'", "1997", "1998", "2000", "2006", "2008") {
						if "`year'" == "2000" {
							recode daywlk hrswlk minwlk (. = 0) if wlk15m == 2 | wlk5int == 2 | wlk5int == 3 // should be zero if respondent didn't walk 15+ min
							replace hrswlk = hrswlk * 60 // convert hours to minutes
							egen checkmiss = rowmiss(hrswlk minwlk)
							egen walk_min = rowtotal(hrswlk minwlk)
							recode walk_min (0 = .) if checkmiss == 2
							replace walk_min = 0 if walk_min < 10
							gen walk_dpw = daywlk / 4 // convert days in last 4 weeks to last week
							gen walk_mets = walk_dpw * walk_min * walk_intensity
						}	
							
						else {	
							cap rename wlk10m wlk15m // 2008 survey asks about walks greater than 10 minutes instead, but I will treat this the same for simplicity
							cap rename wlk5it wlk5int // 2008 has different variable name
							recode daywlk day1wlk day2wlk tottim  (-8 -1 = .)
							recode daywlk day1wlk day2wlk tottim (.=0) if wlk15m == 2 | wlk5int == 2 | wlk5int == 3 // should be zero if respondent didn't walk 15+ min
							foreach var in daywlk day2wlk {
								replace `var' = `var' / 4  // days in past 4 weeks to avg days per week
							}
							replace daywlk = daywlk - day2wlk // Isolate days of one walk/day
							gen walk_dpw = 0 if wlk15m == 2 | wlk5int == 2 | wlk5int == 3 // missing is a true zero if respondent didn't walk continuously for 15+ min in last 4 weeks
							replace walk_dpw = daywlk if day1wlk == 2 // times per week if one 15+ minute walk per day
							replace walk_dpw = day2wlk * 2 if day1wlk == 1 // times per week if more than one 15+ minute walk per week, we will assume 2 per day (which will still underestimate)
							if "`year'" == "1997" {
								recode walk_dpw (.=5) if day1wlk == 2
								recode walk_dpw (.=10) if day1wlk == 1
							}
							replace tottim = 0 if tottim < 10 // less than 10 min doesn't count
							gen walk_min = walk_dpw * tottim
							if inlist("`year'", "1998", "2006") { // asks about number of 15+ min walks in last
								cap rename hrswlka hrswlk
								recode walkno hrswlk (-9 -8 = .) // (-1 = 0)
								replace walk_min = hrswlk * 60 if walk_min == . // convert hours per week to minutes
							}
							gen walk_mets = walk_min * walk_intensity
							recode walk_mets (.=0) if walk_dpw == 0
							recode walk_mets (0=.) if tottim > 0 & tottim != .
							if "`year'" == "2008" {
								replace walk_mets = hrs10wlka * 60 * walk_intensity if walk_mets == . 
								replace walk_mets = 0 if walk10no == 0 // no brisk walks of 10 minutes or more in last 4 weeks
							}
							if !inlist("`year'", "2008", "1997")  { 
								recode walk_mets (. = 0) if walkno == 0
							}
						}
					}
					
					// Categorical walking activity level variables (inactive, light active, moderately active) 1998 2006 15 min, 2003 30 min
					if inlist("`year'", "1998", "2006", "1991_1992", "1993", "2003") {
						cap rename wlkactyb wlkacty 
						recode wlkacty (-8 = .) (-1 = 0) // don't know to missing, NA to inactive
					}
					
				// Housework/Yard/Garden/Domestic
					// Categorical housework/gardening activity level (1=Inactive, 2=light activity, 3=moderate activity)
						if inlist("`year'", "1998", "2006", "2003", "2008", "1991_1992", "1993") {
							cap rename homeactb homeacty
							recode homeacty (-9 -8 = .)
						}
						
					// Heavy housework, days per week and hours per day
						if inlist("`year'", "1997", "1998", "2006", "2008") { 
							cap rename hvyhwkhm  hevyhwrk
							cap rename hvydyhm hevyday
							cap rename hwtimhm hwtim
							cap rename heavyday hevyday
							recode hevyhwrk (-1 = 2) // not applicable = no housework 
							recode hevyday hwtim (-1 = 0) (-8 -9 = .) // not applicable = no days, don't know = .
							replace hevyday = hevyday / 4 // convert to average days of housework per week
							replace hwtim = 0 if hwtim < 10 // less than 10 min doesn't count
							gen housework_min = hwtim * hevyday
						}
						
					// Heavy gardening
						if inlist("`year'", "1991_1992", "1993", "1997", "1998", "2003", "2006") {
							recode manwork (2=0)
							replace manwork = 0 if garden == 2
							recode manwork (-8 -1 = .) 
							if "`year'" != "2003" {
								replace mandays = 0 if manwork == 0
								recode mandays (-1=.) 
								gen gardening_dpw = mandays / 4
								if !inlist("`year'", "1991_1992", "1993") {
									recode diytim (-1=0) if manwork == 0
									recode diytim (-1=.) if gardening_dpw == .
								}
							}
						}

				// Work
					// Categorical activity level at work
						if inlist("`year'", "1997", "1998") {
							recode sitwork (-9 -8 -1 = .) 
							tab sitwork, gen(work)
							rename work1 work_sit
							rename work2 work_stand
							rename work3 work_walk
						}
					
					// Work activity level
						if "`year'" == "2008" {
							recode wkactsit wkactwlk wkactclb wkactlft (-9 -8 = .)
							foreach var in wkactsit wkactwlk wkactclb wkactlft {
								gen `var'_min = `var' * 5 // Assume 5 days of work/week --> minutes/week
								// Calculate METS
							}
						}
						
					// Work
						if inlist("`year'", "1998", "2003", "2006") {
							gen work_activity = workdc == 1
							recode work_activity (0=.) if workdc == -8 
							recode workd (-8=.)
							gen work_activity_dpw = workd / 4 // days in last 4 weeks to avg days per week
						}
							
				// Recreation/Leisure/Sports
					if inlist("`year'", "1997", "1998", "2003", "2006", "2008") {	
							cap rename actphys actphy
							recode actphy (-9 -8 = .) (-1=0) (2=0) // no answer/refused/don't know= ., NA=no, recode no=2 to no=0
						
						// Make MET multipliers for each recreational activity type
							gen met01 = 8 // swim (range from 7-10)
							gen met02 = 8 // Cycling
							gen met03 = 5.5  // Working out
							gen met04 = 6.83 // Aerobics (http://appliedresearch.cancer.gov/tools/atus-met/met.php)
							gen met05 = 4.5 // Dancing
							gen met06 = 7.5 // Running
							gen met07 = 9 // Football/Rugby
							gen met08 = 7  // Tennis
							gen met09 = 12 // Squash
							gen met10 = 8 // exercises (ranges from 3.5 to 8)
							
						// Variable names for days of each activity are different in 2003 
						if inlist("`year'", "1997", "1998", "2003", "2006") {
							if inlist("`year'", "1997", "1998") {
								local y = 11
								foreach x in a b c d {
									rename act`x'occ act`y'occ
									rename act`x'tim act`y'tim
									rename act`x'eff act`y'eff
									rename act`x' intensity`y'
									local y = (`y' + 1)
								}
							}
							rename swimocc dayexc01
							rename cycleocc dayexc02
							rename weighocc dayexc03
							rename aeroocc dayexc04
							rename danceocc dayexc05
							rename runocc dayexc06
							rename ftbllocc dayexc07
							rename tennocc dayexc08
							rename squasocc dayexc09
							rename exocc dayexc10
							rename act11occ dayexc11
							rename act12occ dayexc12
							rename act13occ dayexc13
							rename act14occ dayexc14
							
							rename swimtim   exctim01
							rename cycletim  exctim02
							rename weightim  exctim03
							rename aerotim   exctim04
							rename dancetim  exctim05
							rename runtim    exctim06
							rename ftblltim  exctim07
							rename tenntim   exctim08
							rename squastim  exctim09
							rename extim     exctim10
							rename act11tim  exctim11
							rename act12tim  exctim12
							rename act13tim  exctim13
							rename act14tim  exctim14
							
							rename swimeff  excswt01
							cap rename cycleff  excswt02
							cap rename cycleeff  excswt02
							rename weigheff excswt03
							rename aeroeff  excswt04
							rename danceeff excswt05
							rename runeff   excswt06
							rename ftblleff excswt07
							rename tenneff  excswt08
							rename squaseff excswt09
							rename exeff    excswt10
							rename act11eff excswt11
							rename act12eff excswt12
							rename act13eff excswt13
							rename act14eff excswt14	
						}
						
						// Loop through each activity type and calculate MET-min/week
							foreach x in "01" "02" "03" "04" "05" "06" "07" "08" "09" "10" {
								recode whtact`x' dayexc`x' exctim`x' excswt`x' (-9 -8 = .) (-1=0) (2=0)
								replace dayexc`x' =  dayexc`x' / 4 // convert days in last 4 weeks to average days per week
								gen rec_min`x' = dayexc`x' * exctim`x'
								gen rec_met`x' = rec_min`x' * met`x'
							}
							
								
						// Calculate MET-min/week for "other" activities
							foreach x in "11" "12" "13" "14" {
								recode dayexc`x' exctim`x' excswt`x' (-9 -8 = .) (-1=0) (2=0)
								replace dayexc`x' =  dayexc`x'/4 
								gen rec_min`x' = dayexc`x' * exctim`x'
								gen rec_met`x' = dayexc`x' * 4 if excswt`x' == 2 // Assume moderate if not sweaty
								replace rec_met`x' = dayexc`x' * 8 if excswt`x' == 1 // Assume vigorous if sweaty
							}
							
						// Calculate total recreational MET-min/week
							egen rec_mets = rowtotal(rec_met*)
							egen countmiss = rowmiss(rec_met*)
							replace rec_mets = . if countmiss == 16
							drop countmiss
					}
						
					// In a sports club, gym, exercise or dance group
						if inlist("`year'", "2001", "2002", "2003", "2005", "2006") {
								recode orgs13 (-9 = .) (-2 -1 = 0)
						}
						
					// Any Recreational exercise
						if inlist("`year'", "1997", "1998", "2001") {
							cap rename  precp112 exercise
							cap rename oactq1 exercise
							recode  exercise (-9 -8 = .) (-1=0)
						}
						
				// Average hours doing heavy housework, heavy manual labor and brisk or fast walking per week 
					if "`year'" == "1998" | "`year'" == "2006" {
						cap rename hrswlka hrswlk // average hours walking per week brisk or fast (2006)
						recode hrshwk hrsman hrswlk  (-9 -8 = .) (-1 = 0) // no answer/refused and don't know to missing, not applicable to zero hours
						// Make variables that are consistent with other surveys and are in terms of average minutes per week
							gen housework_min2 = hrshwk * 60
							gen labor_min = hrsman * 60
							gen walk_min2 = hrswlk * 60
					}
									
				// Tempfile each year dataset so that they can be appended together below		
					tempfile data_`year'
					save `data_`year'', replace
					
					tempfile data`count'
					save `data`count'', replace
					local count = `count' + 1
			}
	}
}

// Append all countries together
	use `data0', clear
	local max = `count' - 1
	forvalues x = 1/`max' {
		qui: append using `data`x'', force
	}

// Standardize survey sampling variables
	replace psu = area if psu == .
	
	gen pweight = .
	replace wt_int = wt_intel if wt_int == 0 & wt_intel != 0 // Combine 65+ weight and normal weights
	foreach var in int_wt wt_int wt_65 {
		replace pweight = `var' if `var' != . & pweight == .
	}
	
	replace cluster = stratum if cluster == .
	
	recode actany exercise hevyhwrk (2=0) 
	recode actphy (-1=.)
	replace actany = actphy if actany == . & actphy != .
	
	keep sex age num20 num30 num10 num20sp numocc numoccsp vig* workact sprtact* walk_intensity walk_mets wlkacty walk*no homeacty hevy* housework* hwtim work_sit work_stand work_walk sitwork wkact*_min actphy rec_mets orgs13 exercise hrshwk hrsman hrswlk labor_min work_activity* cluster psu pweight year_start year_end file actany ad30wlk hrs10wlka gardening_dpw diytim hrstot workactg
	
tempfile master_clean
save `master_clean', replace


// Calculate proportion with work activity in each year/age/sex subgroup and save compiled/prepped dataset
	preserve
	// Condense categorical work activity variable into binary  indicator for simplicity
		gen workactive = 1 if workact > 2 & workact != . // moderate of vigorous activity level
		replace workactive = 0 if workact < 3
	
	// Only keep observations with non-missing work activity
		keep if workactive != . 

	// Set age groups
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 80 if age_start > 80 & age_start != .
		levelsof age_start, local(ages)
		drop age
		
	// Set survey weights
		svyset psu [pweight=pweight], strata(cluster)
	
	// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
		mata 
			year_start = J(1,1,999)
			age_start = J(1,1,999)
			sex = J(1,1,999)
			sample_size = J(1,1,999)
			file = J(1,1, "todrop")
			workactive_mean = J(1,1,999)
			workactive_se = J(1,1,999)
		end		
			
	// Compute prevalence
		levelsof year_start, local(years)
		foreach year of local years {
				foreach sex in 1 2 {
					foreach age of local ages {
						count if year_start == `year' & age_start == `age' & sex == `sex'
						if `r(N)' > 0 {	
							di in red  "year:`year' sex:`sex' age:`age'"
							mata: sample_size = sample_size \ `r(N)'
						// Calculate mean and standard error 
							** Years after 2000 have survey weights
							if `year' > 2000 {
								svy linearized, subpop(if year_start == `year' & age_start == `age' & sex == `sex'): mean workactive
									matrix meanmatrix = e(b)
									local mean = meanmatrix[1,1]
									mata: workactive_mean = workactive_mean \ `mean'
									
									matrix variancematrix = e(V)
									local se = sqrt(variancematrix[1,1])
									mata: workactive_se = workactive_se \ `se'
							}
							
							** Years before 2000 do not have survey weights
							if `year' < 2000 {
								mean workactive if year_start == `year' & age_start == `age' & sex == `sex'
									matrix meanmatrix = r(table)
									local mean = meanmatrix[1,1]
									mata: workactive_mean = workactive_mean \ `mean'
									
									local se = meanmatrix[2,1]
									mata: workactive_se = workactive_se \ `se'
							}
										
							// Extract other key variables	
								mata: year_start = year_start \ `year'
								mata: sex = sex \ `sex'
								mata: age_start = age_start \ `age'
								levelsof file if year_start == `year' & age_start == `age' & sex == `sex', local(filepath) clean
								mata: file = file \ "`filepath'"
						}
					}
				}
			}

	// Get stored prevalence calculations from matrix
		clear
		getmata year_start age_start sex sample_size file workactive_mean workactive_se
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
	
	// Create variables that are always tracked		
		generate year_end = year_start
		generate age_end = age_start + 4
		egen maxage = max(age_start)
		replace age_end = 100 if age_start == maxage
		drop maxage
		gen GBD_cause = "physical_inactivity"
		gen national_type_id =  2 // subnationally representative
		gen urbanicity_type_id = 1 // representative
		gen survey_name = "Health Survey of England"
		gen source = "micro_hse"
		gen iso3 = "GBR"
		gen questionnaire = "work activity"
		
	// Replace standard error as missing if its zero (so that dismod calculates error using the sample size instead)
		recode workactive_se (0 = .)
	
	//  Organize
		order iso3 year_start year_end sex age_start age_end sample_size workactive_mean workactive_se, first
		sort sex age_start age_end		
		
	// Save survey weighted prevalence estimates 
		save "`outdir'/prepped/hse_prepped.dta", replace
		
