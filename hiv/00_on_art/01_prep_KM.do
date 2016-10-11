// THIS FILE'S PURPOSE IS TO PREPARE AND FORMAT THE KAPLAN MEIER DATA SO IT CAN BE PUT INTO DISMOD FOR 
	// (1) IDENTIFY POSITIVE DEVIATE IN SS AFRICA 
	// (2) RUN ALL DATA IN DISMOD. 
	// PREP STEPS INCLUDE 
		// STANDARDIZING VARIABLES, APPLYING THE LTFU CORRECTION, 
		// CALCULATING % MALE AND MEDIAN AGE BY REGION FOR THE PURPOSE OF APPLYING HAZARD RATIOS, 
		// AND TURNING CUMULATIVE INTO CONDITIONAL PROBS


global user "`c(username)'"

// settings
	clear all
	set more off
	if (c(os)=="Unix") {
		global root "/home/j"
		global code_dir "strPath"
	}

	if (c(os)=="Windows") {
		global root "J:"
		global code_dir "strPath"
	}

	
// locals 

	local KM_data "strPath/HIV_extract_KM_2015.xlsx"
	local dismod_templates "strPath"
	local bradmod_dir "strPath"
	
	local store_graphs "strPath"
	local store_logs "strPath"
	local store_data "strPath"
	
