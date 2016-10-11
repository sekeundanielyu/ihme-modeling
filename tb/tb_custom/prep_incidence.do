// Prep TB incidence data

// settings 
	clear all
	set more off

	

** **********************************
// Prep data
** **********************************

   ** get pop data
	    adopath + J:/Project/Mortality/shared/functions
        get_env_results
        tempfile pop
		save `pop', replace
		
		// create 65+ custom age group
		use `pop', clear
		// drop the all-ages group
		drop if age_group_id>21
		// drop under five
		drop if age_group_id==1
		// drop aggregate locations
		drop if inlist(location_id,1, 4, 5, 9, 21, 31, 32, 42, 56, 64, 65, 70, 73, 96, 100, 103, 104, 120, 124, 134, 137, 138, 158, 159, 166, 167, 174, 192, 199)
		// merge on iso3
		merge m:1 location_id using "iso3.dta", keep(3)nogen
			** generate custom age groups... 
			preserve
				qui keep if age_group_id>=18
				collapse (sum) mean_pop, by(iso3 year_id sex sex_id)
				qui gen age=65
				tempfile tmp_65
				save `tmp_65', replace
			restore
		// create under 5 age group
			preserve
			    qui keep if age_group_id<=5
				collapse (sum) mean_pop, by(iso3 year_id sex sex_id)
				qui gen age=0
				tempfile tmp_0
				save `tmp_0', replace
			restore
		// create custome age groups 5-15, 15-25, ..., 55-65	
			drop if age_group_id<=5
			drop if age_group_id>=18
			/* replace age_group_name ="80 to 99" if age_group_name=="80 plus" */
			split age_group_name,p( to )
			gen age=age_group_name1
			destring age, replace
			forvalues i=5(10)55 {
				preserve
					local k=`i'+5
					keep if age>=`i' & age<=`k'
					collapse (sum) mean_pop, by(iso3 year sex sex_id)
					gen age=`i'
					tempfile tmp_`i'
					save `tmp_`i'', replace 
				restore
			}
			//append the files
			use "`tmp_0'", clear
			forvalues i=5(10)55 {
				qui append using "`tmp_`i''"
			}
			
			append using "`tmp_65'"
						
			qui drop if year<1990
			rename year_id year
			rename mean_pop pop
			
			//save
			
	        save "pop_custom_age.dta", replace
	
	** Prep age weights for WHO age groups...

		** get age weights
		** Use a connection string
		local conn_string strConnection
    
		local gbd_round = "2015"

		odbc load, exec("SELECT age_group_id, age_group_weight_value FROM shared.age_group_weight LEFT JOIN shared.gbd_round USING (gbd_round_id) WHERE gbd_round in ('`gbd_round'') AND age_group_weight_description LIKE 'IHME%'") `conn_string' clear
	
		rename age_group_weight_value weight
	
		save "age_weights.dta", replace
	
		// generate under 5 custom age group
	
			preserve
			qui keep if age_group_id<=5
			collapse (sum) weight
			qui gen age=0
		    tempfile tmp_0
		    save `tmp_0', replace
		    restore
			
		// generate 65+ custom age group
	        preserve
			qui keep if age_group_id>=18
			collapse (sum) weight
			qui gen age=65
		    tempfile tmp_65
		    save `tmp_65', replace
		    restore
			
		// generate custome age groups 5-15, 15-25, ..., 55-65	
		
		use "age_weights.dta", clear
		// merge on age_group_names
		merge 1:1 age_group_id using "age_group_id.dta", keep(3)nogen
		// drop under 5 and 65+ age groups
		drop if age_group_id<=5 | age_group_id>=18
		// create custome age groups 5-15, 15-25, ..., 55-65	
			split age_group_name,p( to )
			gen age=age_group_name1
			destring age, replace
		forvalues i=5(10)55 {
			    preserve
				local l=`i'+5
				qui keep if age>=`i' & age<=`l'
				collapse (sum) weight
				qui gen age=`i'
			    tempfile tmp_`i'
			    save `tmp_`i'', replace 
				restore
		}
		//append the files
		use "`tmp_0'", clear
		append using "`tmp_65'"
		forvalues i=5(10)55 {
			append using "`tmp_`i''"
		}
		qui sort age
		qui order age weig
		tempfile tmp_age_weight
		save `tmp_age_weight', replace
		save "tmp_age_weight.dta", replace


	** Prep age-specific case notifications  
	
		insheet using "notifications.csv", comma names clear 
			keep iso3 year new_sp_* new_sn_* new_ep*
			// drop unnecessary variables
			foreach var in sn ep {
				drop new_`var'_s* new_`var'_mu new_`var'_fu
			}
			drop new_ep new_sp_fu new_sp_mu
			// reshape by variable
			foreach var in sp sn ep {
				preserve
					qui keep iso year new_`var'_m* new_`var'_f*
					qui reshape long new_`var'_m new_`var'_f, i(iso year) j(age) string
					qui reshape long new_`var'_, i(iso year age) j(sex) string
					tempfile tmp_`var'
					save `tmp_`var'', replace 
				restore
			}
			** merge datasets together
			use "`tmp_sp'", clear 
			merge 1:1 iso year age sex using "`tmp_sn'", nogen 
			merge 1:1 iso year age sex using "`tmp_ep'", nogen 
				qui replace age="0-14" if age=="014"
				qui replace age="0-4" if age=="04"
				qui replace age="15-24" if age=="1524"
				qui replace age="15-100" if age=="15plus"
				qui replace age="25-34" if age=="2534" 
				qui replace age="35-44" if age=="3544"
				qui replace age="45-54" if age=="4554"
				qui replace age="5-14" if age=="514"
				qui replace age="55-64" if age=="5564"
				qui replace age="65-100" if age=="65"
				qui drop if age=="0-14" | age=="15-100"
				qui replace sex="1" if sex=="m"
				qui replace sex="2" if sex=="f"
				qui destring sex, replace 
			
	     save "tmp_CNs_age.dta", replace


