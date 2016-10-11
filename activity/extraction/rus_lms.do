// DATE: JANUARY 30, 2013
// PURPOSE: CLEAN AND EXTRACT PHYSICAL ACTIVITY DATA FROM RUSSIA LONGITUDINAL MONITORING SURVEY, AND COMPUTE PHYSICAL ACTIVITY PREVALENCE IN 5 YEAR AGE-SEX GROUPS FOR EACH YEAR 

// NOTES: 
	** Covers years 2002, 2009-2012
	** Asks respondent about a variety of activities (Jogging, ice skating, skiing; Using exercise equipment; Pleasure walking; Heel-and-toe walk; Bicycling; Swimming; Dancing, aerobics; Basketball, volleyball, soccer, hockey; Badminton, tennis; Fighting, boxing, karate; Something else 
		** Whether he/she has engaged in activity in the last 12 months at least 12 times
		** During how many months
		** Times per month
		** Minutes/time the activity lasted
	** Also asks about self characterized exercise 

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

// Make locals for relevant files and folders
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp"

// Bring in dataset
	use "`data_dir'/raw/activity_RLMS_2014_03_11.DTA", clear
	append using "`data_dir'/raw/activity_RLMS_limited_2014_01_29.DTA"

// Recreational activities
	foreach stub in  box dan equ jog swm pao pbb pbm {
		foreach suffix in min mos tmo {
			rename ik`stub'`suffix' `stub'`suffix'
			recode `stub'`suffix' (-999999=0)
		}
		gen `stub'_tpw = round((`stub'tmo * `stub'mos / 52), 1) // Average times per week
		replace `stub'_tpw = 0 if `stub'_tpw < 1 // an average of less than once per week does not count	
		gen `stub'_total = `stub'_tpw * `stub'min
	}

// Transport	
	rename ikbikehr ikbikehrs
	rename ikbikemn ikbikemin 
	foreach stub in bike wlk {
		foreach suffix in min hrs {
			rename ik`stub'`suffix' `stub'`suffix'
			recode `stub'`suffix' (-999999=0) (.b=0)
		}
		replace `stub'min = `stub'hrs * 60 + `stub'min	
		gen `stub'_total = `stub'min * 5 // Assume 5 days of work/school per week 
	}

// Work	
	foreach job in o p {
		replace ik`job'wrkwh = ik`job'wrkwh * 60 // convert to minutes
		replace ik`job'wrkmn = ik`job'wrkhr * 60 + ik`job'wrkmn
		gen `job'_dpw = ik`job'wrkwh / ik`job'wrkmn 
		foreach intensity in mpe spe {
			foreach suffix in mn hr {
				rename ik`job'`intensity'`suffix' `job'`intensity'`suffix'
			}
				recode `job'`intensity'hr `job'`intensity'mn ik`job'wrkwh ik`job'wrkhr ik`job'wrkmn ik`job'vpehr ik`job'vpemn (-999999=0)
				replace `job'`intensity'mn = `job'`intensity'hr * 60 + `job'`intensity'mn	
				gen `job'`intensity'_min = `job'`intensity'mn * `job'_dpw
		}
		gen `job'mpe_mets = `job'mpe_min *  4
		gen `job'spe_mets = `job'spe_min *  8
	}
	egen work_mets = rowtotal(ompe_mets ospe_mets pmpe_mets pspe_mets)
	egen checkmiss = rowmiss(ompe_mets ospe_mets pmpe_mets pspe_mets)
	recode work_mets (0=.) if checkmiss == 4
	drop pmpe_mets pspe_mets ompe_mets ospe_mets checkmiss

//  Specify MET equivalents
	gen box_intensity = 8 // wrestling = 6,martial arte = 10
	gen dan_intensity = 5 // dancing = 4.50, aerobics =  6.83 
	gen equ_intensity = 8 // cardiovascular equipment 
	gen jog_intensity = 7 
	gen swm_intensity = 8
	gen pao_intensity = 4
	gen pbb_intensity = 7  // volleyball 5.5, soccer 7, basketball 8
	gen pbm_intensity = 8 // singles tennis is 7-12
	gen bike_intensity = 4
	gen wlk_intensity = 3.3
	

// Calculate MET-min/week for each activity
	foreach stub in box dan equ jog swm pao pbb pbm bike wlk {
		gen `stub'_mets = (`stub'_total * `stub'_intensity)
	}
	
