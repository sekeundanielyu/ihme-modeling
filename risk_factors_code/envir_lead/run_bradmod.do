///////////////////////////////////////////////////////////////////////////////////////////////////
////                                                                                          /////
//// Purpose: Prepare and Run RRs through BradMod (DisMod without the hierarchy)              /////
//// Project: GBD Risk Factors                                                                /////
////                                                                                          /////
///////////////////////////////////////////////////////////////////////////////////////////////////

clear all
set more off

///////////////////
////  Setup OS ////
///////////////////

* set J and path to the dismod suite
if c(os)=="Unix" {
	global j "FILEPATH"
	local dismodlink FILEPATH
}

else {
	global j "J:"
	local dismodlink FILEPATH
}

local project "lead_exp" 

//////////////////////
//// Set Paths    ////
//////////////////////

*Need data_in, effect_in, plain_in, rate_in, & value_in. See .txt file for information on these

global bradmod_dir "FILEPATH" //input folder to your input dataset
global input_file 	"compiled_imputed_sd" //filename of the input dataset
global input_folder	"FILEPATH" //
local code_folder  	"FILEPATH"

*Options for creating files if needed
local make_data 	1
local make_effect 	1
local make_plain 	0 // 1
local make_rate 	1
local make_value 	1
local make_model 	1

///////////////////////////////
//// Set DisMod Parameters ////
///////////////////////////////
 
global num_sample	6000 //
global mesh 0 0.02 0.083 1 5 10 15 20 25 30 35 40 45 50 55 60 65 70 75 80 85 90 95 100 //these are the age mesh points for which bradmod will produce predictions for
global sample_interval	10 //
global proportion 1 // 
local integrand "prevalence" //either prevalence or incidence
local data_transform "log_gaussian"
local data_type_pred "gaussian"

////////////////////////////
//// Prep data_in.csv   ////
////////////////////////////

**See .txt for required columns. This only appends on supplemental rows needed.
if `make_data' == 1 {
	*Make mtall rows for mesh points
	local mesh $mesh
	local inputfolder $inputfolder

	tokenize `mesh'
	local count: word count $mesh
	local count = `count' - 1

	import delimited "FILEPATH", clear

	*Need age_upper and age_lower
	cap rename age_start age_lower
	cap rename age_end age_upper

	*Need super, region, subreg variables
	cap gen super = "."
	cap gen region = "."
	cap gen subreg = "."

	*Need integrand variable (currently set to incidence for its feature of being continuous)
	cap gen integrand = "`integrand'"

	*Need time_lower & time_upper variables
	gen time_lower = year_start
	gen time_upper = year_end

	*Need data_like variable
	gen data_like = "`data_transform'"

	*Need x_sex variable
	gen x_sex = 0 if sex == "Both"
		replace x_sex = .5 if sex == "Male"
		replace x_sex = -.5 if sex == "Female"

	cap destring age_lower, replace
	cap destring age_upper, replace

	gen x_ones=1

	*Need meas_value & meas_stdev variables
	gen meas_value = mean
	gen meas_stdev = standard_error
	destring meas_stdev, force replace
	destring upper, force replace
	destring lower, force replace
	*estimate st_dev from upper and lower
	*replace meas_stdev = (upper - lower)/(2*1.96) if meas_stdev == . // data has standard errors imputed already
	*set cut-point so it will not break
	replace meas_stdev = 0.01 if meas_stdev<=0
	tostring meas_stdev, replace force

	local o = _N

	forvalues i = 1/`count' {
		local o = `o' + 1	
		set obs `o'
		replace integrand = "mtall" in `o'
		replace super = "none" in `o'
		replace region = "none" in `o'
		replace subreg = "none" in `o'
		replace time_lower = 2000 in `o'
		replace time_upper = 2000 in `o'
		replace age_lower = ``i'' in `o'
		replace data_like = "log_gaussian" in `o'
		local next = `i'+1
		replace age_upper = ``next'' in `o'
		replace x_sex = 0 in `o'
		replace x_ones = 0 in `o'
		replace meas_value = .01 in `o'
		replace meas_stdev = "inf" in `o'
	}

	*Export
	outsheet using "$input_folder/data_in.csv", comma replace
}

else {
	insheet using "$input_folder/data_in.csv"
}

/////////////////////////////////////////////////////////
//// Prep effect_in, rate_in, value_in, and plain_in ////
/////////////////////////////////////////////////////////

local studycovs
foreach var of varlist x_* {
	local studycovs "`studycovs' `var'"
}

global studycovs `studycovs'
global prjfolder $bradmod_dir

if `make_effect' == 1 {
	do "`code_folder'/make_effect_ins.do"
}

if `make_rate' == 1 {
	do "`code_folder'/make_rate_ins.do"
}

if `make_value' == 1 {
	do "`code_folder'/make_value_in.do"
}

