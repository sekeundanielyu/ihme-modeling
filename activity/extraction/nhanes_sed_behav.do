// Date: April 14, 2015 
// Purpose: EXPLORATION OF SEDENTARY TIME IN NHANES USING SELF-REPORTED AND ACCELEROMETRY DATA IN NHANES 

** ************************************************************
** Set up Stata
** ***********************************************************
	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	set maxvar 30000, permanently 
	set matsize 10000, permanently
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	
	do "$j/WORK/04_epi/01_database/01_code/04_models/prod/fastcollapse.ado"
	do "/snfs3/strUser/tsspell.ado" 
	do "/snfs3/strUser/tsset.ado"
	
// Create locals for relevant files and folders
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp/raw" 
	local nhanes_data "$j/DATA/USA/NATIONAL_HEALTH_AND_NUTRITION_EXAMINATION_SURVEY/2005_2006"
	local out_dir "$j/WORK/05_risk/risks/activity/data"

** ************************************************************
** Analysis of combined NHANES data for 1988-2012
** ***********************************************************
// Bring in compiled NHANES data
	use "`data_dir'/nhanes_compiled.dta", clear 
	tempfile alldata
	save `alldata', replace
	
// Convert TV watching and computer use questions (for NHANES 2007 onward) to minutes so that comparable to the sedentary behavior question 

	// pad680: The following question is about sitting at work, at home, getting to and from places, or with friends, including time spent sitting at a desk, traveling in a car or bus, reading, playing cards, watching television or using a computer. Do not include time spent sleeping. How much time do you usually spend sitting on a typical day? 
	// paq710: Now I will ask you first about TV watching and then about computer use. Over the past 30 days, on average how many hours per day did you sit and watch TV or videos? 
	// paq715: Over the past 30 days, on average how many hours per day did you use a computer or play computer games outside of work or school? 

	gen tv_min = paq710 * 60 // convert from hours a day to minutes per day 
	gen comp_min = paq715 * 60 
	rename pad680 sed_min
	rename pad675 mod_min
	rename pad660 vig_min

// Rule out unreasonable values (only 1,440 minutes in a day) 

	drop if comp_min > 1400 
	drop if tv_min > 1440
	
// Generate age group variable.  For simplicity we will do 25-39, 40-64 and 64+ (young productive years, tweeners and retired folks)
	egen agegrp = cut(age), at(25, 40, 65, 120) icodes
	label define age_definitions 0 "25-39" 1"40-64" 2 "65+", replace
	label values agegrp age_definitions
		
	levelsof agegrp, local(agegrps)
	local activities comp_min tv_min 
	
	tempfile master 
	save `master', replace 
	
** ************************************************************
**  (1) Look at correlation between sedentary time and computer use time 
** ***********************************************************

	mata 
		sex = J(1,1, 999)
		sample_size = J(1,1, 999)
		activity = J(1,1,"todrop")
		agegrp = J(1,1, 999)
		corr = J(1,1, 99999)
		
	end
	
	foreach activity of local activities { 
		foreach sex in 1 2 {
			foreach agegrp of local agegrps {
		
		di "Sex: `sex' Age group: `agegrp'"
		corr sed_min `activity' if sex == `sex' & agegrp == `agegrp'
		matrix correlation = r(C)
		local correlation  = correlation[1,2]
		mata: corr = corr \ `correlation'
		mata: agegrp = agegrp \ `agegrp'
		mata: sex = sex \ `sex'
		mata: sample_size = sample_size \ `r(N)'
		mata: activity = activity \ "`activity'" 			
					
				}
			}
		}
		
	// Get stored coefficients and constants from matrix
	clear
	
	getmata sex sample_size agegrp corr activity 
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	
	
	// Organize	
	sort activity sex agegrp
	order activity sex agegrp	
	
	// Save to spreadsheet 
	export excel using "`out_dir'/sedentary_crosswalk.xlsx", sheet("sed_tv_comp_corr") firstrow(varlabels) sheetmodify		


