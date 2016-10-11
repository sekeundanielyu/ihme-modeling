// Compile FAO age trend results and apply them
	clear all
	macro drop _all
	set maxvar 32000
// Set to run all selected code without pausing
	set more off
// Remove previous restores
	cap restore, not
// Define J drive (data) for cluster (UNIX) and Windows (Windows)
	if c(os) == "Unix" {
		global j "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global j "J:"
	}
	d
// diet information
	local fao_data "J:/WORK/05_risk/risks/diet_general/data/exp/fao/FAO_item_nutrient_modeled_compiled8.dta"
	local database_dir "$j/WORK/05_risk/risks/diet_general/data/exp/compiler"
	local as_dir "J:/WORK/05_risk/risks/diet_general/data/exp/fao/2015_as"
	local tfa "J:/WORK/05_risk/risks/diet_transfat/data/exp/xwalk/output/"
	local output "J:/WORK/05_risk/risks/diet_general/data/exp/fao"
	local inter "`output'/2015_as/intermediate"
	
	//directions for the demographic getting
	local pullfreshnums 0
	local pop_dir "J:/WORK/05_risk/risks/diet_general/data/exp/popnums/"
	
//dynamically set the codefolder between my computer, remote desktop and clustervv	
	if c(os) == "Unix" {
		local codefolder "$j/WORK/05_risk/risks/diet_general/code/fao/age_sex_split/gen_agetrend"
	}
	else if c(os) == "Windows" {
		//will only work on the cdrive for now
		//notepad++ screws with the PWD command trhough its use of include-- making dynamic setting a pain
		local codefolder "J:/WORK/05_risk/risks/diet_general/code/fao/age_sex_split/gen_agetrend"
	}
//get some functions going
	adopath + "$j/WORK/10_gbd/00_library/functions"
	quietly do "J:/WORK/10_gbd/00_library/functions/fastcollapse.ado"
	qui do "J:/WORK/10_gbd/00_library/functions/fastfraction.ado"

local risk_factors diet_grains diet_fish diet_legumes diet_milk diet_nuts diet_redmeat diet_transfat diet_veg diet_fruit diet_calcium diet_fiber diet_pufa diet_satfat
	
tempfile data
save `data', replace emptyok

//format the data a bit
	//clean up data space
	keep age estimate predMale predFemale predBoth risk beta_sex //we're dropping upper and lowers until such time we can figure out how to use them
	
	//reshape the dataset long by sex
	reshape long pred, i(age estimate beta_sex  risk) j(sex) string
	
	//set ages less than 2 to 0 -- babies are breast feeding and shouldn't count in the split
	//this basically means ages 0 .01 .1
	replace pred = 0 if age<1
	
	gen age_group_id = .
	{
		tostring age, replace force format(%8.0g)
		replace age_group_id =2 if age=="0"
		replace age_group_id =3 if age==".01"
		replace age_group_id =4 if age==".1"
		replace age_group_id =5 if age=="1"
		replace age_group_id =7.5 if age=="10"
		replace age_group_id =9.5 if age=="20"
		replace age_group_id =11.5 if age=="30"
		replace age_group_id =13.5 if age=="40"
		replace age_group_id =15.5 if age=="50"
		replace age_group_id =17.5 if age=="60"
		replace age_group_id =19.5 if age=="70"
		replace age_group_id =21 if age=="80"
	}
	//save the data
	save `data', replace

