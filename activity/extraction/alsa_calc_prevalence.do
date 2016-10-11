// Date: April 7, 2015
// Purpose: Extract physical activity data from South Australia Longitudinal Study of Ageing and compute  physical activity prevalence in 5 year age-sex groups for each year

// Notes: Only 65+ wave 1=1992, Wave 2=1993, etc
// Data for Wave 1 (1992-1993) 
//  Wave 4 (1995-1996) 
// Wave have all of the appropriate data to calculate METs, including average number of exercise sessions per week and the time engaged in those exercise sessions 

	clear all
	set more off
	set mem 2g
	capture log close
	capture restore not
	
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	
	else if c(os) == "Windows" {
		global j "J:"
	}
	
// Create locals for relevant files and folders
	cd "$j/WORK/05_risk/risks/activity/data/exp"
	local data_dir "$j/WORK/05_risk/risks/activity/data/exp/raw/alsa"

// ********************* Prepare First wave file ************************** // 

	use "`data_dir'/alsa_1992.dta", clear
	renvars, lower
	gen year_start = 1992
	
	// Keep only necessary variables
		
		// vigexcs: In the past two weeks did you engage in vigorous exercise (exercise which made you breathe harder or puff and pant such as tennis, jogging etc.)? 
		// vigexc2w: How many sessions of vigorous exercise did you engage in over the past two weeks? 
		// tmvexc2w: How much time did you spend exercising vigorously during the past two weeks? 
		// lsvigexc: In the past two weeks, did you engage in less vigorous exercise for recreation, sport or health-fitness purporses which did not make you breathe harder or puff and pant? 
		// lsvexc2w: How many sessions of less vigorous exercise did you engage in over the past two weeks? 
		// walk2wks: In the past two weeks, did you walk for recreation or exercise? 
		// hwmnwk2w: How many times did you walk for recreation or exercise in the past two weeks? 
		// exrthous: In the past two weeks, in the course of your tasks around the house, were you involved in moderate to heavy physical exertion which made you breathe harder or puff and pant? 
		// tmhvyexr: How much time were you involved in moderate to heavy physical exertion in tasks at (work or) home during the past two weeks?
		// heavy: Did that job require you to perform heavy physical work? 

		keep year vigexcs vigexc2w tmvexc2w lsvigexc lsvexc2w walk2wks hwmnwk2w aap23 exrthous tmhvyexr aap4 aap5 popwght seqnum age sex oldpost currwork whatkind heavy

	// Fill in missingness with zeros (when appropriate)
		recode hwmnwk2w (.=0) if walk2wks == 2
		recode tmhvyexr (.=0) if exrthous == 2
		recode vigexc2w tmvexc2w (.=0) if vigexcs == 2
		recode lsvexc2w (.=0) if lsvigexc == 2
		
	// Convert vigorous, less vigorous, times walked  to average times per week instead of times in two weeks for consistency with other surveys
		foreach var in vigexc2w lsvexc2w hwmnwk2w {
			replace `var' = `var' / 2
		}
		
	// Calculate MET-min/week (time variables are minutes in the past 2 weeks)
		
		// Vigorous
			// Note: Don't have to multiply time by days because the question is asking about total time spent exercising over past 2 weeks
		gen vig_min = tmvexc2w / 2 // already in minutes so just divide by two to get minutes per week 
		gen vig_mets = vig_min * 8
	
		// Work
		// How much time (hrs) were you involved in moderate to heavy physical exertion in tasks at work or home during the past two weeks
		gen work_min = tmhvyexr * 60 / 2 // convert to average min/week; reported in hours over the past two weeks 
		gen work_mets = work_min * 4 if heavy == 2 // respondent said that the physical exertion was not heavy 
		replace work_mets = work_min * 6 if heavy == 1 // chose MET equivalent of 6 since said moderate to heavy
		
		// Working and less vigorous activity categories only have frequency but no time measure so they cannot be included in the MET calculations
		
		
	tempfile alsa_1992
	save `alsa_1992'
	
// ********************* Prepare Fourth wave file ************************** // 

	use "`data_dir'/alsa_1995", clear
	renvars, lower
	gen year_end = 1995
	
	keep seqnum year_end vigexcw4 vexc2ww4 timvew4 lsvigew4 lsve2ww4 walk2ww4 hmwk2ww4 exrthsw4 hmex2ww4 
	
	// Fill in missingness with zeros (when appropriate)
	recode vexc2ww4 timvew4 (.=0) if vigexcw4 == 2 
	recode lsve2ww4 (.=0) if lsvigew4 == 2 
	recode hmwk2ww4 (.=0) if walk2ww4 == 2 
	recode hmex2ww4 (.=0) if exrthsw4 == 2 
	
	// Convert vigorous, less vigorous, times walked  to average times per week instead of times in two weeks for consistency with other surveys
		
		foreach var in vexc2ww4 timvew4 lsve2ww4 hmwk2ww4 hmex2ww4 {
			replace `var' = `var' / 2
		}
	
	
	// Calculate MET-min/week (time variables are minutes in the past 2 weeks)
		// Vigorous
			// Note: Don't have to multiply time by days because the question is asking about total time spent exercising over past 2 weeks
			rename timvew4 vig_min
			gen vig_mets = vig_min * 8  // already in minutes 
	
		// Work
			// How much time (hrs) were you involved in moderate to heavy physical exertion in tasks at work or home during the past two weeks
			gen work_min = hmex2ww4 / 60 
			gen work_mets = work_min * 5 // use a MET equivalent of 5 (average of 4 if it was moderate and 6 if it was heavy) because survey doesn't specify 
			
			
	merge 1:1 seqnum using `alsa_1992', keep(match)
	
	
	// Calculate total mets from each activity level and the total across all levels combined
	
		egen total_mets = rowtotal(vig_mets work_mets)
		egen total_miss = rowmiss(vig_mets work_mets) 
	    replace total_mets = . if total_miss > 1
		drop total_miss
		
	// Check to make sure total reported activity time is plausible	
		egen total_time = rowtotal(vig_min work_min) // Shouldn't be more than 6720 minutes (assume no more than 16 active waking hours per day on average)
		replace total_mets = . if total_time < 0 
		drop total_time 
		
	// Make variables and variable names consistent with other sources
	label define sex 1 "Male" 2 "Female"
	label values sex sex
	gen survey_name = "South Australia Longitudinal Study of Aging"
	gen iso3 = "AUS"
	keep sex age total_mets iso3 survey_name questionnaire year_start year_end popwwght 
	
		
		// Set age groups
			egen age_start = cut(age), at(25(5)120)
			replace age_start = 80 if age_start > 80 & age_start != .
			levelsof age_start, local(ages)
			drop age
				

//  Organize
	order iso3 year_start year_end sex age_start age_end sample_size vigexerc lesvigex walk, first
	sort sex age_start age_end		
	
// Save survey weighted prevalence estimates 
	save "./prepped/aus_rfps.dta", replace			
	



