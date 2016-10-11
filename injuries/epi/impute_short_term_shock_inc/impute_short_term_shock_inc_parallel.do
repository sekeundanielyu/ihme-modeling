// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	This file will calculate incidence of injury due to war or disease given a country, year, sex, inpatient level using mortality and incidence due to other injuries (road traffic, homicide, fire, other unintentional)

** *********************************************
// DON'T EDIT - prep stata

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	
// Global can't be passed from master when called in parallel
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "03a"
		local 5 impute_short_term_shock_inc
		local 6 "/share/code/injuries/strUser/inj/gbd2015"
		local 7 160
		local 8 2
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
    // directory where the code lives
    local code_dir `6'
    // country
    local location_id `7'
    // sex 
    local sex_id `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	
	// write log if running in parallel and log is not already open
	cap log using "`out_dir'/02_temp/02_logs/`step_num'_`location_id'_`sex_id'.smcl", replace name(worker)
	if !_rc local close_log 1
	else local close_log 0

	// check for finished.txt produced by previous step
	if "`hold_steps'" != "" {
		foreach step of local hold_steps {
			local dir: dir "`root_j_dir'/03_steps/`date'" dirs "`step'_*", respectcase
			// remove extra quotation marks
			local dir = subinstr(`"`dir'"',`"""',"",.)
			capture confirm file "`root_j_dir'/03_steps/`date'/`dir'/finished.txt"
			if _rc {
				di "`dir' failed"
				BREAK
			}
		}
	}

	
// *******************************************************************************************************************************************************************

// Import GBD functions
	// local gbd_ado "$prefix/WORK/04_epi/01_database/01_code/00_library/ado"
local gbd_ado "/snfs1/WORK/10_gbd/00_library/functions"
local diag_dir "`out_dir'/02_temp/04_diagnostics"
adopath + `gbd_ado'
adopath + "`code_dir'/ado"

// Load GBD parameters
load_params

** need to re-code sex to 1/2
if "`sex'"=="male" {
local sexnum 1
}	
if "`sex'"=="female" {
local sexnum 2
}

// Load map of ME ids 
insheet using "`code_dir'/master_injury_me_ids.csv", comma names clear
keep if injury_metric == "Adjusted data"
tempfile me_map
save `me_map', replace

** store all the years we have modeled data for in the cod and epi databases
foreach dbase in cod epi {
get_demographics , gbd_team(`dbase') make_template clear
local `dbase'_years = ""
foreach year_id of global year_ids {
	local `dbase'_years = "``dbase'_years' "+"`year_id'"
	}
keep year_id
rename year_id years
summ years
local `dbase'_years_min = r(min)	
tempfile `dbase'_years_map
save ``dbase'_years_map', replace
}
di "`epi_years'"
di "`cod_years'"

	** make sure you are storing epi demographics in 
get_demographics , gbd_team(epi) make_template clear
	// local all_ages = "$full_ages" + " 80"
	
	** need to pull the step number of the step whose results we're pulling, because these might change
local last_name raw_nonshock_short_term_ecode_inc_by_platform
import excel using "`code_dir'/_inj_steps.xlsx", firstrow clear
keep if name=="`last_name'"
local last_step=step in 1
	// global pull_results_dir "/clustertmp/WORK/04_epi/01_database/02_data/`functional'/04_models/`gbd'/03_steps/`date'/`last_step'_`last_name'/03_outputs/01_draws/"
global pull_results_dir "/share/injuries/03_steps/`date'/`last_step'_`last_name'/03_outputs/01_draws/"
	
	** load imputation relationships from parameters
	insheet using "`in_dir'/parameters/ecode_imputation_relationships.csv", comma names clear
	** store the e_codes in memory to cycle through them, submitting jobs
	levelsof imputed_ecode, local(imputed_ecodes) clean

capture ssc install sxpose
sxpose, firstnames clear
tempfile relationships
save `relationships', replace
	
	** get population data for subnational mortality denominators- these only go up to 80+
	// use if iso3=="`iso3'" & sex == `sexnum' & age<=80 using "$prefix/WORK/02_mortality/04_outputs/02_results/envelope.dta", clear