** ******************************************
// Generate ep and sn inflation factors 
** ******************************************

	// Mark SU & Relapsed outliers 

		insheet using "notifications.csv", comma names clear
		qui keep iso3 year new_sp new_sn new_su new_ep ret_rel
		
			gen outlier_su=0
			gen outlier_rel=0
			**
			qui replace outlier_su=1 if iso=="AGO" & year==1995
			qui replace outlier_rel=1 if iso=="AGO" & year==2006
			qui replace outlier_su=1 if iso=="ARE" & year==1999
			qui replace outlier_su=1 if iso=="ARG" & year==1999
			qui replace outlier_su=1 if iso=="ARG" & year==2000
			qui replace outlier_su=1 if iso=="AUS" & year==2004
			qui replace outlier_su=1 if iso=="AZE" & year==2000
			qui replace outlier_su=1 if iso=="BEL" & year==1995
			qui replace outlier_su=1 if iso=="BIH" & year==1997
			qui replace outlier_su=1 if iso=="BRN" & year==1997
			qui replace outlier_su=1 if iso=="CHE" & year==1998
			qui replace outlier_su=1 if iso=="DJI" & year==1999
			qui replace outlier_su=1 if iso=="ERI" & year==1995
			qui replace outlier_su=1 if iso=="ETH" & year==1996
			qui replace outlier_su=1 if iso=="GBR" & year==1995
			qui replace outlier_su=1 if iso=="IND" & year==1997
			qui replace outlier_su=1 if iso=="ISR" & year==1998
			qui replace outlier_su=1 if iso=="ITA" & year==1995
			qui replace outlier_su=1 if iso=="LBY" & year==1995
			qui replace outlier_su=1 if iso=="MDA" & year==2000
			qui replace outlier_su=1 if iso=="NLD" & year==1995
			qui replace outlier_su=1 if iso=="NZL" & year==1997
			qui replace outlier_su=1 if iso=="PAK" & year==1998
			qui replace outlier_su=1 if iso=="PAN" & year==1999
			qui replace outlier_su=1 if iso=="PRT" & year==1995
			qui replace outlier_su=1 if iso=="SLV" & year==1995
			qui replace outlier_su=1 if iso=="TTO" & year==1997
			qui replace outlier_su=1 if iso=="TUR" & year==2001
			qui replace outlier_su=1 if iso=="TUR" & year==2004
			qui replace outlier_su=1 if iso=="UGA" & year==2000
			qui replace outlier_su=1 if iso=="ZAF" & year==1995
			qui replace outlier_su=1 if iso=="ZMB" & year==2002
			qui replace outlier_su=1 if iso=="ZWE" & year==1995
			replace new_su=. if outlier_su==1
			replace ret=. if outlier_rel==1
			drop out*
		save "tmp_CN_vars_out.dta", replace
		
	// Generate inflation factors 
	
		** Smear-unknown inflation factors...- take national average
		
			// create a variable to indicate whether smear unknown is missing or not
				qui gen su_miss=1 if new_su==.
			// temporarily replace missing smear unknown cases with zeros (we will later mark the smear unknown inflation factor based on them as missing)
				qui replace new_su=0 if new_su==.
				qui gen CN_spsu=new_sp+new_su
				qui keep iso year CN_spsu new_sp su_miss
			// create the smear unknown inflation factor
				qui gen su_inflat_sp=CN_spsu/new_sp
			// mark the inflation factor as missing if smear unknown is missing
				qui replace su_inflat=. if su_miss==1
				qui drop su_miss
			
				qui keep iso year su_*
			tempfile tmp_su_inflation
			save `tmp_su_inflation', replace 
		
		
		** Generate Relapsed cases inflation factors...
		
			use "tmp_CN_vars_out.dta", clear
			// create a variable to indicate whether relapse information is missing or not
				qui gen ret_miss=1 if ret_rel==.
			// temporarily replace missing relapse cases with zeros (we will later mark the inflation factor based on them as missing)
				qui replace new_su=0 if new_su==.
				qui replace ret_rel=0 if ret_rel==.
			// create the relapse inflation factor
				qui gen CN_spsu_rel=new_sp+new_su+ret_rel
				qui gen CN_spsu=new_sp+new_su
				qui keep iso year CN_spsu_rel CN_spsu ret_miss
				qui gen ret_inflat_sp=CN_spsu_rel/CN_spsu /*smear unknown is included in both the numerator and the denominator, so replacing the missing values with zeros have no effect on the relapse inflation factor */
			// mark the inflation factor as missing if the relapse information is missing
				qui replace ret_inflat_sp=. if ret_miss==1
				qui drop ret_miss
			** 	replace ret_inflat_sp=1 if ret_inflat_sp==.
				qui keep iso year ret_inflat*
			tempfile tmp_ret_inflation
			save `tmp_ret_inflation', replace 
		
		
		** merge data together
		use `tmp_su_inflation', clear
			merge 1:1 iso year using `tmp_ret_inflation', nogen 	
		save "tmp_inflations.dta", replace
	
	// Interpolate inflation factore values... 

		// Prep data 
		
			// flag countries where we have a single year of data
				preserve
					qui drop if su_inflat==.
					qui gen id=1
					collapse (sum) id, by(iso )
					qui gen ratio_su=0
					qui replace ratio_su=1 if id<=1
					tempfile tmp_su_ratio
					save `tmp_su_ratio', replace 
				restore
				**
				preserve
					qui drop if ret_inf==.
					qui gen id=1
					collapse (sum) id, by(iso )
					qui gen ratio_ret=0
					qui replace ratio_ret=1 if id<=1
					qui tempfile tmp_ret_ratio
					save `tmp_ret_ratio', replace 
				restore
				merge m:1 iso using "`tmp_su_ratio'", nogen 
				merge m:1 iso using "`tmp_ret_ratio'", nogen
				drop id
			
				save "tmp_interp_dta.dta", replace

		// Interpolate SU
		
			** for multiple year data 
				keep if ratio_su==0
				levelsof iso, local(isos) 
				foreach i of local isos {
					preserve
						qui keep if iso=="`i'"
						qui impute su_inflat year, gen (su_inflat_sp_xb) 
						tempfile tmp_`i'
						save `tmp_`i'', replace 
					restore
				}
				clear
				foreach i of local isos {
					qui append using "`tmp_`i''"
				}
				// create a new variable where missing su inflation values will be replaced with imputed values
				qui gen su_inflat_sp_new=su_inflat_sp 
				qui replace  su_inflat_sp_new=su_inflat_sp_xb if su_inflat_sp==.
				qui replace su_inflat_sp_new=1 if su_inflat_sp_new<0
				qui keep iso year su_inflat_sp_new
			tempfile tmp_su_1
			save `tmp_su_1', replace 
			** for one year data
			use "tmp_interp_dta.dta", clear
				qui keep if ratio_su==1
				qui keep iso su_infla
				qui duplicates drop 
				qui drop if su_infla==.
				qui rename su_infla su_inflat_avg
			tempfile tmp_su_2
			save `tmp_su_2', replace
			** append together
			use "tmp_interp_dta.dta", clear
				qui keep iso year
				merge 1:1 iso year using `tmp_su_1', nogen
				merge m:1 iso using `tmp_su_2', nogen
				qui replace su_inflat_sp_new=su_inflat_avg if su_inflat_sp_new==.
				drop *avg
				duplicates drop 
				drop if year==.
			tempfile tmp_su_inflat_adj
			save `tmp_su_inflat_adj', replace
			save "tmp_su_inflat_adj.dta", replace

		
		// Interpolate Relapsed
		
			** for multiple year data 
			use "tmp_interp_dta.dta", clear
				keep if ratio_ret==0
				levelsof iso, local(isos) 
				foreach i of local isos {
					preserve
						qui keep if iso=="`i'"
						qui impute ret_inflat year, gen (ret_inflat_sp_xb) 
						qui tempfile tmp_`i'
						save `tmp_`i'', replace 
					restore
				}
				clear
				foreach i of local isos {
					qui append using "`tmp_`i''"
				}
				qui gen ret_inflat_sp_new=ret_inflat_sp 
				qui replace  ret_inflat_sp_new=ret_inflat_sp_xb if ret_inflat_sp==.
				qui replace ret_inflat_sp_new=1 if ret_inflat_sp_new<0
				qui keep iso year ret_inflat_sp_new
			tempfile tmp_ret_1
			save `tmp_ret_1', replace 
			** for one year data
			use "tmp_interp_dta.dta", clear
				qui keep if ratio_ret==1
				qui keep iso ret_infla
				duplicates drop 
				qui drop  if ret_infla==.
				rename ret_infla ret_inflat_avg
			tempfile tmp_ret_2
			save `tmp_ret_2', replace
			** append together
			use "tmp_interp_dta.dta", clear
				qui keep iso year
				merge 1:1 iso year using `tmp_ret_1', nogen
				merge m:1 iso using `tmp_ret_2', nogen
				qui replace ret_inflat_sp_new=ret_inflat_avg if ret_inflat_sp_new==.
				qui drop *avg
				qui duplicates drop 
				drop if year==.
			tempfile tmp_ret_inflat_adj
			save `tmp_ret_inflat_adj', replace
		save "tmp_ret_inflat_adj.dta", replace
		
		// Merge together
		use "tmp_interp_dta.dta", clear
			qui drop ratio*
			qui merge 1:1 iso year using "`tmp_ret_inflat_adj'", nogen 
			qui merge 1:1 iso year using "`tmp_su_inflat_adj'", nogen 
			qui replace ret_inflat_sp_new=2 if ret_inflat_sp_new>2
			qui replace su_inflat_sp_new=2 if su_inflat_sp_new>2
		tempfile tmp_interp_ratios
		save `tmp_interp_ratios', replace 
		save "tmp_interp_ratios.dta", replace
		

** ******************************************
// Correct for missing age-sex notifications... (under 15 age group)
** ******************************************
** Prep raw CN data- country year
		insheet using "notifications", comma names clear 
		keep iso3 year new_sp new_sn new_su new_ep new_oth ret_rel new_labconf
		tempfile tmp_CN_vars
		save `tmp_CN_vars', replace

		
		use "`tmp_CN_vars'", clear 
			merge 1:m iso year using "tmp_CNs_age.dta", nogen 
			foreach var in sp sn ep {
				rename new_`var'_ new_`var'_age
			}
			order iso year age sex
			drop if new_sp==. & new_sn==. & new_oth==. & new_ep==. & ret_rel==.
			
			sort iso3 year age sex
			gen missing_age=0
			replace missing_age=1 if new_sp!=. & new_sp_age==.
			foreach var in new_sp new_sn new_su new_ep new_oth ret_rel {
				rename `var' `var'_cy
			}
			split age,p("-")
			destring age1, replace
			drop age age2
			rename age age
			order iso year age sex
			sort iso year age sex
			drop if year<1990
		save "ALL_CN_data_cyas_cy.dta", replace
		
	
	// Prep data... 

		use "ALL_CN_data_cyas_cy.dta", clear
			drop *cy missing
			** replace age groups <15 missing - Theo outliers
			preserve
				insheet using "outliers_u15.csv", clear names
				gen outlier=1
				tempfile tmp_u15
				save `tmp_u15', replace
			restore
			merge m:1 iso3 using "`tmp_u15'", nogen 
			foreach s in sp sn ep {
				replace new_`s'_age=. if outlier==1 & age<15
			}
			drop outlier
			** replace age-notifications to missing for years where only report one age group
			foreach s in sn ep {
				replace new_`s'_age=. if iso=="IND" & year==2007
				replace new_`s'_age=. if iso=="AGO" & year==2011
				replace new_`s'_age=. if iso=="MLI"
				replace new_`s'_age=. if iso=="BRB"
				replace new_`s'_age=. if iso=="ETH"
				replace new_`s'_age=. if iso=="GRD"
				replace new_`s'_age=. if iso=="TLS"
				replace new_`s'_age=. if iso=="LCA"
				replace new_`s'_age=. if iso=="SYC"
				replace new_`s'_age=. if iso=="ATG"
			}
			** merge on pop
			// rename sex befor merging on pop
			rename sex sex_id
			merge 1:1 iso year age sex using "pop_custom_age.dta", keepusing(pop) keep(3) nogen 
			// calculate log incidence rate
			foreach var in sp sn ep {
				gen ln_`var'_rt=ln(new_`var'_age/pop)
			}	
			** Identify where there is all missing data
			preserve
				collapse (sum) new*, by(iso year)
				foreach var in sp sn ep {
					gen missing_`var'=0
				// after collapsing, a missing country-year will be shown as zero
					replace missing_`var'=1 if new_`var'==0
				}
				tempfile tmp_missing
				save `tmp_missing', replace 
			restore
			merge m:1 iso year using "`tmp_missing'", nogen 
		tempfile tmp_reg_data_1
		save `tmp_reg_data_1', replace 
		
		save "tmp_reg_data_1.dta", replace
		
	// Run regression by country & sex & impute
	
		// log file
		log using "log\regression_u5", replace 
			levelsof sex_id, local(sexes)
			foreach s of local sexes {
				preserve
					keep if  sex==`s'
					**
					di in red "SP Regression - Sex `s'"
						regress ln_sp_rt i.year i.age 
						predict ln_sp_rt_xb
					di in red "SN Regression - Sex `s'"
						regress ln_sn_rt i.year i.age 
						predict ln_sn_rt_xb
					di in red "EP Regression - Sex `s'"
						regress ln_ep_rt i.year i.age 
						predict ln_ep_rt_xb
					tempfile tmp_`s'
					save `tmp_`s'', replace 
				restore
			}
		log close 
		clear
			use "`tmp_1'", clear
			append using "`tmp_2'"
			** convert from log space rates to numbers
			foreach var in sp sn ep {
				gen `var'_rt_xb=exp(ln_`var'_rt_xb)
				gen `var'_xb=`var'_rt_xb*pop
			}
			drop ln* *rt*
		tempfile tmp_age_xbs
		save `tmp_age_xbs', replace
		save "tmp_age_xbs.dta", replace
		
	// Fill in missing age groups
	
		use "`tmp_age_xbs'", clear 
			order iso year age sex pop 
			outsheet using "Under_5_CN_reg_xbs.csv", delim(",") replace
			** Fill missing
			foreach var in sp sn ep {
				// replace with predicted values only when some (but not all) country-years are missing
				replace new_`var'_age=`var'_xb if new_`var'_age==. & missing_`var'==0
			}
			keep iso year age sex new* pop 
		tempfile tmp_age_CN_adj
		save `tmp_age_CN_adj', replace 
		save "tmp_age_CN_adj.dta", replace

	
** ********************************************
// Prep inputs for EP regression
** ********************************************

	// Generate age standardzied rates & apply SU/RET inflation factors

		use "tmp_age_CN_adj.dta", clear
			** adjust for smear-unknown
			merge m:1 iso year using "tmp_interp_ratios.dta", keep(3) nogen 
				qui drop su_inflat_sp ret_inflat_sp
				qui gen new_sp_adj=new_sp_age*su_inflat_sp
				qui gen new_sp_adj2=new_sp_adj*ret_inflat_sp
				qui keep iso year age sex_id pop new*
		save "CN_dta_adj_su_ret_ages.dta", replace 
			** merge on weights
			merge m:1 age using "tmp_age_weight.dta", nogen 
			** generate rates... & age standardize
			qui replace new_sp_adj2=(new_sp_adj2/pop)*weight
			collapse (sum) new_sp_adj2* pop, by(iso year) 
			qui rename new_sp_adj2 sp_agestd_rt
		tempfile tmp_age_std
		save `tmp_age_std', replace 
				
	    save "Age_std_CNs.dta", replace

** ********************************************
// Run EP regressions
** ********************************************

	// Prep data

		// Generate desired fractions... 
		
			use "CN_dta_adj_su_ret_ages.dta", clear 
				qui drop  new_sp_adj new_sp_age
				foreach var in sp sn ep {
					qui drop if new_`var'==.
				}
				** gen total 
				qui gen new_tot=new_sp+new_ep+new_sn
				foreach s in sp sn ep {
					qui gen frac_`s'=new_`s'/new_tot
				}
				qui drop if frac_sp==.
				** merge on criteria... 
				** gen iD for populations <5 million
				preserve
					collapse (sum) pop, by(iso year)
					qui gen outlier=0
					qui replace outlier=1 if pop<5000000
					tempfile tmp_pop_out
					save `tmp_pop_out', replace
				restore
				merge m:1 iso year using "`tmp_pop_out'", nogen 
				
			tempfile tmp_fracs
			save `tmp_fracs', replace 
		    save "tmp_fracs.dta", replace 
	
		// Prep data for regression 
	
			use "pop_custom_age.dta", clear
				merge 1:1 iso year age sex_id using "CN_dta_adj_su_ret_ages.dta", nogen  
				merge 1:1 iso year age sex_id using "tmp_fracs.dta", nogen 
				merge m:1 iso year using "Age_std_CNs.dta", nogen 
			
				** generate age dummies
				levelsof age, local(ages)
				foreach a of local ages {
					qui gen age`a'=0
					qui replace age`a'=1 if age==`a' 
				}
				qui gen sex_2=0
				qui replace sex_2=1 if sex_id==2
				qui gen y1_snsp=ln(frac_sn/frac_sp)
				qui gen y2_epsp=ln(frac_ep/frac_sp)
				qui drop frac* new_sp_adj new_sp_age 
				qui order iso year age sex
				** generate missing cat
				foreach var in sn ep {
					gen missing_`var'=0
					replace missing_`var'=1 if new_`var'==.
				}
			tempfile tmp_reg_data_2
			save `tmp_reg_data_2', replace
			save "tmp_reg_data_2.dta", replace
	
	
	// Test regressions
	   
        cap log close
		log using "log\SUP_bysex_noHIV", replace 
			use "tmp_reg_data_2.dta", clear 
			keep if outlier==0
			
			** Try both sexes
			di in red "Both sexes" 
				sureg (y1_snsp sex_2 age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt) (y2_epsp sex_2 age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt)
			di in red "Males"
			preserve
				keep if sex_id==1
				sureg (y1_snsp age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt) (y2_epsp age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt)
			restore
			di in red "Females"
			preserve
				keep if sex_id==2
				sureg (y1_snsp age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt) (y2_epsp age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt)
			restore
			
		log close
	

	// Genearte predictions - Both ages combined

		 use "tmp_reg_data_2.dta", clear	
		// Regression
			sureg (y1_snsp sex_2 age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt) (y2_epsp sex_2 age0 age5 age15 age25 age45 age55 age65 sp_agestd_rt) if outlier==0
			
			** store coefficients
			
				matrix m = e(b)'
				** 
				qui gen y1_b_sex_2=m[1,1]
				qui gen y1_b_age0=m[2,1]
				qui gen y1_b_age5=m[3,1]
				qui gen y1_b_age15=m[4,1]
				qui gen y1_b_age25=m[5,1]
				qui gen y1_b_age45=m[6,1]
				qui gen y1_b_age55=m[7,1]
				qui gen y1_b_age65=m[8,1]
				qui gen y1_b_sp_agestd_rt=m[9,1]
				qui gen y1_b_cons=m[10,1]
				** 
				qui gen y2_b_sex_2=m[11,1]
				qui gen y2_b_age0=m[12,1]
				qui gen y2_b_age5=m[13,1]
				qui gen y2_b_age15=m[14,1]
				qui gen y2_b_age25=m[15,1]
				qui gen y2_b_age45=m[16,1]
				qui gen y2_b_age55=m[17,1]
				qui gen y2_b_age65=m[18,1]
				qui gen y2_b_sp_agestd_rt=m[19,1]
				qui gen y2_b_cons=m[20,1]
			
			
			** genearte predictions
			forvalues i=1/2 {
				qui gen y`i'_xb=sex_2*y`i'_b_sex_2+age0*y`i'_b_age0+age5*y`i'_b_age5+age15*y`i'_b_age15+age25*y`i'_b_age25+age45*y`i'_b_age45+age55*y`i'_b_age55+age65*y`i'_b_age65+sp_agestd_rt*y`i'_b_sp_agestd_rt+y`i'_b_cons
				qui drop y`i'_b*
			}
			qui keep iso year age sex pop y1* y2* new* missing*
			
			** gen smear positive and smear negative
			qui gen xb_sn=exp(y1_xb)*new_sp_adj
			qui gen xb_ep=exp(y2_xb)*new_sp_adj
			qui drop y1* y2*
			
			** generate predictions
			drop if new_sp_adj2==.
			gen new_sn_age_xb=new_sn_age
			gen new_ep_age_xb=new_ep_age
			replace new_sn_age_xb=xb_sn if missing_sn==1
			replace new_ep_age_xb=xb_ep if missing_ep==1
			qui drop xb*
			qui gen CN_bact_xb=new_sn_age_xb+new_sp_adj2+new_ep_age_xb
			qui gen CN_spsn_xb=new_sn_age_xb+new_sp_adj2
			
		tempfile tmp_bothsexes_xb
		save `tmp_bothsexes_xb', replace 	
		save "SUP_xbs_TB_CNs.dta", replace 

