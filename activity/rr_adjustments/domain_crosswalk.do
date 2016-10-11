// Date: November, 2013
// Purpose: Construct domain crosswalks for physical activity relative risk meta-analysis using SAGE and NHANES (GPAQ)

// NOTES: Since SAGE (WHO Study on global AGEing and adult health) and NHANES (National Health and Nutrition Examination Survey) have physical activity intensity across transport, occupational and recreational domains, we will use them to assess the relationship between each domain and total MET-min/week performed across all domains.  Since we seek to capture the disease burden attribuatable to physical inactivity across all domains, but the majority of epidemiological studies reporting relative risks only measure exposure across one domain, we will use regional correlations from SAGE and NHANES to extrapolate from the activity levels used in the study accross one or two domains to activity level across all domains.  

// Set up
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
	
// Create locals for relevant files and folders
	local datadir  "$j/WORK/05_risk/risks/activity/data/exp/raw"
	//local datadir 	"$j\WORK\2013\05_risk\02_models\physical_activity\exp\01_inputs\data\raw"
	local outdir   "$j/WORK/05_risk/risks/activity/data/rr"
	local count 	0 // local to count loop iterations and save each country as numbered tempfiles to be appended later

	use "`datadir'/sage_clean_test.dta", clear
	append using "`datadir'/nhanes_clean.dta"
	levelsof iso3, local(countries)
	
	// Generate age group variable.  For simplicity we will do 25-39, 40-64 and 64+ (young productive years, tweeners and retired folks)
		egen agegrp = cut(age), at(25, 40, 65, 120) icodes
		label define age_definitions 0 "25-39" 1"40-64" 2 "65+", replace
		label values agegrp age_definitions
		
		levelsof agegrp, local(agegrps)
	
	// Assume that missings are actually zeros
		foreach domain in work rec trans {
			replace `domain'_mets = 0 if `domain'_mets == . & total_mets != . 
		}
		
	// Generate domain-specific categorical, rank  and log-transformed MET-min/week variables for crosswalk regressions
		foreach domain in work rec trans total {
			// Convert to MET hours per week for dismod
				replace `domain'_mets = `domain'_mets / 60
			
			// Generate log METS variable
				gen `domain'_log = log(`domain'_mets) 
			
			// Dummy for any MET in domain
				gen `domain'_any = `domain'_met > 0 & `domain'_met != .
				
			// Dummy for no MET in domain
				gen `domain'_none = `domain'_met == 0
		}
	
	// Calculate MET-min/week performed in other domains aside from the predictor domain
		gen total_nowork = total_mets - work_mets
		gen total_norec = total_mets - rec_mets
	
tempfile master
save `master', replace

// Log-log OLS w/ age group sub samples
		// Create empty matrix for storing coefficients and constants for crosswalking
			mata 
			sex = J(1,1, 999)
			sample_size = J(1,1, 999)
			iso3 = J(1,1, "todrop")
			agegrp = J(1,1, 999)
			domain = J(1,1, "todrop")
			beta = J(1,1, 9999)
			cons = J(1,1, 9999)	
			standard_error = J(1,1, 9999)
			lower = J(1,1, 9999)
			upper = J(1,1, 9999)
			bic = J(1,1, 99999)
			r2 = J(1,1, 99999)
		end	
	
		foreach country of local countries {
			foreach sex in 1 2 {
				foreach agegrp of local agegrps {
					foreach domain in work rec trans {
						di "ISO3 = `country', sex = `sex', domain = `domain'"
						use `master' if iso3 == "`country'" & sex == `sex' & agegrp == `agegrp', clear
						count if `domain'_mets > 0 & `domain'_mets != . 
						if `r(N)' > 0 {
							xi: reg total_log `domain'_log  if `domain'_mets > 0
							estimates store `country'_`sex'_`agegrp'_`domain'
							
							matrix regresults = r(table)
							local beta = regresults[1,1]
							mata: beta = beta \ `beta'
							
							local cons = regresults[1,2]
							mata: cons = cons \ `cons'
							
							local lower = regresults[5,1]
							mata lower = lower \ `lower'
							
							local upper = regresults[6,1]
							mata upper = upper \ `upper'
							
							local beta_se = regresults[2,1]
							mata: standard_error = standard_error \ `beta_se'
						
						// Extract other key variables
							mata: agegrp = agegrp \ `agegrp'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `e(N)'
							mata: iso3 = iso3 \ "`country'"
							mata: domain = domain \ "`domain'"
							mata: r2 = r2 \ `e(r2)'
							
							estat ic
							matrix fitstats = r(S)
							local bic = fitstats[1,6]
							mata: bic = bic \ `bic'	
						}
					}
				}
			}
		}
		
	// Get stored coefficients and constants from matrix
		clear

		getmata sex sample_size iso3 agegrp domain beta cons standard_error upper lower bic r2
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	

	// Organize	
		sort domain sex agegrp iso3
		order domain sex agegrp iso3 sample_size beta cons standard_error lower upper

	tempfile coeffs
	save `coeffs', replace

// TRY OUT GENERATING COEFFICIENTS FOR ALL COMBINATIONS OF DOMAINS 

use `master', clear 

	gen work_trans_mets = work_mets + trans_mets 
	gen work_rec_mets = work_mets + rec_mets 
	gen trans_rec_mets = trans_mets + rec_mets 

