
clear all
set more off
if (c(os)=="Unix") {
	global root "/home/j"
}

if (c(os)=="Windows") {
	global root "J:"
}


********* SETUP UP DATA IN FILES FOR BRADMOD
local run_ssa_high = 1
local run_other = 1
local run_best = 1

local drop_outliers = 1

local gen_year_fe = 1 // Do you want to add a year fixed effect for pre-/post- certain years?

local dismod_templates "strPath"
local dismod_dir "strPath"
local bradmod_dir "strPath"


************** PART 2 : Run SSA and HIGH regions separately
	// Save data for full run with all sites
if `run_ssa_high' == 1 {
	foreach sup in ssa high {
	
		cap mkdir "`dismod_dir'/HIV_KM_`sup'_0_6"
		cap mkdir "`dismod_dir'/HIV_KM_`sup'_7_12"
		cap mkdir "`dismod_dir'/HIV_KM_`sup'_12_24"

		use "`bradmod_dir'/tmp_conditional.dta", clear
		keep if super=="`sup'" | integrand=="mtall"
		
		if `drop_outliers' {
			drop if time_lower<1996 & time_upper<2003  & super=="high"
			drop if time_lower==1994  & super=="high"
			drop if meas_value>.05 & age_lower!=0 & super=="high"
			drop if pubmed_id==18981772 & time_point==24   & super=="high"
			drop if pubmed_id==22205933 & time_point==24 & age_lower==35 & super=="high"
		}

		replace super="none"
		
		if `gen_year_fe' == 1 & "`sup'" == "high" {
			// Generate a fixed-year effect on pre-2002 studies
			egen x_year_linear=rowmean(time_lower time_upper)
			gen x_year_pre2002=(x_year_linear < 2002)
			replace x_year_pre2002 = 0 if integrand == "mtall"
			drop x_year_linear
		}
			
		
		// 0-6
			preserve
			keep if time_point==6 | integrand=="mtall"
			sum age_upper if integrand!="mtall"
			local max_0_6=`r(max)'
			replace age_upper=`max_0_6' if integrand=="mtall" & age_lower!=0
			outsheet using "`dismod_dir'/HIV_KM_`sup'_0_6/data_in.csv", delim(",") replace 
			restore
			
		// 7-12
			preserve
			keep if time_point==12 | integrand=="mtall"
			sum age_upper if integrand!="mtall"
			local max_7_12=`r(max)'
			replace age_upper=`max_7_12' if integrand=="mtall" & age_lower!=0
			outsheet using "`dismod_dir'/HIV_KM_`sup'_7_12/data_in.csv", delim(",") replace 
			restore
			
		// 13-24
			preserve
			keep if time_point==24 | integrand=="mtall"
			sum age_upper if integrand!="mtall"
			local max_12_24=`r(max)'
			replace age_upper=`max_12_24' if integrand=="mtall" & age_lower!=0	
			outsheet using "`dismod_dir'/HIV_KM_`sup'_12_24/data_in.csv", delim(",") replace 
			restore
		
		// Save plain in, effect in, value in, draw in, rate in csv
			insheet using "`dismod_templates'//plain_in.csv", clear comma names
			foreach dur in 0_6 7_12 12_24 {
				outsheet using "`dismod_dir'/HIV_KM_`sup'_`dur'//plain_in.csv", comma names replace
			}
			
			insheet using "`dismod_templates'//value_in.csv", clear comma names
			foreach dur in 0_6 7_12 12_24 {
				outsheet using "`dismod_dir'/HIV_KM_`sup'_`dur'//value_in.csv", comma names replace
			}
			
					
			foreach dur in 0_6 7_12 12_24 {
				insheet using "`dismod_templates'//effect_in.csv", clear comma names
				drop if inlist(name, "high", "ssa", "other")

				// Effect in: Specify the covariates etc. that should go in (should match with covariates present in data_in and draw_in
				
				if `gen_year_fe' == 1 & "`sup'" == "high" {
					// binary
					// foreach year in 2000 2003 {
					foreach year in 2002 {
						local setobs=_N+1
						set obs `setobs'
						replace integrand="incidence" if _n==_N
						replace effect="xcov" if _n==_N
						replace name="x_year_pre`year'" if _n==_N
						replace lower=-2 if _n==_N
						replace upper=2 if _n==_N
						replace mean=0 if _n==_N
						replace std="inf" if _n==_N   
					}
				}
									
				outsheet using "`dismod_dir'/HIV_KM_`sup'_`dur'//effect_in.csv", comma names replace
			}
			
			foreach dur in 0_6 7_12 12_24 {
				insheet using "`dismod_dir'/HIV_Archive/GBD2013 Final/HIV_KM_`sup'_`dur'//draw_in.csv", comma clear names
				if `gen_year_fe' == 1 {
					gen x_year_pre2002 = 0
					// gen x_year_pre2003 = 0
				}
				outsheet using "`dismod_dir'/HIV_KM_`sup'_`dur'//draw_in.csv", comma names replace
			}
			
			foreach dur in 0_6 7_12 12_24 {
				insheet using "`dismod_templates'//rate_in.csv", clear comma names
				drop if age==`max_`dur'' & (type=="diota" | type=="iota") & age!=100
				replace age=`max_`dur'' if age==100
				
				outsheet using "`dismod_dir'/HIV_KM_`sup'_`dur'//rate_in.csv", comma names replace
			}
			
	}
		
}


