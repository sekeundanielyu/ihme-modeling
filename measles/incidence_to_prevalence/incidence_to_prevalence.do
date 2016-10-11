
** Purpose: convert measles cases to prevalence and incidence 

// setup

// settings
	clear all
	set more off
	cap restore
	cap log close
	
// locals
	
	local acause measles
	local custom_version v19   
	local age_start=2     
	local age_end=16    

	
// get population data

	adopath + $prefix/Project/Mortality/shared/functions
	get_env_results
	keep year_id location_id sex_id age_group_id mean_pop 
	rename year_id year
	rename sex_id sex
	drop if age_group_id>21
	drop if year<1980
	drop if sex==3
	rename mean_pop pop
	tempfile pop
	save `pop', replace
	
	
// get the cases draws 
	use "age_sex_split_files/cases_draws.dta", clear 

// add age group ids
	gen age_group_id=.
	replace age_group_id=2 if age==0
	replace age_group_id=3 if age>0 & age<0.1
	replace age_group_id=4 if age>0.05 & age<1
	replace age_group_id=5 if age==1
	replace age_group_id=6 if age==5
	replace age_group_id=7 if age==10
	replace age_group_id=8 if age==15
	replace age_group_id=9 if age==20
	replace age_group_id=10 if age==25
	replace age_group_id=11 if age==30
	replace age_group_id=12 if age==35
	replace age_group_id=13 if age==40
	replace age_group_id=14 if age==45
	replace age_group_id=15 if age==50
	replace age_group_id=16 if age==55
	replace age_group_id=17 if age==60
	replace age_group_id=18 if age==65
	replace age_group_id=19 if age==70
	replace age_group_id=20 if age==75
	replace age_group_id=21 if age==80

	merge 1:1 location_id year age_group_id sex using `pop', keep(3) nogen 
	keep if year==1990 | year==1995 | year==2000 | year==2005 | year==2010 | year==2013 | year==2015
// if estmiated cases=0, age-sex splitting often yielded missing values. Replace them with zeros. 
	foreach a of varlist draw_1-draw_1000 {
		replace `a'=0 if `a'==.
		}
	tempfile cases
	save `cases', replace

// convert incidence cases to prevalence, duration of 10 days

	forvalues x= 1/1000 {
		replace draw_`x' = (draw_`x'*(10/365))/pop
		}

	save "`outdir'/prevalence_draws.dta", replace		
		
// convert incidence cases to incidence rate
	use `cases', clear
	forvalues x= 1/1000 {
		replace draw_`x' = draw_`x'/pop
		}

	save "incidence_draws.dta", replace			
		