** ************************************************************
**  (2) Regression of sedentary minutes per day and moderate exercise per day  
** ***********************************************************
	
	// Create empty matrix for storing coefficients and constants for crosswalking
	
	mata 
		sex = J(1,1, 999)
		sample_size = J(1,1, 999)
		agegrp = J(1,1, 999)
		beta = J(1,1, 9999)
		cons = J(1,1, 9999)	
		standard_error = J(1,1, 9999)
		lower = J(1,1, 9999)
		upper = J(1,1, 9999)
		r2 = J(1,1, 99999)
		bic = J(1,1, 99999)
		
	end
		
		foreach sex in 1 2 {
			foreach agegrp of local agegrps {
						
				use `master', clear
				keep if sex == `sex' & agegrp == `agegrp' 
				reg sed_min mod_min
				estimates store ols
					
				// Extract beta coefficients 	and constant
					matrix regresults = e(b)
					local beta = regresults[1,1]
					mata: beta = beta \ `beta'
						
					local cons = regresults[1,2]
					mata: cons = cons \ `cons'
					
				// Calculate standard error and upper and lower 95% confidence intervals	
					matrix variance_matrix = e(V)
					local se_scalar = sqrt(variance_matrix[1,1])
					mata: standard_error = standard_error \ `se_scalar'
				
					local upper = `beta' + `se_scalar'*1.96
					mata: upper = upper \ `upper'
					local lower = `beta' + `se_scalar'*1.96
					mata lower = lower \ `lower'
					
				// Extract other key variables
					estat ic
					matrix fitstats = r(S)
					local bic = fitstats[1,6]
					mata: bic = bic \ `bic'
					mata: r2 = r2 \ `e(r2)'
					mata: agegrp = agegrp \ `agegrp'
					mata: sex = sex \ `sex'
					mata: sample_size = sample_size \ `e(N)'
					
			}
		}
		
	// Get stored coefficients and constants from matrix
		clear

		getmata sex sample_size agegrp beta cons standard_error upper lower r2 bic
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	

	// Organize	
		sort sex agegrp
		order sex agegrp


** ************************************************************
**  (3) Examine relationship between accelerometry data and self-reported sedentary lifestyle questions 
** ***********************************************************
	// Physical activity monitoring data exists for NHANES 2003-2004 and 2005-2006 
	// For this initial exploratory analysis, looking at the 2005-2006 accelerometry data 

// Bring in 2005-2006 NHANES physical monitoring data 
	use "`nhanes_data'/PAXRAW_D.DTA", clear
	tempfile accel 
	save `accel', replace 
	
// Bring in demographic information 
	use "`nhanes_data'/USA_NHANES_2005_2006_DEMO_D.DTA",clear
	tempfile demo 
	save `demo', replace 
	
	merge 1:m seqn using `accel', keep(3)
	drop _m 
	tempfile accel_demo 
	save `accel_demo', replace
	
	
// Dropping unreliable data points
		
		drop if paxcal == 2 | paxstat == 2
	
	// Define non-wear periods of the Actigraph: intervals of at least 90 consecutive mintues of zero activity intensity counts 
		// Participants were asked to remove the accelerometer only during bathing, swimming and sleeping
		** // How would I allow for up to 2 consecutive minutes of activity counts between 0 and 100? 
	
	// Use tsspell command, which identifies runs of consecutive values 
	tsset seqn paxn
	tsspell paxinten
	
	egen length = max(_seq), by(seqn _spell) 
	
	// Tag nonwear period 
	gen nonwear = 1 if length > 90
	replace nonwear = 0 if nonwear == .
	
	// Sedentary time is defined in the literature as a minute where activity counts are <100 cpm; physical activity monitor data is collected for 7 consecutive days 
	gen sed = 1 if paxinten < 100 
	replace sed = 0 if sed == . 
	
	tempfile before
	save `before', replace
	
	collapse (sum) sed nonwear, by(seqn paxday) fast 
	
	// Define wear time as 1440 minutes minus non-wear time for each participant and drop if hours per day is less than 10 hours or more of wear time
	gen wear = 1440 - nonwear
	drop if wear < 600 
	
	// Only keep if a participant has at least 4 days of 10+ hours of wear-time 
	by seqn: egen max = max(paxday)
	keep if max >= 4 
	drop max
	gen sed_wear = sed - nonwear 
	
	collapse (mean) sed_wear wear, by(seqn) fast
	tempfile day 
	save `day', replace 

	outsheet using "C:\Users\strUser\Documents\MPH Program\Quant_PolMethods_503\accel_data.csv", comma names replace

	** ************************************************************
	**  (a) Correlation of self-reported average level of physical activity and accelerometry data
	** ***********************************************************

	use "`nhanes_data'/USA_NHANES_2005_2006_PAQ_D.DTA", clear 
	merge 1:1 seqn using `day', keep(3)
	drop _merge
	merge 1:1 seqn using `demo'
	
	rename ridageyr age 
	rename riagendr sex
	
	// Generate age group variable.  For simplicity we will do 25-39, 40-64 and 64+ (young productive years, tweeners and retired folks)
	egen agegrp = cut(age), at(25, 40, 65, 120) icodes
	label define age_definitions 0 "25-39" 1"40-64" 2 "65+", replace
	label values agegrp age_definitions
		
	levelsof agegrp, local(agegrps)
	
	drop _merge
	tempfile self_report 
	save `self_report', replace
	
//  Look at correlation between self-reported average level of physical activity each day (paq180) and accelerometry data 

	// PAQ180: Measure of usual occupational/domestic activity: 
		// “sit during the day and do not walk about very much,” 2) “stand or walk about quite a lot during the day, but do not have to carry or lift things very often,” 3) “lift or carry light loads, or have to climb stairs or hills often,” and 4) “do heavy work or carry heavy loads.”
	
	drop if paq180 == 7 | paq180 == 9 | paq180 == . 
	
	mata 
		sex = J(1,1, 999)
		sample_size = J(1,1, 999)
		agegrp = J(1,1, 999)
		corr = J(1,1, 99999)
		
	end
	
		foreach sex in 1 2 {
			foreach agegrp of local agegrps {
		
		di "Sex: `sex' Age group: `agegrp'"
		corr sed_wear paq180  if sex == `sex' & agegrp == `agegrp'
		matrix correlation = r(C)
		local correlation  = correlation[1,2]
		mata: corr = corr \ `correlation'
		mata: agegrp = agegrp \ `agegrp'
		mata: sex = sex \ `sex'
		mata: sample_size = sample_size \ `r(N)'		
					
				}
			}
			
	** ************************************************************
	**  (b) T-test of daily accelerometry sedentary data in self-reported physical activity categories
	** ***********************************************************
	gen group = "mostly sitting" if paq180 == 1 
	replace group = "stand, walk, lift or carry" if inrange(paq180, 2, 4) 
	
	ttest sed_wear, by(group)
	
	// Look to see if this difference in sedentary time between groups is due to wear-time 
	bysort group: summarize(wear)
	

	
	