get_demographics, gbd_team(cod)
get_populations , location_id(`location_id') sex_id(`sex_id') year_id($year_ids) age_group_id($age_group_ids) clear
keep year_id age_group_id pop_scaled
	// gen double mort_age = round(age, .01)
	// drop age
tempfile pop_numbers
save `pop_numbers', replace

// Get relevant ids for draw calls
	get_ids, table(measure) clear
		keep if measure_name == "Deaths"
		local cod_measure_id = measure_id
	get_ids, table(metric) clear
		keep if metric_name == "Number"
		local cod_metric_id = metric_id

local noshock_counter=0
local save_counter=0
	foreach shock_e_code of local imputed_ecodes {
		di "in loop for `shock_e_code'"
			
			** these are the way the mortality numbers are designated in the shocks database
			if "`shock_e_code'"=="inj_war" {
				local shock_type war
			}
			if "`shock_e_code'"=="inj_disaster" {
				local shock_type disaster
			}
			
			use `relationships', clear
			
			levelsof `shock_e_code', local(impute_from) clean		
			levelsof `shock_e_code', local(impute_from_punct) sep(,)		
			
			** bring in war / disaster shock data for this cause
			di "getting shock results for `iso3' from $shocks_results"
			create_connection_string, strConnection
			local conn_string = r(conn_string)
			odbc load, exec("SELECT acause, cause_id FROM shared.cause;") `conn_string' clear
				keep if acause == "`shock_e_code'"
				local cause_id = cause_id
			get_demographics, gbd_team(cod)
			get_best_model_versions, gbd_team(cod) id_list(`cause_id') clear
				keep if sex_id == `sex_id'
				local best_model_version = model_version_id
			get_populations, year_id($year_ids) location_id(`location_id') sex_id(`sex_id') age_group_id($age_group_ids) clear
				tempfile cod_pops
				save `cod_pops', replace
			get_draws, gbd_id_field(cause_id) gbd_id(`cause_id') location_ids(`location_id') sex_ids(`sex_id') year_ids($year_ids) status(best) age_group_ids($age_group_ids) source(dalynator) kwargs(version:108) clear
				//keep if model_version_id == `best_model_version'
				keep if sex_id == `sex_id'
				keep if measure_id == `cod_measure_id'
				keep if metric_id == `cod_metric_id'
				if `sex_id' == 2 {
					cap drop if rei_id == 168
				}
				merge 1:1 location_id year_id sex_id age_group_id using `cod_pops', keep(3) nogen

			// use age year shock* types iso3 sex if (types=="`shock_type'" & iso3=="`mort_iso3'" & sex=="`sex'") using "$shocks_results", clear
			// keep age year shock*
			keep age year draw_* pop 
			di "got shock results for `iso3' `shock_type'"
			** rename the shocks names so we can loop through them
			preserve
			describe, replace clear
			// keep if regexm(name, "shocks")
			keep if regexm(name, "draw")
			clear mata
			putmata name, replace
			restore
			quietly {
			forvalues j=0(1)999 {
			local i=`j'+1
			mata: st_local("name",name[`i'])
			rename `name' shock_draw_`j'
			}
			}
			
			di "saving shocks data"
			** if there's no shock mortality data for this sex/location, don't create any new files
			count
			if `r(N)'==0 {
				di "there is no shock mortality data for this sex/location for `shock_type'"
				local ++noshock_counter
			}
			
			** first impute incidence/mortality for all years we have shocks for, save to clustertmp
			else {
				** get the years that we want to impute to				
				levelsof year, local(shock_years)
				display "in loop for `shock_e_code'"
				display "shock years: `shock_years'"
				** merge on national population figures and generate national mortality rate for this shock cause
				// merge 1:1 mort_age year using `nat_pop_numbers', keepusing(mean_pop) keep(3) nogen
				// merge 1:1 age_group_id year_id using `pop_numbers', keepusing(pop_scaled) keep(3) nogen
				// WE HAVE POPS IN GET_DRAWS NOW
				forvalues j=0(1)999 {
				quietly replace shock_draw_`j'=shock_draw_`j'/pop
				}
				drop pop
				tempfile shock_mort
				save `shock_mort'
				** grab raw death and incidence estimates for years with shock data for the e-codes that we are imputing from
				foreach year of local shock_years {
				
					** cod models are stored by E-code so we need to bring those in seperately
					local codcount=1
					foreach modeled_code of local impute_from {
					** need the best model number for this cause of death
						//di "getting best CoD model for `modeled_code'"
						//use	if acause=="`modeled_code'" & sex_id==`sexnum' using "`out_dir'/01_inputs/cod_model_specs.dta", clear
						//gsort - model_version_id
						//local model_num = model_version_id in 1	
						odbc load, exec("SELECT acause, cause_id FROM shared.cause;") `conn_string' clear
						keep if acause == "`modeled_code'"
						local cause_id = cause_id
						get_best_model_versions, gbd_team(cod) id_list(`cause_id') clear
						keep if sex_id == `sex_id'
						keep if regexm(description, "Hybrid") == 1 // REMOVE THIS ONCE I FIGURE OUT HOW TO GET THE HYBRID+SHOCKS MODEL - DO I NEED TO ADD BOTH BEST MODELS TOGETHER?
						local best_model_version = model_version_id
						di "best CoD model for `modeled_code' is `best_model_version'"
						** now bring in the cause of death and incidence results for this cause for all years so we can impute them
						** Copy over cod data for this year if we have it (we have it for every year 1980-2013)
						** if this year is earlier than the earliest results we have for epi results, save the earliest version of our results	
						if `year' < `epi_years_min' {
							get_draws, gbd_id_field(cause_id) gbd_id(`cause_id') location_ids(`location_id') sex_ids(`sex_id') year_ids(`epi_years_min') status(best) source(dalynator) kwargs(version:108) clear
						}
						else {
							get_draws, gbd_id_field(cause_id) gbd_id(`cause_id') location_ids(`location_id') sex_ids(`sex_id') year_ids(`year') status(best) source(dalynator) kwargs(version:108) clear
						}
						keep if measure_id == `cod_measure_id'
						keep if metric_id == `cod_metric_id'
						if `sex_id' == 2 {
							cap drop if rei_id == 168 // some PAF results?
						}
						merge 1:1 location_id year_id sex_id age_group_id using `cod_pops', keep(3) nogen

							** confirm that there are 1000 draws
							capture confirm variable draw_999
							** if there are not, we need to sample more to have 1000
							if _rc {
								tempfile some_deaths
								save `some_deaths', replace

								quietly reshape long draw_, i(age) j(drawnum)
								
								** figure out how many more we need to generate from the existing draws
								summ drawnum
								local drawmax=`r(max)'
								local to_gen = 999-`drawmax'-1

								** make a list of new variables to make
								local new_draws ""
								forvalues i=0/`to_gen' {
									local num=999-`i'
									local new_draws = "`new_draws'" + " draw_`num'"
								}
								di "highest draw is: draw_`drawmax'"
								di "need to make: `new_draws'"
									
								** get the mean, sd of the draws to generate new ones
								collapse (mean) mean=draw_ (sd) sd=draw_, by(age)
								di "`new_draws'"
								foreach ndrw of local new_draws {
									di "`ndrw'"
									generate `ndrw' = rnormal(mean, sd)
								}
								drop mean sd
								merge 1:1 age using `some_deaths', nogen
								order `new_draws', last
								confirm variable draw_999
								di "successfully created draw_999"
							}
							// save ``tempfile'', replace
						//}	
						keep age draw_* year_id sex_id pop
						tempfile this_yr
						save `this_yr', replace

						** bring in the (subnational) populations so we calculate the (subnational) mortality rate instead of straight number of deaths
						if `year'<`epi_years_min' {
							replace year=`epi_years_min'
						}
						// merge 1:m mort_age year using `pop_numbers', keep(3) nogen
						di in red "merged subnational cause-specific mortality on subnational populations"
						forvalues j=0(1)999 {
							quietly replace draw_`j'=draw_`j'/pop
						}
						capture replace year = `year'
						rename draw* mort_draw*
						// rename mort_age age
						// gen double mort_age = round(age, .01)
						// drop age mean_pop
						drop pop
						gen ecode = "`modeled_code'"
						di "saving tempfile `year'_mortr"
						if `codcount'==1 {
							tempfile `year'_mortr
							save ``year'_mortr', replace
							local ++codcount							
						}
						else {
							append using ``year'_mortr'
							save  ``year'_mortr', replace
							local ++codcount
							levelsof ecode
						}
					}
					** end loop saving COD data for this year for all e-codes
						
					** Calculate incidence for all e-codes for this year - if it is earlier than our earliest year, then use the lowest year; need to interpolate for years between Dismod years
					if `year'<=`epi_years_min' {
						clear
						tempfile `year'_inc
						save ``year'_inc', emptyok
						foreach dismod_code of local impute_from {
							use `me_map' if e_code == "`dismod_code'", clear
							local me_id = modelable_entity_id
							import delimited using "$pull_results_dir/incidence_`location_id'_`epi_years_min'_`sex_id'.csv", delim(",") varnames(1) clear asdouble 
							keep if ecode == "`dismod_code'"
							drop if age_group_id > 21
							append using ``year'_inc'
							save ``year'_inc', replace
						}
					}

					** otherwise, calculate the linear interpolation between the two closest years to get estimated incidence for this year
					else {
						** if this is for a year we have incidence numbers for, just save it over
						get_demographics , gbd_team(epi)
						if regexm("`epi_years'", "`year'") == 1 {
							di "`year' is in `epi_years'"
							di "pulling incidence results for `location_id' `year_id'"
							clear
							tempfile `year'_inc
							save ``year'_inc', emptyok
							foreach dismod_code of local impute_from {
								use `me_map' if e_code == "`dismod_code'", clear
								local me_id = modelable_entity_id
								import delimited using "$pull_results_dir/incidence_`location_id'_`year'_`sex_id'.csv", delim(",") varnames(1) clear asdouble 
								keep if ecode == "`dismod_code'"
								gen modelable_entity_id = `me_id'
								drop if age_group_id > 21
								append using ``year'_inc'
								save ``year'_inc', replace
							}
						}
						** otherwise, find the two closest years, interpolate between them from the incidence data for how much should be added/subtracted for the five years
						else {
							use `epi_years_map', clear
							duplicates drop 
							// if (`year'<2010) drop if years==2013
							gen year_diff=abs(years-`year')
							sort year_diff
							keep in 1/2
							sort years
							local lower_year=years in 1
							local upper_year=years in 2
							local diff_between_years=`upper_year'-`lower_year'
							local years_to_add = `year' - `lower_year'
							di "`year'"
							di "`upper_year'"
							di "`lower_year'"
							clear
							tempfile lower_year_data
							save `lower_year_data', emptyok
							foreach dismod_code of local impute_from {
								use `me_map' if e_code == "`dismod_code'", clear
								local me_id = modelable_entity_id
								import delimited using "$pull_results_dir/incidence_`location_id'_`lower_year'_`sex_id'.csv", delim(",") varnames(1) clear asdouble 
								keep if ecode == "`dismod_code'"
								gen modelable_entity_id = `me_id'
								drop if age_group_id > 21
								rename draw* y`lower_year'_draw*
								append using `lower_year_data'
								save `lower_year_data', replace
							}
							clear
							tempfile upper_year_data
							save `upper_year_data', emptyok
							foreach dismod_code of local impute_from {
								use `me_map' if e_code == "`dismod_code'", clear
								local me_id = modelable_entity_id
								import delimited using "$pull_results_dir/incidence_`location_id'_`upper_year'_`sex_id'.csv", delim(",") varnames(1) clear asdouble 
								keep if ecode == "`dismod_code'"
								gen modelable_entity_id = `me_id'
								drop if age_group_id > 21
								rename draw* y`upper_year'_draw*
								append using `upper_year_data'
								save `upper_year_data', replace
							}
							merge 1:1 age modelable_entity_id inpatient using `lower_year_data', keep(3) nogen
							
							** how to interpolate from charles:
							** We will first calculate the mean % change for the five-year interval (e.g. 1990 to 1995); we use means for the rate of change, rather than draw-for-draw rate of change, because it leads to more stable interpolation estimates
							** We then apply the mean rate of change between 1990 and 1995 to each of the 1000 draws from 1990 to get 1991/1992/1993/1994 using this equation: draw#_1991 =  draw#_1990 * exp(1)^ln[mean_1995 / mean_1990) * (1991 - 1990) / (1995 - 1990)]							
							egen mean_`lower_year' = rowmean( y`lower_year'_draw*)
							egen mean_`upper_year' = rowmean( y`upper_year'_draw*)
							forvalues j=0(1)999 {
								quietly generate y`year'_draw_`j' = y`lower_year'_draw_`j' * exp(1)^ln((mean_`upper_year'/mean_`lower_year') * (`years_to_add'/`diff_between_years'))
								drop y`lower_year'_draw_`j' y`upper_year'_draw_`j'
							}
							drop mean_`upper_year' mean_`lower_year'
							capture drop year
							generate year =`year'
							rename y`year'_draw* draw*
							di "saving tempfile `year'_inc"
							tempfile `year'_inc
							save ``year'_inc', replace
							
						}
						** end block for saving imputed incidence data from between years
						}
					** end block for saving incidence data for years later than the earliest year we have results for
			di "finished loop saving incidence & cod numbers for `year' for this data"
				di "`year'_inc"
				
				use ``year'_inc', clear
				count
				summ draw_1
				rename draw* inc_draw*
				//gen double mort_age = round(age, .01)
				//replace mort_age = 80 if age>=80
				merge m:1 age_group_id ecode using ``year'_mortr', keep(3) nogen
					
				display "merge on line 396"					
				di "adding incidence to mortality for `year'"
									
				forvalues j=0(1)999 {
					gen ratio_`j' = inc_draw_`j' / mort_draw_`j'
					drop inc_draw_`j' mort_draw_`j'
				}
				tempfile modeled_ratios
				save `modeled_ratios', replace
	
				di "calculating ratios"
				** calculate the mean incidence-to-mortality ratio across your e-codes with known incidence
				use `modeled_ratios', clear

				levelsof ecode
				levelsof inpatient
				
				// EDIT 6/29/16 NG: this imputation is coming out crazy for ages <1, where any ratio too far above 1 is just not plausible (but definitely possible given the relationships we impose with fires, violence, road traffic, and other unintentional). Average ratio for all ages below 1 to stop the earliest age group from exploding.
				replace age_group_id = 2 if age_group_id <= 4

				collapse (mean) ratio_*, by(age_group_id inpatient)
				isid age_group_id inpatient
				//levelsof mort_age
				levelsof age_group_id
				expand 2 if age_group_id == 2, gen(dup)
					replace age_group_id = 3 if dup == 1 
					drop dup
				expand 2 if age_group_id == 2, gen(dup)
					replace age_group_id = 4 if dup == 1 
					drop dup				

				// SAVE RATIOS FOR DIAGNOSTICS 
				cap mkdir "`root_tmp_dir'/03_steps/`date'/03a_impute_short_term_shock_inc/03_outputs/03_other/mi_ratios/`shock_e_code'/`location_id'"
				save "`root_tmp_dir'/03_steps/`date'/03a_impute_short_term_shock_inc/03_outputs/03_other/mi_ratios/`shock_e_code'/`location_id'/ratio_`location_id'_`year'_`sex_id'.dta", replace

				tempfile ratios
				save `ratios', replace
				
				** grab your shock ecode mortality for this year
				use if year == `year' using `shock_mort', clear
				merge 1:m age_group_id using `ratios', keep(3) nogen
				di "imputing shock incidence for `year' `shock_e_code' `platform'"
				forvalues j=0(1)999 {
					gen shock_inc_`j'= shock_draw_`j'*ratio_`j'
					drop shock_draw_`j' ratio_`j'
				}			
				rename shock_inc_* draw_*
				format draw* %16.0g
				fastrowmean draw*, mean_var_name("mean")
				fastpctile draw*, pct(2.5 97.5) names(ll ul)
				codebook year
				di `year'
				capture drop year
				capture drop sex
				capture drop mort_age
				capture drop mort_draw*
				generate year = `year'
				capture gen ecode = "`shock_e_code'"
				local ++save_counter
				
				if `save_counter'==1 {
					tempfile all_appended
					save `all_appended', replace
				}
				if `save_counter'>1 {
					append using `all_appended'
					save `all_appended', replace
				}
				
			}
			** end loop for year
		}
		** end block for years with shock data
	}
** end shock_e_code loop

di `noshock_counter'
if `noshock_counter'<2 {
	use `all_appended', clear

	isid age ecode inpatient year

	foreach platform in inp otp {
		if "`platform'"=="inp" {
			local platnum=1
		}	
		if "`platform'"=="otp" {
			local platnum=0
		}
		preserve
		keep if inpatient==`platnum'	
		order age ecode year, first
		sort ecode year age
		export delimited age ecode year draw_*  using "`tmp_dir'/03_outputs/01_draws/incidence_`location_id'_`platform'_`sex_id'.csv", delim(",") replace
		keep age year ecode mean ul ll
		save  "`tmp_dir'/03_outputs/02_summary/incidence_`location_id'_`platform'_`sex_id'.dta", replace
		restore
	}

}

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// CHECK FILES (NO NEED TO EDIT THIS SECTION)

	// write check file to indicate sub-step has finished
		file open finished using "`tmp_dir'/02_temp/01_code/checks/finished_`location_id'_`sex'.txt", replace write
		file close finished
	
	log close worker
	erase "`out_dir'/02_temp/02_logs/`step_num'_`location_id'_`sex_id'.smcl"
	
	