** ********************************************************************age split 65 plus*******************************************************************************************************************************************

	use "BRA_inc_age_pattern.dta", clear
	keep age_start age_end sex rate
	keep if age_start>=65
	tempfile age_pattern
	save `age_pattern', replace


	use "pop_0to90plus.dta", clear
	drop if age_start==75 & age_end==100
	merge m:1 location_id using "iso3.dta", keep(3)nogen
	preserve
	keep if age_start>=65
	tempfile pop_65_plus
	save `pop_65_plus', replace
	restore
	drop if age_start>=65
	tempfile pop_under65
	save `pop_under65', replace

	use "SUP_xbs_TB_CNs.dta", clear
	keep iso3 year age sex CN_bact_xb

	keep if age==65


	merge 1:m iso3 year sex using `pop_65_plus', keep(3) nogen


	merge m:1 sex age_start using `age_pattern', keep(3)nogen

	rename pop sub_pop
	gen rate_sub_pop=rate*sub_pop

	preserve
	collapse (sum) rate_sub_pop, by(location_id year sex) fast
	rename rate_sub_pop sum_rate_sub_pop
	tempfile sum
	save `sum', replace

	restore
	merge m:1 location_id year sex using `sum', keep(3)nogen

	gen cases=rate_sub_pop*(CN_bact_xb/sum_rate_sub_pop)

	rename sub_pop sample_size 

	sort location_id year sex age_start

	tempfile tmp_65_split
	save `tmp_65_split', replace


	use "SUP_xbs_TB_CNs.dta", clear
	keep iso3 year age sex CN_bact_xb
	gen cases=CN_bact_xb

	drop if age==65

	merge m:1 iso3 year age sex using "`temp_dir'\pop_custom_age.dta", keep(3) nogen
	merge m:1 iso3 using "`temp_dir'\iso3.dta", keep(3)nogen
	//rename
	rename pop sample_size 
	rename age age_start
	gen age_end=age_start+10
	replace age_end=4 if age_start==0

	append using `tmp_65_split'

	sort location_id year sex age_start age_end 

	drop rate rate_sub_pop sum_rate_sub_pop age age_group_name

	save "SUP_xbs_TB_CNs_age_splitted.dta", replace

	// generate a correction factor to adjust for discrepancies between all-age numbers and the sum of age-sex specific numbers 
	collapse (sum) cases, by(location_id iso3 year) fast
	tempfile tot_cases
	save `tot_cases', replace

	insheet using "notifications", comma names clear
	keep iso3 year c_newinc
	tempfile WHO
	save `WHO', replace

	use `tot_cases', clear

	merge 1:1 iso3 year using `WHO', keep(3)nogen

	gen correction_factor=c_newinc/cases

	keep location_id iso3 year correction_factor

	save "tb_correction_factor.dta", replace
  
// get cdr (5 yr moving average)

	use "moving_imputed_CDR_outlier.dta", clear
	keep location_id year mean_cdr
	tempfile cdr
	save `cdr', replace

	use "SUP_xbs_TB_CNs_age_splitted.dta", clear