** ************************************************************
**  (4) Relationship between self-reported levels of MVPA (moderate-to-vigorous physical activity) and sedentary time 
** ***********************************************************
	use "`nhanes_data'/USA_NHANES_2005_2006_PAQIAF_D.DTA", clear 
	
	// Multiply number of times did activity in the last 30 days by the duration of the activity to get monthly MPVA and divide by six to get weekly MPVA
	gen MVPA_week = (paddurat * padtimes) / 6 
	collapse (sum) MVPA_week, by(seqn) fast
	 
	merge 1:1 seqn using `self_report', keep(3) 
	
	// Create two categorical groups based on physical activity guideline of > 150 minutes of MPVA / week 
	gen active = 1 if MVPA_week > 150
	replace active = 0 if MVPA_week < 150 
	
	ttest sed_wear, by(active)
	
	// No significant difference in the sedentary time between those who meet the physical activity guidelines of greater than 150 minutes per week of moderate to vigorous PA and those who don't --> justifies sedentary time as a risk factor 


** ************************************************************
**  (5) Look at mean sitting time by different demographic groups
** ***********************************************************

use `before', clear 
rename riagendr sex
rename ridageyr age

collapse (sum) sed nonwear (first) sex age, by(seqn paxday) fast 
	
	// Define wear time as 1440 minutes minus non-wear time for each participant and drop if hours per day is less than 10 hours or more of wear time
	gen wear = 1440 - nonwear
	drop if wear < 600 
	
	// Only keep if a participant has at least 4 days of 10+ hours of wear-time 
	by seqn: egen max = max(paxday)
	keep if max >= 4 
	drop max
	gen sed_wear = sed - nonwear 
	
	collapse (mean) sed_wear (first) sex age, by(seqn) fast
	tempfile age_sex
	save `age_sex', replace 

merge 1:1 seqn using `demo', keep(3)
drop _m

// Set survey weights
	rename sdmvpsu  psu 
	rename sdmvstra strata
	rename wtint2yr wt 
	
	rename sed_wear sedtime
					
	svyset psu [pweight=wt], strata(strata)
	
// Create empty matrix for storing values

	mata 
			
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		sedtime_mean = J(1,1,999) 
		sedtime_se = J(1,1,999)
	end

	// Set age groups
		egen age_start = cut(age), at(25(5)120)
		replace age_start = 80 if age_start > 80 & age_start != .
		levelsof age_start, local(ages)
		drop age
					
	//  Compute prevalence
		
			foreach sex in 1 2 {
				foreach age of local ages {
					
					di in red  "year:`year' sex:`sex' age:`age'"
					count if age_start == `age' & sex == `sex'
					if r(N) != 0 {
						// Calculate mean and standard error for sedentary time

							svy linearized, subpop(if age_start == `age' & sex == `sex'): mean sedtime
								
							matrix sedtime_meanmatrix = e(b)
							local sedtime_mean = sedtime_meanmatrix[1,1]
							mata: sedtime_mean = sedtime_mean \ `sedtime_mean'
								
							matrix sedtime_variancematrix = e(V)
							local sedtime_se = sqrt(sedtime_variancematrix[1,1])
							mata: sedtime_se = sedtime_se \ `sedtime_se'
						}
			
						// Extract other key variables	
							mata: sex = sex \ `sex'
							mata: age_start = age_start \ `age'
							mata: sample_size = sample_size \ `e(N_sub)'
							
					}
				}
				
	
	clear
	getmata age_start sex sample_size sedtime_mean sedtime_se
	drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
			

	
		
	
	
	
	
	

	