** *****************************
// Prep KM data
** *****************************

	// 1: Apply changes that affect both KM and HR calculations (regions)
		
		import excel using "`KM_data'", clear firstrow
		rename *LTFU* *ltfu*

		keep if include==1
		
		// Fill in Missing years (necessary for cd4 adjustment based on study period)
			replace year_start=year_end if year_start==.
		
		// Standardize Regions
			tab gbd_region

			gen super="ssa" if inlist(gbd_region, "Southern Sub-Saharan Africa", "Western Sub-Saharan Africa", "Eastern Sub-Saharan Africa", "Sub-Saharan Africa and Other", "Sub-Saharan Africa") ///
				| inlist(pubmed_id, 22972859, 16905784) | (pubmed_id==16530575 & site=="Low Income") ///
				| iso3 == "CIV"
			replace super="other" if inlist(gbd_region, "Tropical Latin America", "North Africa and Middle East", "East Asia", "Australasia", "Southeast Asia", "Latin America and Caribbean", "Latin America/Caribbean", "South Asia") ///
				| regexm(gbd_region,"Latin")
			replace super="high" if inlist(gbd_region, "High-Income", "Western Europe", "High-income North America") | (pubmed_id == 16530575 & site=="High Income")

		
		// CD4 categories
		
			// Standarize entries
			replace cd4_start = . if cd4_start == .
			replace cd4_start=50 if cd4_start==51
			replace cd4_start=100 if cd4_start==101
			replace cd4_start=150 if cd4_start==151
			replace cd4_start=200 if cd4_start==201
			replace cd4_start=250 if cd4_start==251
			replace cd4_start=350 if cd4_start==351
			replace cd4_start=450 if cd4_start==451

			replace cd4_end = 1500 if cd4_end == 1500
			replace cd4_end=50 if cd4_end==49
			replace cd4_end=100 if cd4_end==99
			replace cd4_end=200 if cd4_end==199
			replace cd4_end=350 if cd4_end==349
		
			// Adjust CD4 based on guidelines in place at time of study - in developing countries would not have initiated patients on art unless they had a cd4 meeting the guideline
				
				// Rwanda-specific guidelines cited in paper. they were ahead of other countries and implemented the 350 guideline earlier
				replace cd4_end=500 if iso=="RWA" &  cd4_end==1500 & cd4_start >= 350
				replace cd4_end=350 if iso=="RWA" &  cd4_end==1500 & cd4_start < 350
				
				// developing countries:
				// 2013 on: 500
				// 2010-2013: 350
				// pre 2010: 200			
				gen year_mean = (year_start + year_end) / 2
				replace cd4_end=200 if year_mean < 2010 & cd4_end==1500 & cd4_start==0 & (super=="ssa" | super=="other")
				replace cd4_end=350 if year_mean >= 2010 & year_mean < 2013 & cd4_end==1500 & cd4_start==0 & (super=="ssa" | super=="other")
				replace cd4_end=500 if cd4_end==1500 & (super=="ssa" | super=="other") // if there are still remaining 1500s left for categories starting at 200 or 350, limit the max to 500
				drop year_mean

				// developed:
				// always use 500 http://www.thelancet.com/journals/lancet/article/PIIS0140-6736(05)61719-9/fulltext
				replace cd4_end=500 if super=="high" & cd4_end==1500 & cd4_start<500 & super=="high"
				replace cd4_end=1000 if super=="high" & cd4_end==1500 & cd4_start>=500 & cd4_start!=. & super=="high"

		
		tempfile KM_data_clean
		save `KM_data_clean', replace

		
	// 2: Calculate region-specific median age and % male from KM data to be later used in applying Hazard Ratios. Should be weighted based on the size of the study.
		
		use `KM_data_clean', clear
		keep if baseline==1
		drop if prop_male==. | age_med==.
		keep pubmed_id nid subcohort_id sample_size prop_male age_med super
		
		gen num_male=prop_male*sample_size
		gen age_weight=age_med*sample_size
		collapse (sum) sample_size num_male age_weight, by(super)
		gen pct_male_weighted=num_male/sample_size
		gen age_med_weight=age_weight/sample_size
		drop sample_size num_male age_weight
			
		outsheet using "`store_data'/pct_male_med_age/pct_male_med_age.csv", delim(",") replace 
		

	// 3: Prep data for KM DisMod

		use `KM_data_clean', clear 
		
		drop if baseline==1
		keep include pubmed_id nid subcohort_id super iso site cohort year* sex prop_m age* cd4* treat* sample_size ltfu_prop* dead_prop* ltfu_def extractor notes
		drop dead_prop_alt
		foreach var in cd4_start cd4_end {
			replace `var' = round(`var',.01)
		}
		tostring cd4_start, replace
		tostring cd4_end, replace 
		
		// standardize CD4 categories
		gen cd4_joint=cd4_start+"-"+cd4_end
		split cd4_joint, p("-")  // "
		replace cd4_start=cd4_joint1
		replace cd4_end=cd4_joint2
		drop cd4_joint1 cd4_joint2
		
		// Generate aggreate duration
		tostring treat_mo_s, replace
		tostring treat_mo_e, replace 
		gen time_per=treat_mo_s+"_"+treat_mo_en
		
		// geneate an additional time point variable that is numeric and will sort properly
		gen time_point=6 if time_per=="0_6"
		replace time_point=12 if time_per=="0_12"
		replace time_point=24 if time_per=="0_24"
		
		// keep observations that have the time periods of interest; we will lose some observations this way but not too many
		keep if time_per=="0_6" | time_per=="0_12" | time_per=="0_24"
	
	//  4: Tempfile our prepped file
		tempfile tmp_prepped
		save `tmp_prepped', replace 


*********************
// APPLY LTFU CORRECTION (Written by allen roberts)
*********************

	// Run LTFU code

		use `tmp_prepped', clear 
		do "$code_dir/01a_adjust_survival_for_ltfu.do"
			drop if dead_prop_adj==.
			destring treat_mo_end, replace 