foreach domain_combo in work_trans work_rec trans_rec { 
	gen `domain_combo'_log = log(`domain_combo'_mets) 
}



save `master', replace 

// Create empty matrix for storing coefficients and constants for crosswalking
		mata 
			sex = J(1,1, 999)
			sample_size = J(1,1, 999)
			iso3 = J(1,1, "todrop")
			agegrp = J(1,1, 999)
			domain_combo = J(1,1, "todrop")
			beta = J(1,1, 9999)
			cons = J(1,1, 9999)	
			standard_error = J(1,1, 9999)
			lower = J(1,1, 9999)
			upper = J(1,1, 9999)
			bic = J(1,1, 99999)
			r2 = J(1,1, 99999)
		end	
	
		foreach country of local countries {
			foreach sex in 1 2 {
				foreach agegrp of local agegrps {
					foreach domain_combo in work_trans work_rec trans_rec {
						
						di "ISO3 = `country', sex = `sex', domain_combo = `domain_combo'"
						use `master' if iso3 == "`country'" & sex == `sex' & agegrp == `agegrp', clear
						count if `domain_combo'_mets > 0 & `domain_combo'_mets != . 
						if `r(N)' > 0 {
							xi: reg total_log `domain_combo'_log  if `domain_combo'_mets > 0
							estimates store `country'_`sex'_`agegrp'_`domain_combo'
							
							matrix regresults = r(table)
							local beta = regresults[1,1]
							mata: beta = beta \ `beta'
							
							local cons = regresults[1,2]
							mata: cons = cons \ `cons'
							
							local lower = regresults[5,1]
							mata lower = lower \ `lower'
							
							local upper = regresults[6,1]
							mata upper = upper \ `upper'
							
							local beta_se = regresults[2,1]
							mata: standard_error = standard_error \ `beta_se'
						
						// Extract other key variables
							mata: agegrp = agegrp \ `agegrp'
							mata: sex = sex \ `sex'
							mata: sample_size = sample_size \ `e(N)'
							mata: iso3 = iso3 \ "`country'"
							mata: domain_combo = domain_combo \ "`domain_combo'"
							mata: r2 = r2 \ `e(r2)'
							
							estat ic
							matrix fitstats = r(S)
							local bic = fitstats[1,6]
							mata: bic = bic \ `bic'	
						}
					}
				}
			}
		}
		
// Get stored coefficients and constants from matrix
		clear

		getmata sex sample_size iso3 agegrp domain_combo beta cons standard_error upper lower bic r2
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results	

	append using `coeffs' 
	replace domain = domain_combo if domain == ""
	drop domain_combo
	
	// Organize	
	sort domain sex agegrp iso3
	order domain sex agegrp iso3 sample_size beta cons standard_error lower upper
	
// Combine with other coefficients and save 
//	export excel using "`outdir'/domain_crosswalk_updated_2015.xlsx", sheet("log-log") firstrow(varlabels) sheetmodify
	export excel using "C:/Users/lalexan1/Desktop/domain_crosswalk_updated_2015.xlsx", sheet("log-log") firstrow(varlabels) sheetmodify

		