// Calculate total MET-min/week
	egen total_mets = rowtotal(*mets)
	egen checkmiss = rowmiss(*mets)
	replace total_mets = . if checkmiss > 2
	drop if total_mets == .
	
// Make categorical physical activity variables
	gen inactive = total_mets < 600
	gen lowactive = total_mets >= 600 & total_mets < 4000
	gen lowmodhighactive = total_mets >= 600
	gen modactive = total_mets >= 4000 & total_mets < 8000
	gen modhighactive = total_mets >= 4000 
	gen highactive = total_mets >=8000 
	recode inactive lowactive lowmodhighactive modhighactive modactive highactive (0=.) if total_mets == .
	
// Set age groups
	gen birth_year = .
	gen pweight = .
	gen sex = .
	
	foreach x in k r s t u {
		replace birth_year = i`x'birthy if i`x'birthy != .
		replace pweight = inwgt_`x' if inwgt_`x' != .
		replace sex = i`x'gender if i`x'gender != .
		replace sex = 2 if sex == -999998
		replace sex = 1 if sex == -999997
	}
	gen age = year_start - birth_year
	drop if age < 25 | age == .
	egen age_start = cut(age), at(25(5)120)
	replace age_start = 70 if age_start > 70
	levelsof age_start, local(ages)
	drop age
	
// Set survey weights
	svyset [pweight=pweight]

// Create empty matrix for storing proportion of a country/age/sex subpopulation in each physical activity category (inactive, moderately active and highly active)
	mata 
		year_start = J(1,1,999)
		age_start = J(1,1,999)
		sex = J(1,1,999)
		sample_size = J(1,1,999)
		inactive_mean = J(1,1,999)
		inactive_se = J(1,1,999)
		lowmodhighactive_mean = J(1,1,999)
		lowmodhighactive_se = J(1,1,999)
		modhighactive_mean = J(1,1,999)
		modhighactive_se = J(1,1,999)
		lowactive_mean = J(1,1,999)
		lowactive_se = J(1,1,999)
		modactive_mean = J(1,1,999)
		modactive_se = J(1,1,999)
		highactive_mean = J(1,1,999)
		highactive_se = J(1,1,999)
	end

//  Compute prevalence in each age/sex group
	levelsof year_start, local(years)
	foreach year of local years {
		foreach sex in 1 2 {	
			foreach age of local ages {
								
				di in red "Year: `year' Age: `age' Sex: `sex'"
				count if year_start == `year' & age_start == `age' & sex == `sex' & total_mets != .
				local sample_size = r(N)
				if `sample_size' > 0 {
					// Calculate mean and standard error for each activity category
						foreach category in inactive lowactive modactive highactive lowmodhighactive modhighactive {
							svy linearized, subpop(if year_start == `year' & age_start ==`age' & sex == `sex'): mean `category'
							matrix `category'_stats = r(table)
							
							local `category'_mean = `category'_stats[1,1]
							mata: `category'_mean = `category'_mean \ ``category'_mean'
							
							local `category'_se = `category'_stats[2,1]
							mata: `category'_se = `category'_se \ ``category'_se'
						}
							
					// Extract other key variables	
						mata: age_start = age_start \ `age'
						mata: sex = sex \ `sex'
						mata: sample_size = sample_size \ `sample_size'
						mata: year_start = year_start \ `year'
				}
			}
		}
	}
					
		// Get stored prevalence calculations from matrix
			clear

			getmata year_start age_start sex sample_size highactive_mean highactive_se modactive_mean modactive_se lowactive_mean lowactive_se inactive_mean inactive_se
			drop if _n == 1 // drop top row which was a placehcolder for the matrix created to store results	
	
// Create variables that are always tracked	
	generate year_end = year_start
	generate iso3 = "RUS"
	generate age_end = age_start + 4
	egen maxage = max(age_start)
	replace age_end = 100 if age_start == maxage
	drop maxage
	gen risk = "activity"
	gen parameter_type = "Prevalence"
	gen survey_name = ""
	gen source = "micro"
	gen questionnaire = "rec and transport"
	gen data_type = 10
	gen orig_unit_type = 2 // Rate per 100 (percent)
	gen orig_uncertainty_type = "SE" 
	gen national_type_id = 1 // Representative sample
	
//  Organize
	order iso3 year_start year_end sex age_start age_end sample_size highactive* modactive* lowactive* inactive*, first
	sort sex age_start age_end
	
// Save survey weighted prevalence estimates 
	save "`outdir'/prepped/rus_lms_prepped.dta", replace			
	
