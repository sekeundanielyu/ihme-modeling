
// Purpose: Calculate Region-Duration-CD4-Sex-Age-specific mortality estimates for HIV patients on ART

clear all
set more off

** Set code directory for Git
global user "`c(username)'"

if (c(os)=="Unix") {
	global root "/home/j"
	global code_dir "strPath"
}

if (c(os)=="Windows") {
	global root "$root"
	global code_dir "strPath"
}

**** SET UP ****
	// adopath + "$root/Project/Mortality/shared/functions" // get_locations (not needed right now)
	cd "$code_dir"
	global dismod_dir "strPath"
	global dismod_type = "20150319" // Options: standard, or an alternate date (20150319) that corresponds to the DisMod version you want
	
	global km_pre = 0				// Prep stages for all KM data
	global km_id_brad = 0			// Run id best in Bradmod
	global km_id_post = 0			// After running id best, identify and then prep full dataset for KM
	global km_full_brad = 0			// Run Bradmod for the full set of data
	global km_full_post = 0 		// After the full run of BradMod, generate conditional prob of death
	global hr_pre = 0				// Run sex meta-analysis and prep age data for BradMod
	global hr_brad = 0				// Run BradMod to synthesize age hazard ratios
	global hr_post = 0				// Reference hazard ratios to region-specific mean ages and format
	global final_analysis = 1 		// Apply HR data to conditional mortality estimates and then output
	
	// Archive toggles (do we want to archive this run, and if so, how should we save?
	global archive = 1
	local date: display %td_CCYY_NN_DD date(c(current_date), "DMY")
	global date = subinstr(trim("`date'"), " " , "-", .)
	local comment = ""
	if "`comment'" != "" global date = "$date_`comment'"
	global bradmod_archive = "data_in.csv change_post.csv data_omega.csv data_pred.csv data_tmp.csv effect_tmp.csv info_out.csv model_draw2.csv model_out.csv plain_tmp.csv plot_post.pdf rate_omega.csv rate_tmp.csv sample_out.csv sample_split.csv sample_stat.csv stat_post.pdf value_tmp.csv"
	global bradmod_remove = subinstr("$bradmod_archive","data_in.csv","",.)
	


