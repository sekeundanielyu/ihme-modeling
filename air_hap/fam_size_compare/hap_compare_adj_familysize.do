// compare result for DHS adjusted and unadjusted family size 
clear all 
set more off



local adj_dhs_file "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/DHS/prev_dhs_hap_24Jun2016_adj_fs.dta"
local adj_mics_file "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/MICS/prev_mics_hap_24Jun2016_adj_fs.dta"
local unadj_dhs "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/01_DHS_results"
local unadj_mics "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/02_MICS_results"


// combine all unadjusted results
local surveys dhs mics 
foreach survey of local surveys {		
		cd "`unadj_`survey''"
		clear
		local fullfilenames: dir "`unadj_`survey''" files "*_*_*.dta", respectcase
		foreach f of local fullfilenames {
			append using "`unadj_`survey''/`f'"
		}
			tempfile `survey'
			save ``survey'',replace 
		}
		use `dhs',clear 
		append using `mics'

rename mean mean_unadj
tempfile unadjusted
save `unadjusted',replace 

// adjusted 
use "`adj_dhs_file'",clear
append using "`adj_mics_file'"
rename mean mean_adj 
merge 1:1 iso3 startyear endyear filepath using `unadjusted', keep(3) nogen /*264*/
// Graphing 
twoway (scatter mean_adj mean_unadj) (function y=x), ytitle(adjusted) xtitle(unadjusted)