if `make_plain' == 1{
	do "`code_folder'/make_plain_in.do"
}

if `make_model' == 1 {

	*Make template, then populate with mesh & studies
	insheet using "$input_folder/data_in.csv", clear
	local mesh $mesh

	clear

	*Make base variables
	local o = 1
	gen subreg = ""
	gen age_lower = .
	gen age_upper = .
	gen integrand = "`integrand'"
	gen meas_value = 0
	gen meas_stdev = "inf"
	gen region = "none"
	gen super = "none"
	gen x_ones = 1
	gen data_like = "gaussian"

		foreach j in `mesh'{
			set obs `o'
			replace subreg = "." in `o'
			replace age_lower = `j' in `o'
			replace age_upper = `j' in `o'
			replace integrand = "incidence" in `o'
			replace meas_value = 0 in `o'
			replace meas_stdev = "inf" in `o'
			replace region = "none" in `o'
			replace super = "none" in `o'
			replace x_ones = 1 in `o'
			replace data_like = "gaussian" in `o'
			local o = `o'+1
		}
	
	*Add mtall
	foreach j in `mesh'{
			set obs `o'
			replace subreg = "none" in `o'
			replace age_lower = `j' in `o'
			replace age_upper = `j' in `o'
			replace integrand = "mtall" in `o'
			replace meas_value = 0 in `o'
			replace meas_stdev = "inf" in `o'
			replace region = "none" in `o'
			replace super = "none" in `o'
			replace x_ones = 0 in `o'
			replace data_like = "gaussian" in `o'
			local o = `o'+1
	}

	outsheet using  "$input_folder/model_in.csv", comma replace	
}

else {
	insheet using  "$input_folder/model_in.csv", comma clear
}

/////////////////////////////////////
//// Prep prediction frame       ////
/////////////////////////////////////

*Match mesh points within prediction inputs
insheet using "FILEPATH", comma clear case

if $proportion == 1 keep if integrand == "prevalence"
if $proportion == 0 keep if integrand == "incidence"
foreach var of local studycovs {
	capture gen `var' = 0
}

keep in 1

tokenize $mesh
local count: word count $mesh
local count = `count' - 1

forvalues i = 1/`count' {
	expand 2 in 1
	local next = `i'+1 
	replace age_lower = ``i'' in `i'
	replace age_upper = ``next'' in `i'
}

local o = _N
drop in `o'
cap gen data_like = "`data_type_pred'"

outsheet using "FILEPATH", comma replace

cd "$input_folder"

*Connect to dismod and run model
	
! `dismodlink'/sample_post.py

insheet using "FILEPATH", comma clear
	foreach var of local studycovs {
			cap gen `var' = 0
	}

	gen row_name = "null"
	rename x_y_2013 x_y_2015
outsheet using "$input_folder/draw_in.csv", comma replace

	! `dismodlink'/stat_post.py scale_beta=false	
	! `dismodlink'/data_pred data_in.csv value_in.csv plain_in.csv rate_tmp.csv effect_in.csv sample_out.csv data_pred.csv
	! `dismodlink'/data_pred pred_in.csv value_in.csv plain_in.csv rate_tmp.csv effect_in.csv sample_out.csv pred_out.csv
	! `dismodlink'/model_draw value_in.csv plain_in.csv rate_in.csv effect_in.csv sample_out.csv draw_in.csv draw_out.csv
	! `dismodlink'/predict_post.py 10
	! `dismodlink'/data_pred model_in.csv value_in.csv plain_in.csv rate_tmp.csv effect_in.csv sample_out.csv model_out.csv
	! `dismodlink'/plot_post.py  "`project'"
	! `dismodlink'/model_draw  draw_in.csv value_tmp.csv plain_tmp.csv rate_tmp.csv effect_tmp.csv sample_out.csv draw_out.csv

		insheet using "draw_out.csv", comma clear
				local n = _N
				keep if _n == 1 | _n > `n' - 1000
				xpose,clear
				gen id = _n
				tempfile draw_out
				save `draw_out'
		insheet using "draw_in.csv", comma clear
				gen id = _n
				merge 1:1 id using `draw_out'		

				drop v1
qui				forval i = 1/1000 {
						local j = `i' + 1
						rename v`j' draw`i'
				}
				tostring age,force replace
				replace age = ".01" if age == ".0099999998"
				replace age = ".1" if age == ".1000000015"
				egen mean = rowmean(draw*)
				egen float lower = rowpctile(draw*), p(2.5)
				egen float upper = rowpctile(draw*), p(97.5)

				save reshaped_draws.dta, replace

*Transform back data_in for future runs/ evaluating file
if `make_data'==1{
	insheet using "$input_folder/data_in.csv", clear

	replace age_upper = 1.5*age_upper if integrand != "mtall"
	replace age_lower = 1.5*age_lower if integrand != "mtall"

	outsheet using "$input_folder/data_in.csv", comma replace
}