**** KAPLAN MEIER ****
// We take kaplan meier data on mortality and loss to follow up that has been extracted from literature (region-duration-CD4-specific). These are collected as cumulative probabilities from initiation on therapy. We first standardize the extractions and apply a LTFU correction factor, then run the data through dismod (new dismod, or 'bradmod'), "tricking" dismod to treat CD4 categories as ages.  From the cumulative probability output by dismod, we generate conditional mortality rates for the duration-periods used by Spectrum.
// We first identify a 'best' case scenario, by examining the residuals of all the studies and picking the best one from sub-saharan africa. Then, we treat this as a separate 'region' in analyses.

	// Prepare KM data for dismod; cleaning the data - applying exclusion criteria; applying Allen's correction factor for differential mortality in LTFU; prepping to BradMod format. This is prepping the data for both the determination of the best site, and some cleaning that will go into running the full model
	** everything cumulative probabilities
	if $km_pre == 1 {
		do $code_dir/00_prep_data.do
		do $code_dir/01_prep_KM.do
		// note: this also calls on the file 
		** 01a_adjust_survival_for_ltfu
		if $archive == 1 {
			// Archive pct male_med
			local pct_male_dir "strPath"
			! cp "`pct_male_dir'/pct_male_med_age.csv" "`pct_male_dir'/archive/pct_male_med_age_$date.csv"
			
			// Archive conditional and cumulative tmp probabilities
			local tmp_dir "strPath"
			! cp "`tmp_dir'/tmp_conditional.dta" "`tmp_dir'/archive/tmp_conditional_$date.dta"
			! cp "`tmp_dir'/tmp_cumulative.dta" "`tmp_dir'/archive/tmp_cumulative_$date.dta"
		}
	}
		
	// NOTE: THIS EVENTUALLY NEEDS TO BE LAUNCHED BETWEEN THE TWO SECTIONS OF 02_ID_BEST
	if $km_id_brad == 1 {
		do $code_dir/02a_id_pre.do
	
		local runtypes "HIV_IDBEST_CUMUL_0_6 HIV_IDBEST_CUMUL_0_12 HIV_IDBEST_CUMUL_0_24"
		
		// Remove results from previous run
			foreach folder in `runtypes' {
				foreach fff of global bradmod_remove {
					cap rm "$dismod_dir/`folder'/`fff'"
				}
			}
		
		// Launch BradMod jobs
			cd "$code_dir"
			local job_count = 0
			foreach runtype in `runtypes' {
				! /usr/local/bin/SGE/bin/lx24-amd64/qsub -N brad_`runtype' -e /share/temp/sgeoutput/$user/errors -o /share/temp/sgeoutput/$user/output -P proj_hiv "run_all.sh" "$code_dir/launch_dismod_ode.do" "`runtype' $dismod_type"
				local ++job_count
			}
		
		// Check that BradMod has finished before proceeding
			local i = 0
			while `i' == 0 {
				local counter = 0
				foreach runtype in `runtypes' {
					capture confirm file "$dismod_dir/`runtype'/model_draw2.csv"
					if !_rc local ++counter
				}
				
				di "Checking `c(current_time)': `counter' of `job_count' ID Best jobs finished"
				if (`counter' == `job_count') local i = `i' + 1
				else sleep 30000
			}
			
		sleep 30000 // Just to give the ID Best jobs more time to write -- had issues with draw files being empty
			
		// Archive, if desired
			if $archive == 1 {
				foreach runtype in `runtypes' {
					cap mkdir "$dismod_dir/`runtype'/archive_$date"
					foreach fff of global bradmod_archive {
						! cp "$dismod_dir/`runtype'/`fff'" "$dismod_dir/`runtype'/archive_$date/`fff'"
					}
				}
			}
	}
	
	if $km_id_post == 1 {
		// examine the residuals to id the 'best' site
		do $code_dir/02b_id_post

		// now we can run everything, inputting the 'best' study as its own random effect region
		do $code_dir/03_prep_full_KM
		
		if $archive == 1 {
			// Archive the best sites
			local store_best_dir "strPath"
			! cp "`store_best_dir'/best_cumulative.csv" "`store_best_dir'/archive/best_cumulative.csv"
			! cp "`store_best_dir'/best_conditional.csv" "`store_best_dir'/archive/best_conditional.csv"
		}
	}
	
	// Run Bradmod now for all the major regions
	if $km_full_brad == 1 {
		local runtypes "HIV_KM_ssa_0_6 HIV_KM_ssa_7_12 HIV_KM_ssa_12_24 HIV_KM_high_0_6 HIV_KM_high_7_12 HIV_KM_high_12_24 HIV_KM_other_0_6 HIV_KM_other_7_12 HIV_KM_other_12_24 HIV_KM_ssabest_0_6 HIV_KM_ssabest_7_12 HIV_KM_ssabest_12_24"
		
		// Remove results from previous run
			foreach folder in `runtypes' {
				foreach fff of global bradmod_remove {
					// Remove the results from the previous run
					cap rm "$dismod_dir/`folder'/`fff'"
				}
			}
		
		// Launch BradMod jobs
			cd "$code_dir"
			local job_count = 0
			foreach runtype in `runtypes' {
				! /usr/local/bin/SGE/bin/lx24-amd64/qsub -N brad_`runtype' -e /share/temp/sgeoutput/$user/errors -o /share/temp/sgeoutput/$user/output -P proj_hiv "run_all.sh" "$code_dir/launch_dismod_ode.do" "`runtype' $dismod_type"
				local ++job_count
			}
		
		// Check that BradMod has finished before proceeding
		// Usually runs quickly without covariates, but with covariates it takes about an hour
			local i = 0
			while `i' == 0 {
				local counter = 0
				foreach runtype in `runtypes' {
					capture confirm file "$dismod_dir/`runtype'/model_draw2.csv"
					if !_rc local ++counter
				}
				
				di "Checking `c(current_time)': `counter' of `job_count' Full BradMod jobs finished"
				if (`counter' == `job_count') local i = `i' + 1
				else sleep 30000
			}
			
			sleep 30000 // Just to give the BradMod jobs more time to write -- had issues with draw files being empty
			
		// Archive, if desired
			if $archive == 1 {
				foreach runtype in `runtypes' {
					cap mkdir "$dismod_dir/`runtype'/archive_$date"
					foreach fff of global bradmod_archive {
						! cp "$dismod_dir/`runtype'/`fff'" "$dismod_dir/`runtype'/archive_$date/`fff'"
					}
				}
			}
			
	}
	
	if $km_full_post == 1 {
		// Generate conditional probabilities based on dismod outputs... then convert to death rates.  Graphs results
		// So many graphs -- figure out if we need to archive or not... Probably not if we have the underlying data
		do $code_dir/04_post_dismod_full_KM
		
		if $archive == 1 {
			// Conditional Mortality and mortality rates
			local tmp_dir "$root/WORK/04_epi/01_database/02_data/hiv/on_art/data/bradmod"
			! cp "`tmp_dir'/mortality_conditional_prob_output.dta" "`tmp_dir'/archive/mortality_conditional_prob_output_$date.dta"
			! cp "`tmp_dir'/mortality_rate_output.dta" "`tmp_dir'/archive/mortality_rate_output_$date.dta"		
		}
	}
	
	
