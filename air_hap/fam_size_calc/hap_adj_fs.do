// generate multiplier for family size crosswalk
// 6/28/2016

clear all 
set more off

local dhs_adj_file "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/DHS/prev_dhs_hap_11Jul2016_adj_fs.dta"
local mics_adj_file "J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/adj_family_size/02_data/microdata/MICS/prev_mics_hap_11Jul2016_adj_fs.dta"

*************************
*****locations***** 
*************************
include "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado"
get_location_metadata, location_set_id(9) clear 
keep location_id region_id super_region_id ihme_loc_id
tempfile loc 
save `loc',replace 

*************************
*****Build database***** 
*************************
// Adjusted data 
use "`dhs_adj_file'",clear 
append using "`mics_adj_file'"
/*270*/

replace mean=0.0001 if mean==0
gen ind=0 // reference group
tempfile adjusted 
save `adjusted',replace 

// Undajusted data
local dhsdir 				"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/01_DHS_results"
local micsdir 				"J:/WORK/05_risk/risks/air_hap/01_exposure/01_data audit/02_data/02_MICS_results"
local dirs dhs mics
	foreach d of local dirs {
		clear
		cd "``d'dir'"
		local fullfilenames: dir "``d'dir'" files "*_*_*.dta", respectcase
		foreach f of local fullfilenames {
			append using "``d'dir'/`f'"
		}
		tempfile `d'
		save ``d'', replace
	}
	
	use "`dhs'",clear 
	append using `mics'

	replace mean=0.0001 if mean==0
	gen ind=1  
	tempfile unadjusted 
	save `unadjusted',replace 

*********************************************************************************
*****make a list of surveys that would be included in the mixed effect model***** 
*********************************************************************************
	// matched surveys 
	use `adjusted',clear
	rename mean mean_adj 
	merge 1:1 filepath using `unadjusted', keep(3) nogen
	keep iso3 startyear endyear mean_adj reference filepath mean
	// graphing to identify outliers 
	twoway (scatter mean_adj mean) (function y=x), ytitle(adjusted) xtitle(unadjusted) title (Scatter plot: Adjusted mean and Unadjusted mean by data extraction) // no outliers

	// identify the data points that the adjustment actually reduce the mean 
	*br if mean_adj<mean /*41 obs*/
	/* in these surveys, either family size is negatively associated with solid fuel use or no assocation OR the mean is extremely small */
	// drop the data point identified since they are not at the expected direction 
	drop if mean_adj<mean 

	// make a list of filepath
	keep filepath 
	tempfile matchfile /*223*/
	save `matchfile',replace 

// reduce the adjusted and Undajusted datasets to the matched files 
use `adjusted',clear 
merge 1:1 filepath using `matchfile', keep(3) nogen
save `adjusted',replace 

use `unadjusted',clear 
merge 1:1 filepath using `matchfile', keep(3) nogen
save `unadjusted', replace 

*****************************
*****Crosswalk***** 223 surveys in the crosswalk, excluded those have opposite directions
*****************************
	// make a database consists of matched adjusted and unadjusted data points and run mixed effect model
	append using `adjusted'
	// get location and clean the database 
	rename iso3 ihme_loc_id 
	merge m:1 ihme_loc_id using `loc', keep(3) nogen
	keep ihme_loc_id startyear endyear mean se reference ind filepath location_id region_id super_region_id

	// Run mixed effect model to generate a multiplier for shifting 
	gen mean_orig=mean
	gen logit_mean = logit(mean)

	mixed logit_mean ind || super_region_id: ind || region_id: ind || location_id:ind || filepath:ind
	predict re*, reffect
	gen coef = re1 + re3 + (_b[ind]) * ind
	gen mean_adj=invlogit(logit_mean - coef)
	
*****Diagnosis*****
	sort filepath ind 
	// whether the value in reasonable range  
	codebook mean_orig mean_adj
	// scatter plot to compare adjusted and unadjusted mean
	twoway (scatter mean_adj mean_orig if ind==1, sort) (function y=x), ytitle(adjusted) xtitle(unadjusted) title(Scatter Plot: Comparison of pre- and post- crosswalk)

	// percentage change from unadjusted to adjusted 
	gen change= (mean_adj-mean_orig)/mean_orig*100 
		//the crosswalk reduced the mean 
		br if change<0 & ind==1 