// apply the correction factor so that the sum of all cases will equal total cases
 
	merge m:1 location_id year using "tb_correction_factor.dta", nogen
	replace cases=cases*correction_factor if correction_factor>1 & correction_factor !=.

// calculate mean and se
	gen mean=cases/sample_size
 
	gen standard_error=sqrt(mean*(1-mean)/sample_size)

// add nid

	gen nid=126384

// merge on cdr but don't adjust for cdr
	merge m:1 location_id year using `cdr'

	save "SUP_xbs_TB_CNs_age_splitted_no_cdr_adj.dta", replace 


** **********************************************************************************************************************************************************************************
// Prep subnationals
** **********************************************************************************************************************************************************************************

// get national age patterns
	use "SUP_xbs_TB_CNs_age_splitted.dta", clear
	gen rate=cases/sample_size
	keep iso3 year age_start age_end sex rate cases
	rename cases cases_national
	preserve
	keep if iso3=="CHN"
	tempfile CHN_age_pattern
	save `CHN_age_pattern', replace
	restore

	preserve
	keep if iso=="MEX"
	keep if year==2012
// no national age pattern for 1990 so use the 2012 age pattern instead
	expand 2, gen(new)
	replace year=1990 if new==1
	drop new
	tempfile MEX_age_pattern
	save `MEX_age_pattern', replace
	restore

	preserve
	keep if iso=="GBR"
	tempfile GBR_age_pattern
	save `GBR_age_pattern', replace
	restore

	preserve
	keep if iso=="JPN"
	keep if year==2012