************************
// Format variables for bradmod excels
************************

	// 1: Create variables needed for data_in csv
		tostring age_start age_end, replace
		gen age_joint=age_start+"-"+age_end
		gen sex_real=sex
		
		keep sex year_start year_end cd4_start cd4_end dead_prop_adj dead_prop_lo dead_prop_hi super iso3 cohort site pubmed_id nid subcohort_id time_per time_point age_joint sex_real sample_size
		rename year_s time_lower
		rename year_e time_upper
		gen integrand="incidence" 
		rename cd4_start age_lower
		rename cd4_end age_upper
		rename dead_prop_adj meas_value 
		tostring nid, replace 
		gen subreg = "none"
		gen region="none"
		// super already exists
		gen x_sex=.
		replace sex=3 if sex==.
		replace x_sex=0 if sex==3 
		replace x_sex=.5 if sex==1
		replace x_sex=-.5 if sex==2
		gen x_ones=1

		
	// 2: Adjust CD4 counts (in bradmod they are in the 'age' columns since we are 'tricking' dismod)
		destring age_upper, replace 
		destring age_lower, replace 

		replace age_upper=age_upper/10
		replace age_lower=age_lower/10

	// 3: Order and save variables
		order pubmed_ nid subcohort_id super region subreg iso3 time_l time_u sex age_l age_u meas_v integ x_* time_per time_point
		tempfile tmp_adjusted
		save `tmp_adjusted', replace


***********************
// Convert to conditional probabilities before putting into bradmod
***********************

	// 1: Create conditional probabilities

		use "`tmp_adjusted'", clear 

		order meas_value pubmed_id nid subcohort_id age_joint sex_real time_point
		sort pubmed_id nid super iso3 cohort site time_lower time_upper age_joint age_lower age_upper sex_real time_point	
		
		bysort pubmed_id nid super iso3 cohort site time_lower time_upper age_joint age_lower age_upper sex_real: gen cond_prob=((meas_value-meas_value[_n-1])/(1 - meas_value[_n-1])) if time_point!=6
		
		replace cond_prob=meas_value if time_point==6
		order cond_prob
		drop meas_value
		rename cond_prob meas_value 

				
	// 2: Generate Standard Dev

		// generate confidence interval
		gen lower_adj = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (meas_value + 1/(2*sample_size) * invnormal(0.975)^2 - invnormal(0.975) * sqrt(1/sample_size * meas_value * (1 - meas_value) + 1/(4*sample_size^2) * invnormal(0.975)^2))  
		gen upper_adj = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (meas_value + 1/(2*sample_size) * invnormal(0.975)^2 + invnormal(0.975) * sqrt(1/sample_size * meas_value * (1 - meas_value) + 1/(4*sample_size^2) * invnormal(0.975)^2))  
		
		// generate standard deviation 
		gen delta=(upper-lower)/(1.96*2)
		gen exp_delta=exp(delta)
		gen meas_stdev=(exp_delta-1)*meas_value

		// need appropriate fix if the meas_value was 0 and therefore also the standard deviation calculated was zero. solution proposed by hmwe is to average the standard
			// deviation of other rows from the same study. or otherwise just replace with a very small value (.0001)
		bysort pubmed_id nid super iso3 time_lower time_upper age_joint age_lower age_upper sex_real: egen mean_std=mean(meas_stdev)
		replace meas_stdev=mean_std if meas_stdev==0
		replace meas_stdev=.0001 if meas_stdev==0

	// 3: Final dismod formatting

		// Keep variables for dismod
		keep pubmed_id nid subcohort_id iso3 cohort site sex super meas_value meas_stdev region subreg x_sex age_lower age_upper time_lower time_upper integrand x_ones time_per time_point
		
		// string in order to append on those weird extra lines that bradmod requires in the data_in file
		tostring meas_stdev, replace force
		
		// Some studies did not have a point from 0-6 as a reference for the conditional prob; drop these.
		drop if meas_st=="."
		
		// dismod requires 2 extra lines at the bottom of the 'data_in' file. have saved these as a separate file that we append on here.
		preserve
			insheet using "`dismod_templates'//dismod_append.csv", clear
			tempfile tmp_append 
			save `tmp_append', replace 
		restore
		
		append using "`tmp_append'"
		order pubmed_id nid subcohort_id sex super meas_value meas_stdev region subreg x_sex age_lower age_upper time_lower time_upper integrand x_ones
		
		// make any edits you need to for those extra 2 lines for data_in
		replace age_lower=0 if integrand=="mtall" & _n!=_N
		replace age_upper=20 if integrand=="mtall" & _n!=_N
		replace age_lower=20 if integrand=="mtall" & _n==_N
		replace age_upper=100 if integrand=="mtall" & _n==_N
		
	// 4: Save conditional probabilities ready for bradmod
		tempfile tmp_conditional
		save `tmp_conditional', replace
		save "`bradmod_dir'/tmp_conditional.dta", replace

	// 5: Also update the templates of the 'value_in' , 'plain_in' , 'effect in' and rate_in files. 
		// here we can adjust smoothing parameters, and number of draws,  'offset' (eta) value, 
		// zeta value (zcov) and prior of mortality dropping with cd4 (diota upper and lower)

		// add random effects for each study to effect in
		
		insheet using "`dismod_templates'//effect_in.csv", comma names clear
			replace lower=0 if effect=="zcov"
			replace upper=1 if effect=="zcov"
			replace mean=.5 if effect=="zcov"
		outsheet using "`dismod_templates'//effect_in.csv", comma names replace
		
		insheet using "`dismod_templates'//value_in.csv", comma names clear
			replace value=".001" if name=="eta_incidence"
		outsheet using "`dismod_templates'//value_in.csv", comma names replace
		
		insheet using "`dismod_templates'//plain_in.csv", comma names clear
			replace lower=1 if name=="xi_iota" 
			replace upper=3 if name=="xi_iota"
			replace mean=2 if name=="xi_iota"
		outsheet using "`dismod_templates'//plain_in.csv", comma names replace
		
		insheet using "`dismod_templates'//rate_in.csv", comma names clear
			replace upper="0" if type=="diota"
		outsheet using "`dismod_templates'//rate_in.csv", comma names replace
		
		
	****** CHECK OUT OUR FINAL SAMPLE OF FACILITIES
		use "`bradmod_dir'/tmp_conditional.dta", clear
		gen geographic=iso
		replace geographic=site if geographic==""
		replace geographic=cohort if geographic==""