//format population numbers
	// Get Epi locations
	adopath + "$j/WORK/10_gbd/00_library/functions"
	get_location_metadata,location_set_id(9) clear
	levelsof location_set_version_id, local(locver)
	tempfile locs
	save `locs', replace
	
	//get the numbers
	local population "`pop_dir'/pops_fao_as.dta"
	if `pullfreshnums'==1{
		do "$j/WORK/05_risk/risks/diet_general/code/pull_2015_populations.ado" 
		pull_2015_populations,locsetver("`locver'")
		keep if year_id>=1988
		keep if is_aggregate==0
		keep if inrange(age_group_id,2,21)
		keep if sex_id == 3
		local counter = 7
		forvalues x = 1/7 {
		preserve
			keep if age_group_id == `counter' | age_group_id == `counter' + 1
			sort 		year_id location_id 
			quietly by 	year_id location_id: egen sum_mean_pop = sum(mean_pop)
			drop mean_pop
			rename sum_mean_pop mean_pop
			drop if age_group_id == `counter' + 1
			replace age_group_id = (`counter' + `counter' + 1) / 2
			replace age_group_years_end = age_group_years_end + 5
			tempfile `counter'
			save ``counter''
			local counter = `counter' + 2
		restore
		}
		forvalues x = 7/20 {
			drop if age_group_id == `x'
		}
		local age_group_ids 7 9 11 13 15 17 19
		foreach age of local age_group_ids {
			append using ``age''
		}

		sort year_id location_id age_group_id

		save "`population'", replace
	}
	else{
		use `population', clear
	}

	
//bring in fao estimates
	//format fao data so that it can merge with the pop numbers
	use `fao_data', clear
	**rename sd_resid standard_error
	gen standard_error = (variance)^(1/2)
	**rename grams_daily exp_mean
	rename mean_value exp_mean
	keep location_id year exp_mean standard_error risk
	keep if year>=1988
	
	//rename to make them consistant with gdb
	replace risk = "diet_"+risk
	replace risk = "diet_nuts" if risk=="diet_nuts_seeds"
	replace risk = "diet_legumes" if risk == "diet_pulses_legumes"
	replace risk = "diet_redmeat" if risk == "diet_red_meats"
	replace risk = "diet_veg" if risk == "diet_vegetables"
	replace risk = "diet_grains" if risk=="diet_whole_grains"
	replace risk = "diet_fruit" if risk == "diet_fruits"
	
	//interactive coding suggests that there are five datapoints with no se. No idea how it happened, but drop them
	count if standard_error ==.
	if `r(N)' >5{
		di as error "Greater than expected droppage"
		asdf
	}
	drop if standard_error ==.
	
	//make sure there is no missing data
	check_missing *
	
	//tempfile the data. Technically, the following steps could all be done at once, but that seems more complicated (I trust merge more than joinby)
	tempfile tosplit
	save `tosplit', replace
	
//age sex split the risk factors
	foreach risk of local risk_factors{
		use `tosplit', clear
		keep if risk == "`risk'"
		
		rename year year_id
		count
		//merge in the predictions
		joinby risk using `data'
		
		merge 1:m location_id year_id sex age_group_id using `population', keep(3) nogen keepusing(mean_pop age_group_years*) //we're essentially adding in age and sex by population
		
		//generate total pop
		bysort location_id year_id : egen total_pop = total(mean_pop)
		
		//generate total consumption
		gen group_consumption = pred*mean_pop
		bysort location_id year_id : egen total_consumption = total(group_consumption)
		gen new_percapita = total_consumption/total_pop
		
		//what is the ratio of the group relative to the whole
		gen scalar =pred/new_percapita
		
		gen new_exp_mean = scalar*exp_mean
		gen adj_se = standard_error*sqrt(9) //each fao datapoint has become 9 new datapoints. Thus, we are less certain. 
		keep if sex == "Both"
		// Split out standard errors using "coefficient of variation" (in quotations because CV is technically the SD/MEAN, but we don't have SD so skipping that step since there's no sample size for FAO/TFA data) from the original mean, then multiplying it by the new mean
		//this logic is borrowed from the previous method
		gen CV = adj_se / exp_mean 
		gen new_se = CV * new_exp_mean //all this does is make se a function of age
		
		
		save "`inter'/as_split_`risk'.dta", replace
	}

//Append all the outputs together, get them ready for the diet_compilier
	clear
	foreach risk of local risk_factors{
		append using "`inter'/as_split_`risk'.dta"
	}
	
	//save an intermediate full dataset
	save "`inter'/as_split_all_v`version'.dta", replace
	
	//clean up the dataset
	keep year_id new_se sex age_group* new_exp_mean location_id risk age
	gen year_start= year_id
	gen year_end = year_id
	rename year_id year
	
	gen sex_id = 3
	drop sex
	rename sex_id sex
	
	gen age_start = age_group_years_start
	gen age_end = age_group_years_end

	drop age_group_id
	
	//save results
	save "`output'/as_2015_`version'.dta", replace