**** HAZARD RATIOS ****
// Since we want our final output to be age and sex specific as well, we use hazard ratios (Also extracted from literature) to adjust our region-duration-cd4-specific mortality estimates. First we use the stata command 'metan' to generate sex hazard ratios. Then we use 'bradmod' to synthesize the age hazard ratios, and output the hazard ratios for spectrum's age groups, referenced to the region-specific mean age from the studies.

	if $hr_pre == 1 {
		// Run sex meta analysis
		do $code_dir/05_sex_meta_analysis.DO // why is this postfix capitalized....so sillly...
		
		// Prep age data for bradmod
		do $code_dir/06_age_prep_bradmod
		
		if $archive == 1 {
			// Archive sex HRs
			local hr_dir "$root/WORK/04_epi/01_database/02_data/hiv/on_art/data/DisMod/HR_predictions"
			! cp "`hr_dir'/sex_hazard_ratios.dta" "`hr_dir'/archive/sex_hazard_ratios_$date.dta"
			! cp "`hr_dir'/sex_hazard_ratios.csv" "`hr_dir'/archive/sex_hazard_ratios_$date.csv"
		}
	}
	
	
	if $hr_brad == 1 {
		// The previous code automatically updates the 'data_in' file, but you may also need to manually update effect_in (random effects), plain_in (smoothing), rate_in (mesh points), value_in (# draws), pred_in (specify intervals to predict)
	
		local runtypes "HIV_HR_ssa HIV_HR_high HIV_HR_other"
		
		// Remove results from previous run
			foreach folder in `runtypes' {
				foreach fff of global bradmod_remove {
					// Remove the results from the previous run
					cap rm "$dismod_dir/`folder'/`fff'"
				}
			}
		
		// Launch BradMod jobs
			cd "$code_dir"
			local job_count = 0
			foreach runtype in `runtypes' {
				! /usr/local/bin/SGE/bin/lx24-amd64/qsub -N brad_`runtype' -e /share/temp/sgeoutput/$user/errors -o /share/temp/sgeoutput/$user/output -P proj_hiv "run_all.sh" "$code_dir/launch_dismod_ode.do" "`runtype' $dismod_type"
				local ++job_count
			}
		
		// Check that BradMod has finished before proceeding
			local i = 0
			while `i' == 0 {
				local counter = 0
				foreach runtype in `runtypes' {
					capture confirm file "$dismod_dir/`runtype'/model_draw2.csv"
					if !_rc local ++counter
				}
				
				di "Checking `c(current_time)': `counter' of `job_count' ID Best jobs finished"
				if (`counter' == `job_count') local i = `i' + 1
				else sleep 30000
			}
			
		sleep 30000 // Just to give the ID Best jobs more time to write -- had issues with draw files being empty
			
		// Archive, if desired
			if $archive == 1 {
				foreach runtype in `runtypes' {
					cap mkdir "$dismod_dir/`runtype'/archive_$date"
					foreach fff of global bradmod_archive {
						! cp "$dismod_dir/`runtype'/`fff'" "$dismod_dir/`runtype'/archive_$date/`fff'"
					}
				}
			}
	}
		
	// With dismod output, reference hazard ratios to region-specific mean ages and format data for analysis
	if $hr_post == 1 {
		do $code_dir/07_age_seperate_post_bradmod
		
		if $archive == 1 {
			local hr_dir "strPath"
			! cp "`hr_dir'/age_hazard_ratios.dta" "`hr_dir'/archive/age_hazard_ratios_$date.dta"
			! cp "`hr_dir'/age_hazard_ratios.csv" "`hr_dir'/archive/age_hazard_ratios_$date.csv"			
		}
	}
	