// no national age pattern for 2014 so use the 2012 age pattern instead
	expand 2, gen(new)
	replace year=2014 if new==1
	drop new
	tempfile JPN_age_pattern
	save `JPN_age_pattern', replace
	restore

	preserve
	keep if iso=="USA"
	tempfile USA_age_pattern
	save `USA_age_pattern', replace
	restore

	// Pull province names 
	use "iso3.dta", clear
	// drop location_name duplicates, otherwise it won't merge
	drop if iso3=="BRA_4756"
	drop if iso3=="GEO"
	drop if iso3=="S4" | iso3=="S5"

	tempfile tmp_iso_map
	save `tmp_iso_map', replace 
	
		
	// Prep China 
	
		** Pull WHO CNs for MAC and HKG

			insheet using "notifications", comma names clear
				gen bact_pos=new_sp+new_sn+new_su
				keep iso3 year bact_pos
				keep if iso=="MAC" | iso=="HKG"
				replace iso="CHN_361" if iso=="MAC"
				replace iso="CHN_354" if iso=="HKG"
				rename bact_pos inc_num
				keep if year>=2004 
			tempfile tmp_MAC_HKG
			save `tmp_MAC_HKG', replace
		
		
		** Pull in the rest of the bact+ CNs
	
			insheet using "CHN_NOTIFIABLE_INFECTIOUS_DISEASES_2004_2012_TB_BACTPOS.csv", clear 
				drop provid reportdeaths
				rename report inc_num
				rename prov location_name
				replace location="Heilongjiang" if location=="Heilongjiag"
				replace location="Shaanxi" if location=="shaanxi"
				merge m:1 location_name using `tmp_iso_map', keep(3) nogen 
				append using "`tmp_MAC_HKG'"
				
				preserve
				collapse (sum) inc, by(year)
				rename inc inc_CHN
				tempfile tmp_chn
				save `tmp_chn', replace
			    restore
				merge m:1 year using "`tmp_chn'", nogen 
				gen frac_nat=inc_num/inc_CHN
				keep iso frac year
				tempfile tmp_CHN_fracs
				save `tmp_CHN_fracs', replace 
			    
				
				use `CHN_age_pattern', clear
				collapse (sum) cases_national, by(year) fast
				merge 1:m year using `tmp_CHN_fracs', keep(3)nogen
				** apply fraction
				gen inc_num_new=cases_national*frac
			
			    tempfile CHN_sub
				save `CHN_sub', replace
		
		** Apply CHINA national pattern... 

			// get population

			use "pop_0to90plus.dta", clear
			drop if age_start==75 & age_end==100
			merge m:1 location_id using "iso3.dta", keepusing(iso3) keep(3)nogen
			keep iso3 year age_start age_end sex pop
			keep if age_start>=65
			tempfile pop_65_plus
			save `pop_65_plus', replace
			
			use "pop_custom_age.dta", clear
			drop if age>=65
			rename age age_start
			gen age_end=age_start+10
			replace age_end=4 if age_start==0
			keep iso3 year age_start age_end sex pop
			
			append using `pop_65_plus'
			tempfile pop_custom
			save `pop_custom', replace

		// prep for age split
		use `CHN_sub', clear
		
           //merge on population
            merge 1:m iso3 year using `pop_custom', keep(3) nogen

			//merge on age pattern
			merge m:1 year age_start age_end sex using `CHN_age_pattern', keep(3)nogen

			rename pop sub_pop
			gen rate_sub_pop=rate*sub_pop

            preserve
            collapse (sum) rate_sub_pop, by(iso3 year) fast
            rename rate_sub_pop sum_rate_sub_pop
			tempfile sum
			save `sum', replace

			restore
			merge m:1 iso3 year using `sum', keep(3)nogen

			gen cases=rate_sub_pop*(inc_num_new/sum_rate_sub_pop)

			rename sub_pop sample_size 

			sort iso3 year sex age_start
			
			// keep necessary variables
			
			keep iso3 year age_start age_end sex cases sample_size
			
			// add nid
			
			gen nid=106687 if strpos(iso3,"CHN_")>0 & year==2004
			replace nid=107379 if strpos(iso3,"CHN_")>0 & year==2005
			replace nid=107380 if strpos(iso3,"CHN_")>0 & year==2006
			replace nid=107381 if strpos(iso3,"CHN_")>0 & year==2007
			replace nid=107382 if strpos(iso3,"CHN_")>0 & year==2008
			replace nid=107383 if strpos(iso3,"CHN_")>0 & year==2009
			replace nid=107384 if strpos(iso3,"CHN_")>0 & year==2010
			replace nid=107385 if strpos(iso3,"CHN_")>0 & year==2011
			/* replace nid=107386 if strpos(iso3,"CHN_")>0 & year==2012 - wrong NID */
			replace nid=107378 if strpos(iso3,"CHN_")>0 & year==2012 
			
            // add iso3 code of parent to merge on cdr
			
			gen parent="CHN"
			
	   save "tmp_CHN_CNs.dta", replace

	
	// Prep Mexico 

		** Prep mex data
	
			insheet using "MEX_CNs.csv", clear 
				drop age_end
				rename age age
				keep prov_name tb_cns age year
				rename prov location_name
				replace location="Yucatán" if location=="Yucatan"
				replace location="México" if location=="Mexico" 
				replace location="Chihuahua" if location=="Chilhuahua"
				replace location="Michoacán de Ocampo" if location=="Michoacan"
				replace location="Nuevo León" if location=="Nuevo Leon"
				replace location="Querétaro" if location=="Queretaro" 
				replace location="San Luis Potosí" if location=="SanLuis Potosi"
				replace location="Veracruz de Ignacio de la Llave" if location=="Veracruz" 
				merge m:1 location_name using `tmp_iso_map', keep(3) nogen
				collapse (sum) tb_cns, by(iso3 year)
				preserve
				
				keep if year==1990
			    rename tb_cns inc_num_new
			    tempfile inc_num_1990
			    save `inc_num_1990', replace
			    restore
			
				drop if year==1990
				preserve
				collapse (sum) tb_cns, by(year)
				rename tb_cns inc_MEX
				tempfile tmp_MEX
				save `tmp_MEX', replace
			    restore
				merge m:1 year using "`tmp_MEX'", nogen 
				gen frac_nat=tb_cns/inc_MEX
				keep iso frac year
				tempfile tmp_MEX_fracs
				save `tmp_MEX_fracs', replace 
			    
				
				use `MEX_age_pattern', clear
				collapse (sum) cases_national, by(year) fast
				merge 1:m year using `tmp_MEX_fracs', keep(3)nogen
				** apply fraction
				gen inc_num_new=cases_national*frac
			    append using `inc_num_1990'
				
			    tempfile MEX_sub
				save `MEX_sub', replace
				
						
		** Apply MEX national pattern... 

		
		// prep for age split
		use `MEX_sub', clear
		
           //merge on population
            merge 1:m iso3 year using `pop_custom', keep(3) nogen

			//merge on age pattern
			merge m:1 year age_start age_end sex using `MEX_age_pattern', keep(3)nogen

			rename pop sub_pop
			gen rate_sub_pop=rate*sub_pop

            preserve
            collapse (sum) rate_sub_pop, by(iso3 year) fast
            rename rate_sub_pop sum_rate_sub_pop
			tempfile sum
			save `sum', replace

			restore
			merge m:1 iso3 year using `sum', keep(3)nogen

			gen cases=rate_sub_pop*(inc_num_new/sum_rate_sub_pop)

			rename sub_pop sample_size 

			sort iso3 year sex age_start
			
			// keep necessary variables
			
			keep iso3 year age_start age_end sex cases sample_size
			
			// add nid
			
			gen nid=138133 if strpos(iso3,"MEX_")>0 & year==1990
			replace nid=138281 if strpos(iso3,"MEX_")>0 & year==2011
			replace nid=138283 if strpos(iso3,"MEX_")>0 & year==2012
			
			 // add iso3 code of parent to merge on cdr
			
			gen parent="MEX"
			
		save "tmp_MEX_CNs.dta", replace
	
	// Prep GBR

		** Prep data
	
			insheet using "GBR_TB_CNs_subnational.csv", clear
				keep iso year tb_cases
				
				preserve
				collapse (sum) tb_cases, by(year)
				rename tb_cases inc_GBR
				tempfile tmp_GBR
				save `tmp_GBR', replace
			    restore
				merge m:1 year using "`tmp_GBR'", nogen 
				gen frac_nat=tb_cases/inc_GBR
				keep iso frac year
				tempfile tmp_GBR_fracs
				save `tmp_GBR_fracs', replace 
			    
				
				use `GBR_age_pattern', clear
				collapse (sum) cases_national, by(year) fast
				merge 1:m year using `tmp_GBR_fracs', keep(3)nogen
				** apply fraction
				gen inc_num_new=cases_national*frac
				
				
				//merge on population
            merge 1:m iso3 year using `pop_custom', keep(3) nogen

			//merge on age pattern
			merge m:1 year age_start age_end sex using `GBR_age_pattern', keep(3)nogen

			rename pop sub_pop
			gen rate_sub_pop=rate*sub_pop

            preserve
            collapse (sum) rate_sub_pop, by(iso3 year) fast
            rename rate_sub_pop sum_rate_sub_pop
			tempfile sum
			save `sum', replace

			restore
			merge m:1 iso3 year using `sum', keep(3)nogen

			gen cases=rate_sub_pop*(inc_num_new/sum_rate_sub_pop)

			rename sub_pop sample_size 

			sort iso3 year sex age_start
			
			// keep necessary variables
			
			keep iso3 year age_start age_end sex cases sample_size
			
			// add nid
			
			gen nid=138151 if strpos(iso3,"GBR_")>0 
			
			 // add iso3 code of parent to merge on cdr
			
			gen parent="GBR"
				
		save "tmp_GBR_CNs.dta", replace
	

	// Prep JPN

		** Prep data
	
			insheet using "JPN_subnational_notifications_2012.csv", comma names clear
				gen year=2012
				
				tempfile JPN_2012
				save `JPN_2012', replace
		
			insheet using "JPN_subnational_notifications_2014.csv", comma names clear
				gen year=2014
				
				tempfile JPN_2014
				save `JPN_2014', replace
				
		    use `JPN_2012', clear
			
			append using `JPN_2014'
			
			rename cases inc_num_new
			
		    replace location_name="Hokkaid?" if location_name=="Hokkaido"	
			replace location_name="Hy?go" if location_name=="Hyogo"	
		    replace location_name="K?chi" if location_name=="Kochi"	
			replace location_name="Ky?to" if location_name=="Kyoto"
			replace location_name="Niagata" if location_name=="Niigata"	
			replace location_name="Ôita" if location_name=="Oita"	
			replace location_name="?saka" if location_name=="Osaka"	
			replace location_name="T?ky?" if location_name=="Tokyo"	
			
						
			//merge on location_name
			merge m:1 location_name using `tmp_iso_map', keep(3)nogen
			
		
			//merge on population
            merge 1:m iso3 year using `pop_custom', keep(3) nogen

			//merge on age pattern
			merge m:1 year age_start age_end sex using `JPN_age_pattern', keep(3)nogen

			rename pop sub_pop
			gen rate_sub_pop=rate*sub_pop

            preserve
            collapse (sum) rate_sub_pop, by(iso3 year) fast
            rename rate_sub_pop sum_rate_sub_pop
			tempfile sum
			save `sum', replace

			restore
			merge m:1 iso3 year using `sum', keep(3)nogen

			gen new_cases=rate_sub_pop*(inc_num_new/sum_rate_sub_pop)

			rename sub_pop sample_size 

			sort iso3 year sex age_start
			
			// keep necessary variables
			
		    keep iso3 year age_start age_end sex new_cases sample_size
			rename new_cases cases
			
			 // add iso3 code of parent to merge on cdr
			
			gen parent="JPN"
			
			// add nid
			
			gen nid=205877
			replace nid=206136 if year==2013
			replace nid=206141 if year==2014
				
		save "tmp_JPN_CNs.dta", replace
	
		
		// Append subnationals

		use "tmp_GBR_CNs.dta", clear 
		append using "tmp_MEX_CNs.dta" 
		append using "tmp_CHN_CNs.dta"
		   append using "tmp_JPN_CNs.dta"
		
		// calculate mean and se
		gen mean=cases/sample_size
		gen standard_error=sqrt(mean*(1-mean)/sample_size)
		tempfile subnationals
		save `subnationals', replace
	
		// merge on cdr (5 yr moving average)
		use "moving_imputed_CDR_outlier.dta", clear
        keep iso3 year mean_cdr
		rename iso3 parent
		tempfile cdr_parent
		save `cdr_parent', replace
		
	    use `subnationals', clear
		merge m:1 parent year using `cdr_parent', keep(3)nogen
		
		tempfile subnat_no_cdr_adj
		save `subnat_no_cdr_adj', replace

		save "subnat_no_cdr_adj.dta", replace

	// append national level data

		append using "SUP_xbs_TB_CNs_age_splitted_no_cdr_adj.dta"

		drop if iso3==""

		export excel using "all_TB_CNs_age_splitted.xlsx", firstrow(variables) nolabel replace

	// add location_name

		keep year iso3 sex sample_size age_start age_end nid cases mean standard_error mean_cdr

		merge m:1 iso3 using "iso3.dta", keep(3)nogen

	//format for DisMod
	gen modelable_entity_id=1175
	gen modelable_entity_name="Tuberculosis"

	
	// create CDR bins	

	replace mean_cdr=mean_cdr*100

	generate byte cdr_cat=recode(mean_cdr,10,20,30,40,50,60,70,80,90,100)

	replace cdr_cat=100 if super_region_id==64

	tab cdr_cat, gen(cdr)

	rename cdr1 cv_cdr_0to10
	rename cdr2 cv_cdr_10to20
	rename cdr3 cv_cdr_20to30
	rename cdr4 cv_cdr_30to40
	rename cdr5 cv_cdr_40to50
	rename cdr6 cv_cdr_50to60
	rename cdr7 cv_cdr_60to70
	rename cdr8 cv_cdr_70to80
	rename cdr9 cv_cdr_80to90


	export excel using "\incidence_cdr_bins.xlsx", firstrow(variables) nolabel replace