****** FOR THE PROCESS OF SELECTING OUR COUNTERFACTUAL, IT MAKES MORE SENSE TO LOOK AT CUMULATIVE SURVIVAL

	// 1: Set up
		use "`tmp_adjusted'", clear

		order meas_value pubmed_id nid age_joint sex_real time_point
		sort pubmed_id nid super iso3 cohort site time_lower time_upper age_joint age_lower age_upper sex_real time_point	
				
	// 2: Generate Standard Dev

		// generate confidence interval
		gen lower_adj = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (meas_value + 1/(2*sample_size) * invnormal(0.975)^2 - invnormal(0.975) * sqrt(1/sample_size * meas_value * (1 - meas_value) + 1/(4*sample_size^2) * invnormal(0.975)^2))  
		gen upper_adj = 1/(1 + 1/sample_size * invnormal(0.975)^2) * (meas_value + 1/(2*sample_size) * invnormal(0.975)^2 + invnormal(0.975) * sqrt(1/sample_size * meas_value * (1 - meas_value) + 1/(4*sample_size^2) * invnormal(0.975)^2))  
		
		// generate standard deviation 
		gen delta=(upper-lower)/(1.96*2)
		gen exp_delta=exp(delta)
		gen meas_stdev=(exp_delta-1)*meas_value

		// need appropriate fix if the meas_value was 0 and therefore also the standard deviation calculated was zero. solution proposed by hmwe is to average the standard
		// deviation of other rows from the same study. or, just replace with a very small value (.0001)
		bysort pubmed_id nid super iso3 time_lower time_upper age_joint age_lower age_upper sex_real: egen mean_std=mean(meas_stdev)
		replace meas_stdev=mean_std if meas_stdev==0
		replace meas_stdev=.0001 if meas_stdev==0

	// 3: Final dismod formatting

		// Keep variables for dismod
		keep pubmed_id nid subcohort_id iso3 cohort site sex meas_value meas_stdev super region subreg x_sex age_lower age_upper time_lower time_upper integrand x_ones time_point
		
		// string in order to append on those weird extra lines that bradmod requires in the data_in file
		tostring meas_stdev, replace force
		
		// Some studies did not have a point from 0-6 as a reference for the conditional prob; drop these.
		drop if meas_st=="."
		
		// dismod requires 2 extra lines at the bottom of the 'data_in' file. have saved these as a separate file that we append on here.
		// pull in bottom lines - save as csv so katrina can pull in temp file and run in stata 12 :)
		preserve
			insheet using "`dismod_templates'//dismod_append.csv", clear
			tempfile tmp_append 
			save `tmp_append', replace 
		restore
		
		append using "`tmp_append'"
		order pubmed_id nid subcohort_id sex super meas_value meas_stdev region subreg x_sex age_lower age_upper time_lower time_upper integrand x_ones
		
		// make any edits you need to for those extra 2 lines for data_in
		replace age_lower=0 if integrand=="mtall" & _n!=_N
		replace age_upper=20 if integrand=="mtall" & _n!=_N
		replace age_lower=20 if integrand=="mtall" & _n==_N
		replace age_upper=100 if integrand=="mtall" & _n==_N
		
	// 4: Save cumulative probabilities ready for bradmod
		tempfile tmp_cumulative
		save `tmp_cumulative', replace
		save "`bradmod_dir'/tmp_cumulative.dta", replace