**** PULLING KM AND HR DATA TOGETHER ****
// We apply the Hazard Ratio data to the Conditional Mortality estimates, then subtract out the baseline mortality data and save the final dataset so it can be input into the GBD spectrum
	if $final_analysis == 1 {
		// Apply HR to KM
		do $code_dir/08_applyHR
		
		// Format the baseline HIV-free mortality rates to be subtracted from our estimates
		** want estimates for 2005
		** convert age-sex-country-year specific rates to numbers, aggregated to DisMod regions and age groups; generate rates from numbers
		do $code_dir/09_prep_HIV_free_lifetables
		
		// Save in spectrum input format
		// NOTE: Archiving of draws happens in this code file, for ease of use
		do $code_dir/10_save_for_GBDspectrum
		
		if $archive == 1 {
			local adj_dir "strPath"
			! cp "`adj_dir'/adj_death_rates.csv" "`adj_dir'/archive_adj_mort/adj_death_rates_$date.csv"
			
			local hiv_free_dir "`adj_dir'/hiv_free_life_tables"
			! cp "`hiv_free_dir'/HIV_free_spectrum_dth_rts.csv" "`hiv_free_dir'/archive/HIV_free_spectrum_dth_rts_$date.csv"
			
			local mort_probs_dir "`adj_dir'/hiv_on_art_draws"
			! cp "`mort_probs_dir'/HIVonART_dth_RATE_DisMod_WITHBACKGROUND_FORTABLE.csv" "`mort_probs_dir'/archive/HIVonART_dth_RATE_DisMod_WITHBACKGROUND_FORTABLE_$date.csv"
			! cp "`mort_probs_dir'/HIVonART_dth_RATE_DisMod_FORTABLE.csv" "`mort_probs_dir'/archive/HIVonART_dth_RATE_DisMod_FORTABLE_$date.csv"
			! cp "`mort_probs_dir'/HIVonART_dth_prob_DisMod.csv" "`mort_probs_dir'/archive/HIVonART_dth_prob_DisMod_$date.csv"
			
			! cp "`adj_dir'/mortality_probs.dta" "`adj_dir'/archive_adj_mort/mortality_probs_$date.dta"
			
			// Archive all the important graphs from the processes
			local graph_dir "$root/WORK/04_epi/01_database/02_data/hiv/on_art/graphs"
			! cp "`graph_dir'/Manuscript/Figure_3_4_5_Conditional_Data_IEDEA.pdf" "`graph_dir'/Manuscript/archive/Figure_3_4_5_Conditional_Data_IEDEA_$date.pdf"
			foreach file in Conditional_All_Regions Cumulative_Mortality_byCD4 Mortality_Rate {
				! cp "`graph_dir'/`file'.pdf" "`graph_dir'/archive/`file'_$date.pdf"
			}
			foreach file in estimates_data hr_estimates {
				! cp "`graph_dir'/hazard_ratios/`file'_separate.pdf" "`graph_dir'/hazard_ratios/archive/`file'_separate_$date.pdf"	
			}
		}
	}
	
	