********** PART 2A: Run 'other' region along with africa in a separate dismod model, but only use 'other'results

************** PART 2 : Run OTHER region seperately, but include SSA data to help inform it
if `run_other' == 1 {
	// Save data for full run with all sites
	
	cap mkdir "`dismod_dir'/HIV_KM_other_0_6"
	cap mkdir "`dismod_dir'/HIV_KM_other_7_12"
	cap mkdir "`dismod_dir'/HIV_KM_other_12_24"

	use "`bradmod_dir'/tmp_conditional.dta", clear
	keep if super=="ssa" | super=="other" | integrand=="mtall"

		// 0-6
		preserve
		keep if time_point==6 | integrand=="mtall"
		sum age_upper if integrand!="mtall"
		local max_0_6=`r(max)'
		replace age_upper=`max_0_6' if integrand=="mtall" & age_lower!=0
		outsheet using "`dismod_dir'/HIV_KM_other_0_6/data_in.csv", delim(",") replace 
		restore
		
		// 7-12
		preserve
		keep if time_point==12 | integrand=="mtall"
		sum age_upper if integrand!="mtall"
		local max_7_12=`r(max)'
		replace age_upper=`max_7_12' if integrand=="mtall" & age_lower!=0
		outsheet using "`dismod_dir'/HIV_KM_other_7_12/data_in.csv", delim(",") replace 
		restore
		
		// 13-24
		preserve
		keep if time_point==24 | integrand=="mtall"
		sum age_upper if integrand!="mtall"
		local max_12_24=`r(max)'
		replace age_upper=`max_12_24' if integrand=="mtall" & age_lower!=0	
		outsheet using "`dismod_dir'/HIV_KM_other_12_24/data_in.csv", delim(",") replace 
		restore
	
	// Save plain in, effect in, value in csv
		insheet using "`dismod_templates'//plain_in.csv", clear comma names
		foreach dur in 0_6 7_12 12_24 {
			outsheet using "`dismod_dir'/HIV_KM_other_`dur'//plain_in.csv", comma names replace
		}
		
		insheet using "`dismod_templates'//value_in.csv", clear comma names
		foreach dur in 0_6 7_12 12_24 {
			outsheet using "`dismod_dir'/HIV_KM_other_`dur'//value_in.csv", comma names replace
		}
		
				
		foreach dur in 0_6 7_12 12_24 {
			insheet using "`dismod_templates'//effect_in.csv", clear comma names
			drop if name=="high"	
			outsheet using "`dismod_dir'/HIV_KM_other_`dur'//effect_in.csv", comma names replace
		}
		
		foreach dur in 0_6 7_12 12_24 {
			insheet using "`dismod_dir'/HIV_Archive/GBD2013 Final/HIV_KM_other_`dur'//draw_in.csv", comma clear names
			if `gen_year_fe' == 1 {
				gen x_year_pre2002 = 0
			}
			outsheet using "`dismod_dir'/HIV_KM_other_`dur'//draw_in.csv", comma names replace
		}
		
		foreach dur in 0_6 7_12 12_24 {
			insheet using "`dismod_templates'//rate_in.csv", clear comma names
			drop if age==`max_`dur'' & (type=="diota" | type=="iota") & age!=100
			replace age=`max_`dur'' if age==100
			outsheet using "`dismod_dir'/HIV_KM_other_`dur'//rate_in.csv", comma names replace
		}

}
	