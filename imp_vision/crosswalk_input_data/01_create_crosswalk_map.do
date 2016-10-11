

//Purpose: Create crosswalks for vision measures spanning multiple GBD severities 
	
**************************************
** Prep Stata
**************************************	

clear all
set mem 1g
set maxvar 20000
set more off
cap restore, not
set type double, perm


	local group= "imp_vision"
	local date: display %td_CCYY_NN_DD date(c(current_date), "DMY")
	local date = subinstr(trim("`date'"), " ", "_", .)
	local prefix "J:"
	local out_dir "`prefix'/WORK/04_epi/01_database/02_data/`group'/02_nonlit"

local strname_2013_data "J:/DATA/Incoming Data/WORK/04_epi/0_ongoing/gbd2013_additional lit from experts/Vision loss_struser/checked_strname_datasheet_prepped_MASTER.xlsx"
local output_data "`out_dir'/03_temp/user/expert group vision database for dismod.dta"
local proportions_map "`out_dir'/proportions_map_split_merged_severity_groups.dta"
local expert_2013_data "J:/WORK/04_epi/01_database/02_data/imp_vision/archive_2013/02_nonlit/02_inputs/04_expert/vision expert group round 2 gbd 2013/gbd2013_additional_vision_060214.xlsx"
	
**********************************************************
** Start data prep of first round of strname data (includes GBD 2010 info)
**********************************************************
if 1==1 {	
	import excel "`strname_2013_data'", firstrow clear 
	
	//  drop that is redundant data or incorrect data (example: 1. you have male, female, both.  drop both 2. data extracted the first time was wrong)
		drop if exclude_data==1
	
	// identify unique ids for the data... if this breaks we need to figure out why and fix it.
	isid nid diagcode year_start year_end iso3 age_start age_end sex location_id site

	// age-sex split
	
		replace specificity=lower(specificity)
		tostring data_status issues, replace
		gen agesex_split_group=group
		levelsof group if why_2=="age/sex", local(groups)		
		
		quietly {
		foreach gp of local groups {

			noisily di "age-sex splitting group `gp'"
			
			** calculate sex ratio 
			summ mean if agesex_split_group==`gp' &  sex==1
			local male = `r(mean)'
			summ mean if agesex_split_group==`gp' &   sex==2
			local female = `r(mean)'
			

			summ denominator if agesex_split_group==`gp' &   sex==1
			local maless = `r(mean)'	
			summ denominator if agesex_split_group==`gp' &   sex==2
			local femaless = `r(mean)'
			
			// if same sample sizes, we have an issue
				if `maless' == `femaless' {
					STOP_group`gp'_denominator_issues
				}
			
			local sexratioM = (`male')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
			local sexratioF = (`female')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
			
			** create different rows for males and females
			expand 2 if agesex_split_group==`gp' &   sex==3, gen(copy)
			** adjust males
			replace mean = mean*`sexratioM' if agesex_split_group==`gp' &   sex==3 & copy==1
			replace sex = 1 if copy==1
			replace denominator = int(denominator*(`maless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==1 & copy==1
			replace numerator = . if agesex_split_group==`gp' &   sex==1 & copy==1
			** replace denominator = . if agesex_split_group==`gp' &   sex==1 & copy==1
			** adjust females
			replace mean = mean*`sexratioF' if agesex_split_group==`gp' &   sex==3 & copy==0
			replace sex = 2 if agesex_split_group==`gp' &   sex==3 & copy==0 
			replace denominator = int(denominator*(`femaless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==2 & copy==0 
			replace numerator = . if agesex_split_group==`gp' &   sex==2 & copy==0
			** replace denominator = . if agesex_split_group==`gp' &   sex==2 & copy==0

			** drop the sex-specific all-age data points
			summ age_start if agesex_split_group==`gp' & inlist(sex, 1, 2)
			local min `r(min)'
			summ age_end if agesex_split_group==`gp' & inlist(sex, 1, 2)
			local max `r(max)'
			drop if agesex_split_group==`gp' & inlist(sex, 1, 2) & age_start==`min' & age_end==`max'
			drop copy
			
			replace row_id = .
				
			replace lower = . if agesex_split_group==`gp'
			replace upper = . if agesex_split_group==`gp'
			replace standard_error = . if agesex_split_group==`gp'
			replace is_raw = "adjusted" if agesex_split_group==`gp'
			replace data_status = "" if agesex_split_group==`gp'
			replace issues = "was age/sex split " + string(agesex_split_group) if agesex_split_group==`gp'
			replace mean = 0 if mean ==. & agesex_split_group==`gp'
		}	
		}	
			
	// age-sex-subnational split
		levelsof group if why_2=="age/sex, subnational", local(groups)

		// age/sex split first
		quietly {
			foreach gp of local groups {

				noisily di "age-sex splitting group `gp'"
				
				** calculate sex ratio 
				summ mean if agesex_split_group==`gp' &  sex==1
				local male = `r(mean)'
				summ mean if agesex_split_group==`gp' &   sex==2
				local female = `r(mean)'
				

				summ denominator if agesex_split_group==`gp' &   sex==1
				local maless = `r(mean)'	
				summ denominator if agesex_split_group==`gp' &   sex==2
				local femaless = `r(mean)'
				
				// if same sample sizes, we have an issue
					if `maless' == `femaless' {
						STOP_group`gp'_denominator_issues
					}
				
				local sexratioM = (`male')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
				local sexratioF = (`female')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
		
				** create different rows for males and females
				expand 2 if agesex_split_group==`gp' &   sex==3 & specificity!="subnational", gen(copy)
				** adjust males
				replace mean = mean*`sexratioM' if agesex_split_group==`gp' &   sex==3 & copy==1 & specificity!="subnational"
				replace sex = 1 if copy==1 & specificity!="subnational"
				replace denominator = int(denominator*(`maless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==1 & copy==1 & specificity!="subnational"
				replace numerator = . if agesex_split_group==`gp' &   sex==1 & copy==1 & specificity!="subnational"

				** adjust females
				replace mean = mean*`sexratioF' if agesex_split_group==`gp' &   sex==3 & copy==0 & specificity!="subnational"
				replace sex = 2 if agesex_split_group==`gp' &   sex==3 & copy==0  & specificity!="subnational"
				replace denominator = int(denominator*(`femaless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==2 & copy==0  & specificity!="subnational"
				replace numerator = . if agesex_split_group==`gp' &   sex==2 & copy==0 & specificity!="subnational"

				** drop the sex-specific all-age data points
				summ age_start if agesex_split_group==`gp' & inlist(sex, 1, 2) & specificity!="subnational"
				local min `r(min)'
				summ age_end if agesex_split_group==`gp' & inlist(sex, 1, 2) & specificity!="subnational"
				local max `r(max)'
				drop if agesex_split_group==`gp' & inlist(sex, 1, 2) & age_start==`min' & age_end==`max' & specificity!="subnational"
				drop copy
				
				replace row_id = .
					
				replace lower = . if agesex_split_group==`gp'
				replace upper = . if agesex_split_group==`gp'
				replace standard_error = . if agesex_split_group==`gp'
				replace is_raw = "adjusted" if agesex_split_group==`gp'
				replace data_status = "" if agesex_split_group==`gp'
				replace issues = "was age/sex/subnational split " + string(agesex_split_group) if agesex_split_group==`gp'
				replace mean = 0 if mean ==. & agesex_split_group==`gp'
			}	
			}	
					
// MORE DATA PREP
	gen filepath="`expert_2013_data'"
	
	// make a local with all of the variables essential of dismod input sheet
		local vars "acause grouping healthstate sequela_name description row_id study_status nid citation file page_num table_num source_type data_type location_type location_id iso3 location_name sex year_start year_end age_start age_end parameter_type mean lower upper standard_error sample_size numerator denominator orig_unit_type orig_uncertainty_type national_type urbanicity_type site socio_characteristics recall_type recall_type_value sampling_type design_effect response_rate case_name case_definition case_diagnostics population_characteristics is_raw data_status issues extractor uploaded notes cv_* _* filepath diagcode"
		
	** Clean up and save
		order `vars'
		keep `vars'
		
		tostring acause grouping healthstate sequela_name description study_status citation file page_num table_num source_type data_type location_type iso3 location_name parameter_type orig_unit_type  site socio_characteristics recall_type sampling_type case_name case_definition case_diagnostics population_characteristics data_status issues extractor notes is_raw national_type urbanicity_type _*, replace
		
		destring row_id nid location_id sex year_start year_end age_start age_end mean lower upper standard_error sample_size numerator denominator recall_type_valu design_effect response_rate orig_uncertainty_type, replace		

	// site is necessary to uniquely identify obs, make it N/A if missing so merges and reshapes work
		replace site="." if site==""
	
	// clean up
		tostring orig_uncertainty_type, replace force
		replace orig_uncertainty_type=""
	
	// don't want incidence data
		drop if parameter_type=="incidence"
	
	
	
	// identify type of uncertainty
		replace orig_uncertainty_type="CI" if upper!=. & lower!=.
		replace orig_uncertainty_type="ESS" if denominator!=.	
		replace orig_uncertainty_type="SE" if standard_error!=.		
	
	drop if data_status=="excluded"
	
	tempfile VLEG_round1
	save `VLEG_round1', replace
	
}

**********************************************************
** Data prep for the sources we received from strname 3/2 and other experts
**********************************************************
if 1==1 {
	
	import excel "`expert_2013_data'", firstrow clear 

	// can't have American Samoa
		drop if site=="Ta'u Island"

	replace location_id=00000 if location_id==.
	replace site="." if site==""
	replace urbanicity_type="." if urbanicity_type==""
	
	
	// age-sex split
		replace specificity=lower(specificity)
		tostring data_status issues, replace
		gen agesex_split_group=group
		levelsof group if why_2=="age/sex", local(groups)	
	
	local gp 47
		
	quietly {
		foreach gp of local groups {

			noisily di "age-sex splitting group `gp'"
			
			** calculate sex ratio 
			summ mean if agesex_split_group==`gp' &  sex==1
			local male = `r(mean)'
			summ mean if agesex_split_group==`gp' &   sex==2
			local female = `r(mean)'
			

			summ denominator if agesex_split_group==`gp' &   sex==1
			local maless = `r(mean)'	
			summ denominator if agesex_split_group==`gp' &   sex==2
			local femaless = `r(mean)'
			
			// if same sample sizes, we have an issue
				if `maless' == `femaless' {
					STOP_group`gp'_denominator_issues
				}
			
			local sexratioM = (`male')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
			local sexratioF = (`female')/((`male'*`maless'+`female'*`femaless')/(`maless'+`femaless'))
			
			** create different rows for males and females
			expand 2 if agesex_split_group==`gp' &   sex==3, gen(copy)
			** adjust males
			replace mean = mean*`sexratioM' if agesex_split_group==`gp' &   sex==3 & copy==1
			replace sex = 1 if copy==1
			replace denominator = int(denominator*(`maless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==1 & copy==1
			replace numerator = . if agesex_split_group==`gp' &   sex==1 & copy==1

			** adjust females
			replace mean = mean*`sexratioF' if agesex_split_group==`gp' &   sex==3 & copy==0
			replace sex = 2 if agesex_split_group==`gp' &   sex==3 & copy==0 
			replace denominator = int(denominator*(`femaless'/(`maless'+`femaless'))) if agesex_split_group==`gp' &   sex==2 & copy==0 
			replace numerator = . if agesex_split_group==`gp' &   sex==2 & copy==0

			** drop the sex-specific all-age data points
			summ age_start if agesex_split_group==`gp' & inlist(sex, 1, 2)
			local min `r(min)'
			summ age_end if agesex_split_group==`gp' & inlist(sex, 1, 2)
			local max `r(max)'
			drop if agesex_split_group==`gp' & inlist(sex, 1, 2) & age_start==`min' & age_end==`max'
			drop copy
			
			replace row_id = .
				
			replace lower = . if agesex_split_group==`gp'
			replace upper = . if agesex_split_group==`gp'
			replace standard_error = . if agesex_split_group==`gp'
			replace is_raw = "adjusted" if agesex_split_group==`gp'
			replace data_status = "" if agesex_split_group==`gp'
			replace issues = "was age/sex split " + string(agesex_split_group) if agesex_split_group==`gp'
			replace mean = 0 if mean ==. & agesex_split_group==`gp'
		}	
		}	
		
	// clean up a few of the variables
	drop description
		gen description="GBD 2013"
	gen file=file_location + file_name
	gen study_status="active"
	gen filepath="`expert_2013_data'"
	gen diagcode=petediagcode
	gen citation=field_citation
	
	// make means for numerator/denom
		replace mean=numerator/denominator if mean==.
	
	// add all of the extra covariates and other info that may be important
		gen cv_rapid_test=add1
		gen cv_presenting=.

	// clean up urbanicity_type variable
		replace urbanicity_type="1" if urbanicity_type=="Representative" | urbanicity_type=="representative"
		replace urbanicity_type="2" if urbanicity_type=="Urban" | urbanicity_type== "urban"
		replace urbanicity_type="3" if urbanicity_type=="Rural" | urbanicity_type== "rural"
		replace urbanicity_type="4" if urbanicity_type=="Suburban" | urbanicity_type== "suburban"
		replace urbanicity_type="5" if urbanicity_type=="Peri-urban" | urbanicity_type== "peri-urban"

		replace urbanicity_type="0" if urbanicity_type== "mixed" | urbanicity_type== "Mixed" | urbanicity_type=="unknown"	
		replace urbanicity_type="." if urbanicity_type==""
	
	// clean up rapid_test
		destring cv_rapid_test, replace
		replace cv_rapid_test=0 if cv_rapid_test==.

	// indicator that this didn't come from strname's database
		gen _strnames_data=0
		
	// make a local with all of the variables essential of dismod input sheet
		local vars "acause grouping healthstate sequela_name description row_id study_status nid citation file page_num table_num source_type data_type location_type location_id iso3 location_name sex year_start year_end age_start age_end parameter_type mean lower upper standard_error sample_size numerator denominator orig_unit_type orig_uncertainty_type national_type urbanicity_type site socio_characteristics recall_type recall_type_value sampling_type design_effect response_rate case_name case_definition case_diagnostics population_characteristics is_raw data_status issues extractor uploaded notes cv_* _* filepath diagcode"
		
	** Clean up and save
		order `vars'
		keep `vars'
		
		tostring acause grouping healthstate sequela_name description study_status citation file page_num table_num source_type data_type location_type iso3 location_name parameter_type orig_unit_type  site socio_characteristics recall_type sampling_type case_name case_definition case_diagnostics population_characteristics data_status issues extractor notes is_raw national_type urbanicity_type _*, replace
		
		destring row_id nid location_id sex year_start year_end age_start age_end mean lower upper standard_error sample_size numerator denominator recall_type_valu design_effect response_rate orig_uncertainty_type , replace		

	// site is necessary to uniquely identify obs, make it N/A if missing so merges and reshapes work
		replace site="." if site==""
	
	
	// clean up
		tostring orig_uncertainty_type, replace force
		replace orig_uncertainty_type=""
	

	
	// don't want incidence data
		drop if parameter_type=="incidence"

	// identify type of uncertainty
		replace orig_uncertainty_type="CI" if upper!=. & lower!=.
		replace orig_uncertainty_type="ESS" if denominator!=.	
		replace orig_uncertainty_type="SE" if standard_error!=.		
	

	drop if data_status=="excluded"

	tempfile VLEG_round2
	save `VLEG_round2', replace
}

********************************************************
** Clean up
	** ID cause and severity
	** collapse by age for cause/severities with small sample size issues that affect modeling
	** turn all uncertainty into SE
********************************************************
if 1==1 {	
	use `VLEG_round2', clear
	append using `VLEG_round1'

** ID cause and severity	
	// make temporary diagnosis variable I will manipulate throughout this cleaning
	gen diagcode_temp=diagcode

	// clean up diagnosis info
	replace diagcode_temp=subinstr(diagcode_temp, " ", "", .)
	replace diagcode_temp=subinstr(diagcode_temp, "D-MILD", "DMILD", .)
	replace diagcode_temp=subinstr(diagcode_temp, "OTHERGBDMILD", "OTHER-DMILD", .)
	
	// get presenting/best corrected info, okay because always same within single line
	replace cv_presenting=0 if substr(diagcode_temp, -1, .)=="P"
	replace cv_presenting=1 if substr(diagcode_temp, -1, .)=="B"

	// clean up cause info
	replace diagcode_temp=subinstr(diagcode_temp, "All", "ALL", .)
	replace diagcode_temp=subinstr(diagcode_temp, "AMD", "MAC", .)
	replace diagcode_temp=subinstr(diagcode_temp, "GBDRE", "RE", .)
	replace diagcode_temp=subinstr(diagcode_temp, "REGBD", "RE", .)	
	replace diagcode_temp=subinstr(diagcode_temp, "GBDOTHER", "GBDOTH", .)
	replace diagcode_temp=subinstr(diagcode_temp, "OTHERGBD", "GBDOTH", .)	
	replace diagcode_temp=subinstr(diagcode_temp, "OTHERGGBD", "GBDOTH", .)
	replace diagcode_temp=subinstr(diagcode_temp, "OTHER", "GBDOTH", .)
	replace diagcode_temp=subinstr(diagcode_temp, "-CAT", "CAT", .)
	replace diagcode_temp=subinstr(diagcode_temp, "TTRAC", "TRAC", .)
	replace diagcode_temp=subinstr(diagcode_temp, "TRACH", "TRAC", .)
	replace diagcode_temp=subinstr(diagcode_temp, "GLA", "GL", .)
	replace diagcode_temp=subinstr(diagcode_temp, "GBDOTHDVB", "GBDOTH-DVB", .)	
	replace diagcode_temp=subinstr(diagcode_temp, "ARM-", "", .)
	
	// get cause info
	split diagcode_temp, parse(+)
	split diagcode_temp1, parse(-)
	gen cause=diagcode_temp11

	// get number of diagnoses attached to each
	gen diag_num=1
	replace diag_num=2 if diagcode_temp2!=""
	replace diag_num=3 if diagcode_temp3!=""
	replace diag_num=4 if diagcode_temp4!=""
	
	// clean up diagnosis info

	replace diagcode_temp=subinstr(diagcode_temp, "_", "-", .)
	replace diagcode_temp=subinstr(diagcode_temp, "DSV", "DSEV", .)
	replace diagcode_temp=subinstr(diagcode_temp, "DSEVP", "DSEV-P", .)
	replace diagcode_temp=subinstr(diagcode_temp, "-D+", "+", .)
	
	levelsof diagcode_temp11, clean local(causes)
	local cause "ALL"
	foreach cause of local causes {
		replace diagcode_temp=subinstr(diagcode_temp, "`cause'-", "", .)
	}
	replace diagcode_temp=subinstr(diagcode_temp, "-P", "", .)
	replace diagcode_temp=subinstr(diagcode_temp, "-B", "", .)

	replace diagcode_temp="DMOD+DSEV" if diagcode_temp=="DSEV+DMOD"
	replace diagcode_temp="DMOD+DSEV+DVB" if diagcode_temp=="DVB+DSEV+DMOD"
	replace diagcode_temp=subinstr(diagcode_temp, "DMODu", "DMOD", .)
	replace diagcode_temp="DMOD+DSEV+DVB" if diagcode_temp=="DVB+DMOD+DSEV"
	replace diagcode_temp="DSEV+DVB" if diagcode_temp=="DVB+DSEV"
	replace diagcode_temp="DMOD" if diagcode_temp=="DMOD+DMOD"
	

	// make a count of how many studies by different severity group
	preserve
		keep if cause=="ALL"
		contract diagcode_temp
	restore
	
	// more cleaning
	replace cause="GBDOTH" if cause=="GBDOTHGDB"
	replace cause="GBDOTH" if cause=="OTH"


	// keep only the data points for causes: all, macular degenration, cataract, glaucoma, trachoma, diabetic retinopathy, and other blindness (drop refractive error, we calculate it a different way)
	keep if cause == "ALL" | cause=="MAC" | cause == "CAT" | cause == "GL" | cause== "TRAC" | cause == "DR" | cause == "GBDOTH"
	
	gen count=1

	tempfile somewhat_clean
	save `somewhat_clean', replace	

** COLLAPSING AGE GROUPS **
	// some of these studies have small sample sizes for certain causes/severities.  Collapse them down do span more age groups.  
	
	// cedrone study has sample sizes that are way to small for cataract and glaucoma.  collapse down age groups.
	if 1==1 {
		preserve
		clear all
		gen nid=.
		tempfile temp
		save `temp', replace
		restore

		preserve
		local cause CAT
		local d DMOD
		foreach cause in GL CAT MAC GBDOTH {
			foreach d in DMILD DMOD DSEV DVB {
				di in red "`acause' `g'"
				
				use `somewhat_clean', clear
				keep if nid==127531 & cause=="`cause'" & diagcode_temp=="`d'"
				if _N==0 continue
				
				forvalues x=1/2 {
					summ numerator if sex==`x'
					local num_`x'=`r(sum)'
					summ denominator if sex==`x'
					local denom_`x'=`r(sum)'
				}
				
				summ age_start
				local start = `r(min)'
				summ age_end
				local end = `r(max)'
				
				
				keep in 1/2
				replace age_start=`start'
				replace age_end=`end'
				forvalues x=1/2 {
				replace sex=`x' in `x'
				replace numerator=`num_`x'' in `x'
				replace denominator=`denom_`x'' in `x'
				}
				
				replace mean= numerator/denominator
				append using `temp'
				save `temp', replace
			}
		}
		restore
		
		drop if nid==127531 & (cause=="GL" | cause=="CAT" | cause=="MAC") & inlist(diagcode_temp, "DMILD", "DMOD", "DSEV", "DVB")
		append using `temp'
		save `somewhat_clean', replace
	}

	// collapse down age groups for catarct and glaucoma stuff from Beijing Eye Study
	if 1==1 {
		local nid 121969
		local causes "GL CAT MAC"
		local diags "DMILD DMOD DSEV DVB"
	
		preserve
		clear all
		gen nid=.
		tempfile temp
		save `temp', replace
		restore

		preserve
		local cause CAT
		local d DMOD
		foreach cause of local causes {
			foreach d of local diags {
				di in red "`acause' `g'"
				
				use `somewhat_clean', clear
				keep if nid==`nid' & cause=="`cause'" & diagcode_temp=="`d'"
				if _N==0 continue
				
				forvalues x=1/2 {
					summ numerator if sex==`x'
					local num_`x'=`r(sum)'
					summ denominator if sex==`x'
					local denom_`x'=`r(sum)'
				}
				
				summ age_start
				local start = `r(min)'
				summ age_end
				local end = `r(max)'
				
				
				keep in 1/2
				replace age_start=`start'
				replace age_end=`end'
				forvalues x=1/2 {
				replace sex=`x' in `x'
				replace numerator=`num_`x'' in `x'
				replace denominator=`denom_`x'' in `x'
				}
				
				replace mean= numerator/denominator
				append using `temp'
				save `temp', replace
			}
		}
		restore
		
		// drop these observations and replaced with collapsed down versions
		foreach cause of local causes {
			foreach d of local diags {		
				drop if nid==`nid' & cause=="`cause'" & diagcode_temp =="`d'"
			}
		}
		
		append using `temp'
		save `somewhat_clean', replace
	}
	
	// collapse down age groups for blindness due to glaucoma and diabetes for Proyecto VER study out of Johns Hopkins
	if 1==1 {
		// Macular/  - blind
		local diag DVB
		foreach cause in MAC DR {
			use `somewhat_clean', clear
			keep if nid==121974 & cause=="`cause'" & diagcode_temp=="`diag'"

			collapse (sum) numerator denominator, by(diagcode_temp nid cause)
			gen mean= numerator/denominator
			
			gen age_start=40
			gen age_end=99
			gen sex=3
			
			tempfile temp
			save `temp', replace
					
			use `somewhat_clean', clear
			drop if nid==121974 & (sex==2 | age_start!=40) & cause=="`cause'" & diagcode_temp=="`diag'"
			replace age_end=99 if nid==121974  & cause=="`cause'" & diagcode_temp=="`diag'"
			replace sex=3 if nid==121974  & cause=="`cause'" & diagcode_temp=="`diag'"


			merge m:1 nid cause diagcode_temp using `temp', update replace nogen
			save `somewhat_clean', replace
		}
	}	

	// collapse down age groups for blindness due to diabetes for BEAVER DAM STUDY
	if 1==1 {
		use `somewhat_clean', clear
		keep if nid==127362 & cause=="DR" & diagcode_temp=="DVB"

		collapse (sum) numerator denominator, by(diagcode_temp nid cause)
		gen mean= numerator/denominator
		
		gen age_start=45
		gen age_end=89
		gen sex=3
		
		tempfile temp
		save `temp', replace
				
		use `somewhat_clean', clear
		drop if nid==127362 & (sex==2 | age_start!=45) & cause=="DR" & diagcode_temp=="DVB"
		replace age_end=89 if nid==127362  & cause=="DR" & diagcode_temp=="DVB"
		replace sex=3 if nid==127362  & cause=="DR" & diagcode_temp=="DVB"


		merge m:1 nid cause diagcode_temp using `temp', update replace nogen
		save `somewhat_clean', replace
	}	
	
	
	// collapse down age groups for barbados eye study for envelope info
	if 1==1 {
		use `somewhat_clean', clear
		keep if nid==127346 & cause!="ALL"

		collapse (sum) numerator denominator, by(diagcode_temp nid cause)
		gen mean= numerator/denominator
		
		gen age_start=40
		gen age_end=84
		gen sex=3
		
		tempfile temp
		save `temp', replace
				
		use `somewhat_clean', clear
		drop if nid==127346 & (sex==2 | age_start!=40) & cause!="ALL"
		replace age_end=84 if nid==127346  & cause!="ALL"
		replace sex=3 if nid==127346  & cause!="ALL"


		merge m:1 nid cause diagcode_temp using `temp', update replace nogen
		save `somewhat_clean', replace
	}
	
	// collapse down for Bangladesh National Blindness and Low Vision Prevalence Survey 1999-2000. 
	if 1==1 {
		use `somewhat_clean', clear
		keep if nid==121968 & cause=="DR"
		collapse (sum) numerator denominator, by(diagcode_temp nid cause cv_presenting)
		gen mean= numerator/denominator
		
		gen age_start=30
		gen age_end=99
		gen sex=3
		
		tempfile temp
		save `temp', replace
				
		use `somewhat_clean', clear
		drop if nid==121968 & (sex==2 | age_start!=30) & cause=="DR"
		replace age_end=99 if nid==121968  & cause=="DR"
		replace sex=3 if nid==121968  & cause=="DR"

		merge m:1 diagcode_temp nid cause cv_presenting age_end using `temp', update replace nogen
		save `somewhat_clean', replace
	}

** All uncertainty to SE	
	// We are going to generate multiplicative crosswalks.  In order to carry uncertainty forward, we will convert all uncertainty to SE.  Standard way to do this is with Wilson's score interval
	// denominator defined as my effective sample size
		replace sample_size=denominator 
	
		// proportion parameters (Wilson's score interval):
		replace standard_error = sqrt(1/sample_size * mean * (1 - mean) + 1/(4 * sample_size^2) * invnormal(0.975)^2) if orig_uncertainty_type =="ESS"
		
		// non-ratio (max arm approach)
		replace standard_error = max(upper-mean, mean-lower) / invnormal(0.975) if orig_uncertainty_type =="CI"
		
		replace lower=.
		replace upper=.
		replace sample_size=.
		replace denominator=.
		replace orig_uncertainty_type="SE"
	
	
	tempfile clean
	save `clean', replace

}


********************************************************
** Group into 4 different categories (mild, mod, sev, blind) for vision envelope
********************************************************
	// reshape data such that each observation is one study, to be able to split categories into GBD groupings
	
	use `clean', clear

	keep if cause=="ALL" & diagcode_temp!="NVI"	
	
	rename mean d_
	rename standard_error d_se_
	replace diagcode_temp=subinstr(diagcode_temp, "+", "_", .)
	replace diagcode_temp=lower(diagcode_temp) // Force lower case
	
	replace urbanicity_type="." if urbanicity_type==""
	
	isid citation age_start age_end year_start year_end sex iso3 diagcode_temp cv_presenting site cause urbanicity_type
	
	// save a map of all the info we will need later on, but that can't go through on this reshape
	
	tempfile all_cause_long
	save `all_cause_long', replace
	
	keep age_start age_end year_start year_end sex iso3 nid diagcode_temp cv_presenting site cause urbanicity_type d_ 	d_se_
	reshape wide d_ d_se_, i(nid age_start age_end year_start year_end sex iso3 cv_presenting site urbanicity_type) j(diagcode_temp) str

tempfile data_2013
save `data_2013'
	



**************************************************************************************************************
//Add 2015 literature extractions that have GBD severity groupings 
adopath + "J:/WORK/10_gbd/00_library/functions"

* local meid 2426
local i 0
foreach meid in 2426 2566 2567 {
	get_data, modelable_entity_id(`meid') clear 
	keep if inlist(extractor, "rsoren", "areyno")
	if `i' == 0 tempfile data_2015
	else append using `data_2015', force
	save `data_2015', replace
	local ++ i 
	}

	//Label severities as per 2013
		gen diagcode_temp = ""
		replace diagcode_temp = "dvb" if modelable_entity_id == 2426
		replace diagcode_temp = "dmod" if modelable_entity_id == 2566
		replace diagcode_temp = "dsev" if modelable_entity_id == 2567
	
	rename mean d_
	rename standard_error d_se_
	
	drop if is_outlier == 1 
	drop if modelable_entity_id == 2566 & (row_num == 2003 | row_num == 2004) //duplicates 
	drop if modelable_entity_id == 2567 & row_num == 2145 //duplicates 


	isid nid modelable_entity_id age_start age_end year_start year_end sex location_id diagcode_temp cv_presenting 

	keep nid age_start age_end year_start year_end sex location_id diagcode_temp cv_presenting d_ 	d_se_
	reshape wide d_ d_se_, i(nid age_start age_end year_start year_end sex location_id cv_presenting) j(diagcode_temp) str


append using `data_2013', force



// make clean categories that I want to keep... this info put in because it's already in GBD categories we want
	cap gen adj_mild=d_dmild
	cap gen adj_mod=d_dmod
	cap gen adj_sev=d_dsev
	cap gen adj_vb=d_dvb
	cap gen adj_nvi=d_nvi
	
	cap gen adj_se_mild=d_se_dmild
	cap gen adj_se_mod=d_se_dmod
	cap gen adj_se_sev=d_se_dsev
	cap gen adj_se_vb=d_se_dvb
	cap gen adj_se_nvi=d_se_nvi
	
	tempfile clean_grouped
	save `clean_grouped', replace


******************************************************************************
// MAKE CROSSWALK MAP 
******************************************************************************
	** make tempfile to save these age-adjusted proportions (this functions as a map)
	use `clean_grouped', clear
	contract age_start
	drop _f
	tempfile proportions
	save `proportions', replace


*********************************
	** Proportons first
	*********************************
	
if "sev"=="sev" {	
// Get proportions from d_dmod_dsev_dvb
	local group d_dsev_dvb
	foreach cat in sev vb {
		use `clean_grouped', clear
		keep if d_dsev!=. & d_dvb!=.
		gen total= d_dsev + d_dvb
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}	
}

if "mild"=="mild" {	
// Get proportions from d_dmild_dmod 
	local group d_dmild_dmod 
	foreach cat in mild mod {
		use `clean_grouped', clear
		keep if d_dmild!=. & d_dmod!=. 
		gen total=d_dmild + d_dmod
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}

// Get proportions from d_dmild_dmod_dsev
	local group d_dmild_dmod_dsev
	foreach cat in mild mod sev {
		use `clean_grouped', clear
		keep if d_dmod!=. & d_dmild!=. & d_dsev!=.
		gen total=d_dmild + d_dmod + d_dsev
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}

// Get proportions from d_dmild_dmod_dsev_dvb
	local group d_dmild_dmod_dsev_dvb
	foreach cat in mild mod sev vb {
		use `clean_grouped', clear
		keep if d_dmod!=. & d_dmild!=. & d_dsev!=. & d_dvb!=.
		gen total=d_dmild + d_dmod + d_dsev + d_dvb
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}
}

if "mod"=="mod" {	
// Get proportions from d_dmod_dsev
	local group d_dmod_dsev
	foreach cat in mod sev {
		use `clean_grouped', clear
		keep if d_dmod!=. & d_dsev!=.
		gen total=d_dmod + d_dsev
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}
	
// Get proportions from d_dmod_dsev_dvb
	local group d_dmod_dsev_dvb
	foreach cat in mod sev vb {
		use `clean_grouped', clear
		keep if d_dmod!=. & d_dsev!=. & d_dvb!=.
		gen total= d_dmod + d_dsev + d_dvb
		gen `cat'_prop=d_d`cat'/total
		regress `cat'_prop age_start
		
		use `proportions', clear
		predict `cat'_p_`group', xb
		predict `cat'_p_`group'_se, stdp
		save `proportions', replace
	}	
	
}

// save these proportions in the temp folder for posterity
	use `proportions', clear
	
	save `proportions', replace
	save "`proportions_map'", replace


