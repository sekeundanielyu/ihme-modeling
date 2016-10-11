
****************************************************************************************************
****************************************************************************************************
** Code Runs Several Analysis to do with MEPS, NESARC, and AHS Datasets.
** Including SF12 to DW crosswalk, Severity Distributions, and Prevalence from MEPS
** cleaned up version of analysis from this folder:
****************************************************************************************************


cap restore, not
clear all
set more off
set mem 4G

** set OS
if c(os) == "Windows" {
	global SAVE_DIR "strDir"
	global R "strPathToR"
}
if c(os) == "Unix" {
	global SAVE_DIR "strDir"
	global R "strPathToR"
}

** globals

	// set path - use all relative paths from here on
	cd "."
	global dir = subinstr("`c(pwd)'","\","/",.)
	global CW_DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data/1_crosswalk_survey"
	global MEPS_DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data/2_meps"
	global DATADIR "$j/Project/GBD/Systematic Reviews/ANALYSES/MEPS/data"


	// CHECK WITH VERSION OF R YOU ARE USING (USED LATER FOR MAPPING FACILITY LOCATION)
	// global R "C:/Program Files/R/R-2.14.0/bin/R" 			

	// Names
	global surveys meps nesarc ahs
	global surveys ahs1mo ahs12mo nesarc meps

	// External Files
	global gbd_dws "$j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv"

	// Save the name of the file with the most updated causes of severity distribution as a macro
	global causename gbd2013_causes

	// the date so that all files saved as outputs are dated
	global date = subinstr(lower("`c(current_date)'")," ","",.)

****************************************************************************************************
** 1) Run SF-12 to GBD Crosswalk.

	do "./code/1_prep_crosswalk_survey.do"

****************************************************************************************************
** 2) Prep Data - Take in Raw data and get out a squared away dataset with SF scores, DWs, and Condition information

	// Prep raw data
	do "./code/2a_prep_meps.do"
	do "./code/2a_prep_nesarc.do"
	do "./code/2a_prep_ahs.do"

	// Take survey data and use the crosswalk to get DWs for each SF-12 measurement
	!"$R" <"./code/2b_prep_crosswalk.R" --no-save --args "$SAVE_DIR" "meps"
	!"$R" <"./code/2b_prep_crosswalk.R" --no-save --args "$SAVE_DIR" "nesarc"
	!"$R" <"./code/2b_prep_crosswalk.R" --no-save --args "$SAVE_DIR" "ahs"

****************************************************************************************************
** 3) Severity Distribution Analysis --  right now they are split into their own code files but the process
** is similar enough that it may be wise to streamline into one

// A) For each survey, run the regression part of the analysis. This is to be submitted for the cluster
// 		as each regression is to be run on 1000 bootstrapped samples

	global survey meps
	do "./code/3a_analysis_submit.do"

	global survey nesarc
	do "./code/3a_analysis_submit.do"
	do "./code/3a_analysis_ahs.do" // runs for both 1mo and 12mo diagnose


// B) Get distributions.
	do "./code/3b_get_distributions_meps"
	do "./code/3b_get_distributions_nesarc"
	do "./code/3b_get_distributions_ahs"	// loops through and runs both 1 and 12 mo

	insheet using "./gbd_2013_maps/gbd2013_keep_list.csv", clear names
	levelsof acause, local(acauses)
	foreach yld_cause of local acauses {
		! qsub -N dist`yld_cause' ./code/3b_get_distributions_meps_parallel.sh `yld_cause'
	}

// C) Compile results of analysis to a nice table.
	do "./code/3c_compile_distribution_results.do"

// D) Create the tables
	do "./code/3d_results_for_phm_paper.do"

****************************************************************************************************

** 4) MEPS Prevalence Estimates.

// A) Prep data
	do "./code/4a_meps_prevalence_prep.do"

// B) Estimate Prevalence
	do "./code/4b_meps_prevalence_submit.do"

// C) Merge together results and output table
	do "./code/4c_meps_prevalence_merge.do"

// D) Graph Results
	do "./code/4d_meps_prevalence_graph.do"
