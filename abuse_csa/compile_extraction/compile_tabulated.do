// Update: 4.28/2015; Original version: 3/28/2014
// Compile and format childhood sexual abuse data for GBD 2015

// SET UP
	clear all
	set more off
	
// Set locals for relevant files
	local data_dir "J:/WORK/05_risk/risks/abuse_csa/data/exp/01_tabulate/prepped"
	local outdir "J:/WORK/05_risk/risks/abuse_csa/data/exp/02_compile"
	local dismod_dir_female "J:/WORK/05_risk/risks/abuse_csa_female/data/exp/3054/input_data/"
	local dismod_dir_male "J:/WORK/05_risk/risks/abuse_csa_male/data/exp/3053/input_data/"
	local re_extracted "J:/DATA/Incoming Data/WORK/05_risk/1_ready/citation_research/data_files/abuse_csa_2014_july_9_total.xlsx"
	local nids "J:/DATA/Incoming Data/WORK/05_risk/1_ready/csa_ipv_GBD_2010/GBD_2010_CSA_sources_batch1of2_Y2014M03D24.csv"
	
	// Prepare location names & demographics for 2015

	run "J:/WORK/10_gbd/00_library/functions/get_location_metadata.ado" 
	get_location_metadata, location_set_id(9) clear
	keep if is_estimate == 1 & inlist(level, 3, 4)

	keep ihme_loc_id location_id location_ascii_name super_region_name super_region_id region_name region_id
	
	tostring location_id, replace
	rename ihme_loc_id iso3
	
	tempfile countrycodes
	save `countrycodes', replace	

// Prep sourcing spreadsheet that has NIDs from the data indexers
	insheet using "`nids'", comma clear
	duplicates drop uniqueid author country_iso3_code year_start year_end, force
	gen source_type = 1 if field_type == "Scientific literature"
	replace source_type = 2 if field_type == "Survey" | regexm(title, "Survey")
	replace source_type = 5 if field_type == "Report"
	replace citation = field_citation
	drop field*
	tempfile citations
	save `citations'
	
// Prep GBD 2010 data
	insheet using "`data_dir'/M_F_DisMod_Input_crosswalk0_onlydropped_dups_onlyextractedcis_allageKD_dropped.csv", comma clear
	merge m:1 uniqueid author country_iso3_code year_start year_end using `citations', nogen
		
	** Make variables consistent with new Epi template
	replace sex = "1" if sex == "male"
	replace sex = "2" if sex == "female"
	destring sex, replace
	recode standard_error (-99 = .)
	rename country_iso3_code iso3
	rename parameter_value mean
	rename lower_ci lower
	rename upper_ci upper
	rename effective_sample_size sample_size
	rename parameter parameter_type
	rename parametertype case_name
	gen description = "GBD 2010: abuse_csa"


	
	foreach covar in contact noncontact intercourse child_over_15 child_under_15 nointrain perp3 notviostudy1 loqual  {
		rename `covar' cv_`covar'
		recode cv_`covar' (. = 0)
	}

	tempfile raw
	save `raw', replace

// Prep for merge with re-extracted/checked GBD 2010 expert group data
	keep nid iso3 year_start year_end citation 
	duplicates drop	
	
	tempfile identifiers
	save `identifiers', replace
	
// Prep re-extracted/checked GBD 2010 expert group data
	import excel using "`re_extracted'", firstrow sheet("data") clear
	
		** Update sources to reflect subnational units 
	
	//replace location_name = "Guangdong" if regexm(citation, "Individual, familial and community determinants of child physical abuse among high-school students in China")
	//replace location_id = "496" if location_name == "Guangdong"
	replace location_name = "California" if regexm(citation, "The Relationship Between Child Abuse and Adult Obesity Among California Women")
	replace location_id = 527 if location_name == "California"
	replace location_name = "Distrito Federal" if regexm(citation, "Descriptive Epidemiology of Chronic Childhood Adversity in Mexican Adolescents")
	replace location_id = 4651 if location_name == "Distrito Federal"
	//replace location_name = "Oaxaca, Jalisco, Yucatan, Sonora" if regexm(citation, "Childhood trauma and adulthood physical health in Mexico") 
	//replace location_id = 4662, 4656, 4673, 4668 if regexm(location_name, "Oaxaca") 
	replace location_name = "Riyadh" if regexm(citation, "Correlates of sexual violence among adolescent females in Riyadh, Saudi Arabia")
	replace location_id = 44543 if location_name == "Riyadh" 
	replace location_name = "Morelos" if regexm(citation, "Factors for sexual abuse during childhood and adolescence in students of Morelos, Mexico")
	replace location_id = 4659 if location_name == "Morelos"
	replace location_name = "Colima" if regexm(citation, "Prevalence of childhood sexual abuse among Mexican adolescents")
	replace location_id = 4648 if location_name == "Colima"
	replace location_name = "Nairobi, Western Cape" if regexm(citation, "Trauma exposure and post-traumatic stress symptoms in urban African schools. Survey in CapeTown and Nairobi")
	replace location_id = 35646 if location_name == "Nairobi, Western Cape"
	//replace location_name = "Goa, Urban, Goa, Rural" if title == "Prevalence and Correlates of Perpetration of Violence Among Young People: A Population-Based Survey From Goa, India"
	//replace location_id = "43881, 43917" if location_name == "Goa, Urban, Goa, Rural"
	replace location_name = "Delhi, Urban" if regexm(citation, "Nonconsensual Sexual Experiences of Adolescents in Urban India")
	replace location_id = 43880 if location_name == "Delhi, Urban"
	replace location_name = "Henan" if regexm(citation, "Child sexual abuse in Henan province, China: associations with sadness, suicidality, and risk behaviors among adolescent girls")
	replace location_id = 502 if location_name == "Henan"
	replace location_name = "Western Cape" if regexm(citation, "Substance abuse and behavioral correlates of sexual assault among South African adolescents")
	replace location_id = 490 if location_name == "Western Cape"
	replace location_name = "Massachusetts" if regexm(citation, "Health status and health care use of Massachusetts women reporting partner abuse")
	replace location_id = 544 if location_name == "Massachusetts"
	replace location_name = "Nyeri" if regexm(citation, "The Experience of Sexual Coercion among Young People in Kenya")
	replace location_id = 35652 if location_name == "Nyeri" 

	** Drop GENACIS data that was provided by the experts in 2010 because now we have access to the micro-data and have re-tabulated it ourselves 
	drop if nid == 150528 
	
	** DROP BRFSS data - re-extracted ourselves for years 2009, 2010, 2011, 2012 
	drop if inlist(nid, 30018, 83627, 83633, 104825)

	** Fix mistake with missing covariate value - assume missing is 0
	replace cv_child_over_15 = "0" if !inlist(cv_child_over_15, "1", "0")
	destring cv_child_over_15, replace
	
	tempfile re_extracted
	save `re_extracted', replace
	
	** Bring in Australia sources recommended by expert
	insheet using "`data_dir'/aus_potential_sources.csv", comma clear
	gen description = "GBD 2013: abuse_csa"
	gen data_type = "Study: unspecified" if inlist(source_type, "Literature", "Other") 
	replace data_type = "Survey: unspecified" if source_type == "Survey"
	append using `re_extracted'
	
	** Make variables consistent with epi template
	encode source_type, gen(sourcetype)
	drop source_type
	rename sourcetype source_type
	recode source_type (2=6) (3=2)
	label drop sourcetype
	
	encode national_type, gen(nationaltype)
	drop national_type
	rename nationaltype national_type
	label drop nationaltype
	
	tostring location_id, replace

	** Save sourced data
	tempfile sourced
	save `sourced', replace
	
// Merge 
	** Make datset restricted to observations that were accidentally excluded from the dataset for re-extraction/sourcing (i.e. excluded from this file: "J:/DATA/Incoming Data/WORK/05_risk/1_ready/citation_research/data_files/abuse_csa_2014_july_9_total.xlsx")
	merge m:1 nid iso3 year_start year_end using `identifiers'
	keep if _merge == 2 & nid != .
	keep nid iso3 year_start year_end site
	merge 1:m nid iso3 year_start year_end using `raw', nogen keep(match)
	
	** Append the re-extracted datasets
	append using `sourced'

// Clean up
	** Drop all data that does not meet GBD or cause definitions
	drop if exclusion_reference == 1
		
	** Drop incorrect extractions
	drop if incorrect_extraction == 1 & re_extracted == 0
	
	** Format study level covariates
	replace cv_child_over_15 = 1 if (cv_child_18 == 1 | cv_child_18plus == 1 | cv_child_16_17 == 1)
	replace cv_child_over_15 = 0 if cv_child_under_15 == 1 | cv_child_over_15 == .
	//replace cv_anym_quest = anonymous_questionnaire if anym_quest == .
	//drop anonymous_questionnaire

	foreach covar in contact noncontact intercourse child_over_15 child_under_15 nointrain perp3 notviostudy1 parental_report school anym_quest loqual  {
		recode cv_`covar' (. = 0)
	}
	drop if cv_parental_report == 1

	tempfile gbd2010
	save `gbd2010', replace 

// Prep GBD 2013
	insheet using "`data_dir'/GBD_2013_CSA.csv", comma clear
	
	gen location_name = ""
	gen location_id = ""
	replace location_name = "Hunan" if site == "Hunan province" 
	replace location_id = "504" if location_name == "Hunan"
	replace location_name = "Beijing, Shanghai" if site == "representative of Beijing and Shanghai"
	replace location_id = "492, 514" if location_name == "Beijing, Shanghai" 
	replace location_name = "Tianjin, Guangdong, Shanghai, Shaanxi, Hubei, Hong Kong" if site == "Tianjin, Shenzhen, Shanghai, Xi’an, Wuhan and Hong Kong"
	replace location_id = "517, 496, 514, 512, 503, 354" if regexm(location_name, "Tianjin") 

	append using "`data_dir'/brfss_prepped.dta"
	append using "`data_dir'/brfss_states_prepped.dta" // sure we want to include states and national?

	replace case_definition = "An adult touched you sexually, made you touch them sexually, or forced you to have sex before the age of 18" if regexm(file, "BRFSS") 
	replace iso3 = "USA" + "_" + location_id if iso3 == "USA" & location_id != "102" 
	replace iso3 = "USA" if iso3 == "USA_" 
	gen description = "GBD 2013: abuse_csa"

// Prep GBD 2015 additional data (GENACIS) 
	append using "`data_dir'/genacis_prepped.dta"
	replace file = "J:/DATA/GENDER_ALCOHOL_CULTURE_INTERNATIONAL_STUDY_GENACIS" if file == ""  & survey_name == "GENACIS" 
	replace case_definition = "Someone in your family or other than your family made you do sexual things or watch sexual things" if file == "J:/DATA/GENDER_ALCOHOL_CULTURE_INTERNATIONAL_STUDY_GENACIS"

	append using "`data_dir'/add_health_prepped.dta"

	replace case_definition = "A parent or adult caregiver touched you in a sexual way, forced you to touch him or her in a sexual way, or forced you to have sexual relations" if nid == 120195

	append using "`data_dir'/isl_youth_survey_prepped.dta"

	replace case_definition = "Someone exposed themselves to you against your will in improper ways; genital and non-genital touching; forced you to have sex/intercourse" if iso3 == "ISL" 


// Combine and format GBD 2010 and GBD 2013 data
	append using `gbd2010'

	tempfile all_but_ubcov 
	save `all_but_ubcov', replace 

// Add in 2015 CSA lit extractions 
	import excel using "`data_dir'/GBD_2015_CSA.xlsx", firstrow clear 
	tostring urbanicity_type, replace
	tostring citation, replace
	
	replace units = 1 
	gen lit = "1" 

	tostring site, replace
	tostring notes, replace
	tostring questionnaire, replace

// Append all together except ubcov output
	append using `all_but_ubcov'

	** Format units
	foreach var in mean standard_error upper lower { 
		replace `var' = `var' / units if units != . & mean != . 
	}

	replace iso3 = iso3 + "_" + location_id if iso3 == "CHN" & (location_name == "Hunan" | location_name == "Henan") 
	replace iso3 = iso3 + "_" + location_id if iso3 == "IND" & location_name == "Delhi, Urban"
	replace iso3 = iso3 + "_" + location_id if iso3 == "MEX" & location_name == "Distrito Federal"
	rename location_id location_id_old
	merge m:1 iso3 using `countrycodes', keep(3) nogen 
	drop location_type 
	drop location_id_old 
	

	foreach covar in contact noncontact intercourse child_over_15 child_under_15 nointrain perp3 notviostudy1 parental_report school anym_quest loqual  {
		replace cv_`covar' = `covar' if cv_`covar' == . 
		recode cv_`covar' (. = 0)
		drop `covar'
	}
	

	save `all_but_ubcov', replace


// Clean up ubcov output 

	use `countrycodes', clear 
	duplicates tag location_ascii_name, gen(dup) 
	drop if dup == 1 & !regexm(iso3, "BRA") & !regexm(iso3, "GEO") 
	drop dup
	save `countrycodes', replace

	use "`data_dir'/collapsed_abuse_csa.dta", clear 
	rename subnat_id location_name 
	rename ihme_loc_id iso3
	merge m:1 iso3 using `countrycodes', keep(1 3) nogen 
	rename location_id location_id_old 
	replace location_name = "Amapa" if location_name == "Amapá" 
	replace location_name = "Ceara" if location_name == "Ceará"
	replace location_name = "Goias" if location_name == "Goiás" 
	replace location_name = "Maranhao" if location_name == "Maranhão" 
	replace location_name = "Parana" if location_name == "Paraná" 
	replace location_name = "Para" if location_name == "Pará" 
	replace location_name = "Rondonia" if location_name == "Rondônia"
	replace location_name = "Sao Paulo" if location_name == "São Paulo" 
	replace location_name = "Espirito Santo" if location_name == "Espírito Santo"
	replace location_name = "Piaui" if location_name == "Piauí" 

	replace location_ascii_name = location_name if location_name != "" 

	merge m:1 location_ascii_name using `countrycodes', keep(1 3) nogen 
	drop location_id_old 

	tempfile ubcov 
	save `ubcov', replace

	insheet using "`outdir'/convert_to_new_age_ids.csv", comma names clear 
	rename age_group_id age_id
	merge 1:m age_id using `ubcov', keep(3) nogen
	gen age_end = age_start + 4 
	replace iso3 = iso3 + "_" + location_id if regexm(file_path, "BRA") & location_name != "" 
	rename se standard_error
	rename sd standard_deviation
	rename ss sample_size 
	rename sex_id sex 
	drop subnat_est list_flag collapse_flag standard_deviation
	rename anonymous anym_quest
	rename notviostudy notviostudy1
	drop age_id
	rename file_path file 

	** Format study level covariates
	replace child_over_15 = 1 if (child_18 == 1 | child_18plus == 1 | child_16_17 == 1)
	replace child_over_15 = 0 if child_under_15 == 1 | child_over_15 == .
	foreach covar in contact noncontact intercourse child_over_15 child_under_15 nointrain perp3 notviostudy1 parental_report school anym_quest loqual  {
		rename `covar' cv_`covar'
		recode cv_`covar' (. = 0)
	}
	drop if cv_parental_report == 1

	
	** Fix mistake with missing covariate value - assume missing is 0
	rename child_16_17 cv_child_16_17 
	rename child_18 cv_child_18
	rename child_18plus cv_child_18plus

	** Fill in case definitions 
	replace case_definition = "Forced sexual intercourse by a man before the age of 15" if regexm(file, "CDC_RHS") 

	save `ubcov', replace
	

// Append all of the other new data sources

	append using `all_but_ubcov'
	replace location_name = state if state != "" 
	replace location_id = "83" if iso3 == "ISL" 
	replace location_id = "102" if nid == 120195 // U.S. National Longitudinal Study of Adolescent Health
	replace nid = 139804 if location_id == "94" & nid == . 
	** Define source types
	drop source_type
	gen source_type = 26 
	label define source 26 "Survey - other/unknown" 
	label values source_type source

// Specify representation
	rename national_type representative_name
	replace representative_name = 1 if representative_name == . & (representation == "national" | subnational == 0)
	replace representative_name = 2 if representative_name == . & (representation == "subnational" | subnational == 1)
	replace representative_name = 1 if representative_name == .

	replace representative_name = 4 if regexm(file, "BRA") 

	label define national 1 "Nationally representative only" 2 "Representative for subnational location only" 3 "Not representative" 4 "Nationally and subnationally representative" /// 
	5 "Nationally and urban/rural representative" 6 "Nationally, subnationally and urban/rural representative" 7 "Representative for subnational location and below" /// 
	8 "Representative for subnational location and urban/rural" 9 "Representative for subnational location, urban/rural and below" 10 "Representative of urban areas only" /// 
	11 "Representative of rural areas only" 
	label values representative_name national

	// Epi uploader wants as string value
	decode representative_name, gen(rep_name_new)
	rename representative_name rep_name_numeric
	rename rep_name_new representative_name
	
// Specify location type
/*
	replace urbanicity_type = lower(urbanicity_type)
	encode urbanicity_type, gen(urbanicitytype)
	drop urbanicity_type
	rename urbanicitytype urbanicity_type
	recode urbanicity_type (1=0) (2=1) (4=2)
	label drop urbanicitytype
*/
	replace urbanicity_type = "Mixed/both" if urbanicity_type == "mixed" 
	replace urbanicity_type = "Mixed/both" if urbanicity_type == "representative" 
	replace urbanicity_type = "Rural" if urbanicity_type == "rural" 
	replace urbanicity_type = "Urban" if urbanicity_type == "urban"
	replace urbanicity_type = "Unknown" if urbanicity_type == "unknown" 

	replace urbanicity_type = "Mixed/both" if representative_name == "Nationally representative only"
	replace urbanicity_type = "Urban" if urban == 1 & urbanicity_type == ""
	replace urbanicity_type = "Rural" if urban == 0 & urbanicity_type == "" 
	replace urbanicity_type = "Unknown" if urbanicity_type == "." | urbanicity_type == ""
	//label define urbanicity 0 "Unknown" 1 "Mixed/both" 2 "Urban" 3 "Rural" 4 "Suburban" 5 "Peri-urban"

	
// Fix uncertainty variables
	recode lower upper standard_error (0=.)
	replace lower = . if upper == .
	replace upper = . if lower == .
	drop if sample_size < 10 // These means are too unstable
	rename orig_uncertainty_type uncertainty_type
	replace uncertainty_type = "Confidence interval" if lower != . & upper != .
	replace uncertainty_type = "Standard error" if standard_error != . & uncertainty_type == ""
	replace uncertainty_type = "Effective sample size" if uncertainty_type == "" | uncertainty_type == "ESS"	
	replace uncertainty_type = "Standard error" if uncertainty_type == "SE"
	gen uncertainty_type_value = 95 if uncertainty_type == "Confidence interval" 
	replace uncertainty_type_value = . if lower == . 
	
// Fill in case name
	
	// replace those case definitions that are ambiguous (for 2010 expert extractions, some observations were just tagged as ever any CSA without specifying whether this included contact or non-contact)

	replace case_definition = "Have physical sexual relations against your will or do a sexual act that you did not want" if nid == 19728 
	replace case_definition = "Sexual assault" if nid == 120028
	replace case_definition = "Anyone ever made you do something sexual you didn't want to or touched you in a (sexually) embarrassing way" if inlist(nid, 126423, 126424)
	replace case_definition = "Forced to have sexual intercourse or engaging in a sexual act they found degrading or humiliating" if nid == 126427
	replace case_definition = "Anyone ever touched them sexually or made them do something sexual they didn't want to do"
	replace case_definition = "" if nid == 136822
	replace case_definition = "Someone in your family or other than your family made you do sexual things or watch sexual things" if inlist(nid, 136824, 137017) // GENACIS-based literature
	replace case_definition = "Involving a child in sexual activity beyond their understanding or contrary to currently accepted community standards" if nid == 137013 
	replace case_definition = "Flashing, being touched, being pressured to have sex and attempted and actual assaults/rapes" if nid == 137023 
	replace case_definition = "Person younger than 16 years olf being involved in any kind of sexual activity, such as genital fondling, an adult exhibiting his or her genitalia to a child, forcing the child to exhibit himself or herself to the adult or forcing the chidl to have sexual intercourse with someone at least 5 years older or with a family member at least 2 years older than the victim" if nid == 137133 
	replace case_definition = "Forceful sexual intercourse, any form of verbal abuse or harrassment, fondling with private body parts and unwanted sexual comments" if nid == 137134
	replace case_definition = "Students reporting someone touchign their private parts in a way they didn't like or being forced to have sexual intercourse" if nid == 137135 
	replace case_definition = "Before the age of 18, did anyone ever force you into unwanted sexual activity by using force or threatening to harm you" if nid == 137136
	replace case_definition = "Having one or more unwanted sexual experiences before age 16 years" if nid == 137137 
	replace case_definition = "A child (anyone under 16 years) is abused when another person who is sexually mature involves in the child in any activity which the other person expects to lead to sexual arousal, including intercourse, touching, exposure of the sexual organs, showing pornographic  material or talking about sexual things in an erotic way" if nid == 137139 
	replace case_definition = "Sexual assault and sexual molestation" if nid == 137140 
	replace case_definition = "Before the age of 18, do you remember someone trying or succeeding in having sexual intercourse with you, touching you, grabbing you, kissing you, rubbing against your body in either a public place or private, taking nude photographs of you, exhibiting parts of their body to you, performing some sex act in your presence, or an experience involving oral sex or sodomy" if nid == 137141 
	replace case_definition = "Ever been sexually abused" if nid == 137144 
	replace case_definition = "Contact or noncontact sexual assault including voyeurism, exhibitionism and requests to engage in sexual behavior by a parent or adult relative, involved genital contact, clothes or unclothes, between the child and the perpetrator" if nid ==  137145 
	replace case_definition = "" if nid == 137146 
	replace case_definition = "Being forced to have sexual relations without consent under the age of 18" if nid == 137147 
	replace case_definition = "Contact or noncontact sexual abuse experiences" if nid == 137148
	replace case_definition = "Young people persuaded or forced into sexual activities involving exhibitionism, genital fondling, oral, vaginal or anal intercourse, and posing for sex photos or film" if nid == 137153 
	replace case_definition = "Before the age of 15, do you remember if anyone in your family ever touched you sexually, or made you do something sexual that you didn’t want to do" if nid == 137155
	replace case_definition = "Sexual abuse including serious noncontact, contact and rape" if nid == 137156 
	replace case_definition = "Sexual victimization including rape, sexual exposure/flashed, sexual harrassment, and sexual misconduct/statutory rape" if nid == 137157 
	replace case_definition = "Been touched in a sexual way that they did not want or that they had been made to do sexual things that they did not wish to do" if nid == 137158
	replace case_definition = "A parent or adult caregiver touched you in a sexual way, forced you to touch him or her in a sexual way, or forced you to have sexual relations" if nid == 137159
	replace case_definition = "Indecent exposure, touching and abudction" if nid == 137160 
	replace case_definition = "Unwanted sexual acts, contact or noncontact" if nid == 137161
	replace case_definition = "Sexual abuse with and without contact" if nid == 137163 
	replace case_definition = "Sexual abuse including experiences with no physical contact, physical contact but no intercourse, and attempted or completed intercourse" if nid ==  137164 
	replace case_definition = "Having been raped, kissed, or forced to undress or perform sexual acts against their will or as having had private body parts touched " if nid == 137165
	replace case_definition = "" if nid == 137168 
	replace case_definition = "Someone in your family or other than your family made you do sexual things or watch sexual things" if nid == 137169 
	replace case_definition = "Sexual maltreatement including sexual comments, trying to touch in a sexual manner and making sexual advances" if nid == 137170 
	replace case_definition = "Sexual abuse of those under 16 when the perpetrator is 5 years older than the victim and abuse includes exhbitionism, verbal propositions, or contact" if nid ==  137172 
	replace case_definition = " " if nid == 137173 
	replace case_definition = "Ever been coerced (physically or mentally) to have sexual contact or sexual intercourse against your will" if nid == 137175 
	replace case_definition = "Experiences of those under 16 with contact or noncontact sexual behavior against their wishes by a person 5+ years older" if nid == 137176 
	replace case_definition = "Sexual abuse including pornography, indecent exposure, contact abuse, attempted penetration, or penetration/oral sex" if nid == 137177
	replace case_definition = "sexual contact imposed on a child whose development is still, from the emotional, cognitive and maturity point of view, lacking" if nid == 137178 
	replace case_definition = "Childhood sexual abuse prior to age 16 includes any older person inviting or requesting them to do something sexual, kissing or hugging in a sexual way, touching or fondling their private parts, showing their sex organs to them, making them touch in a sexual way or attepmting or having sexual ever_intercourse_csa" if nid == 137179 
	replace case_definition = "When you were 12/13 years or younger, did someone ever do something sexual to you, ever expose him/herself, suggest a sexual act, fondle or kiss your genitals, insert something into your anus or vagina" if nid == 137180
	replace case_definition = "Sexual abuse includes both with and without penetration before the age of 18 years" if nid ==  137181 
	replace case_definition = " " if nid == 137183
	replace case_definition = "Some tried to touch them in a sexual way, someone tried to make them touch the other person in a sexual way, someone sexually abused them, someone threatened to tell lies about them or hurt them if they did not do anything sexual with them" if nid == 137184 
	replace case_definition = "Ever forced by anyone to have sexual contact in their childhood, including contact or noncontact abuse" if nid == 137185
	replace case_definition = "Someone in your family or other than your family made you do sexual things or watch sexual things" if nid == 137186 
	replace case_definition = " " if nid == 137190
	replace case_definition = "Has someone touched your body, excluding genitals in an indecent way, touched your genitals, forced you to touch his/her genitals, or forced you to have intercourse" if nid == 137191
	replace case_definition = " " if nid == 137192
	replace case_definition = "Before the age of 15 do you remember being forced to have sex or participate in any sexual act that you did not want" if nid == 137194
	replace case_definition = " " if nid == 137195 
	replace case_definition = "Forced into sexual acts including contact and noncontact" if nid == 137196
	replace case_definition = " " if nid == 137197 
	replace case_definition = "Sexual victimization is when someone in your family, or someone else, touches you ina  place you did not want to be touched, or does something to you sexually which they shouldn't have" if nid == 137198 
	replace case_definition = "Contact or noncontact sexual abuse including exposure, exhibitionism, touching/fondling, sexual kissing, oral-genital activity, anal intercourse and vaginal intercourse" if nid == 137200 
	replace case_definition = " " if nid == 137280 
	replace case_definition = " " if nid == 148641
	replace case_definition = " " if nid == 148642
	replace case_definition = "Those who experienced unwanted contact or noncontact sexual experiences before 16" if nid == 148643
	replace case_definition = " " if nid == 148645 
	replace case_definition = "Sexually abused while growing up" if nid == 148648 
	replace case_definition = "Wheter someone tried or succeeded in doing something sexual to them or made them do something sexual against their wishes before the age of 18" if nid == 150368
	replace case_definition = "Exposed to any of the following against their will: non-contact abuse, contact abuse, penetrative abuse " if nid == 150369 
	replace case_definition = "Before the age of 18, do you remember someone trying or succeeding in having sexual intercourse with you, touching you, grabbing you, kissing you, rubbing against your body in either a public place or private, taking nude photographs of you, exhibiting parts of their body to you, performing some sex act in your presence, or an experience involving oral sex or sodomy" if nid == 150416 
	replace case_definition = "Being touched in a sexual way or made to do things you did not want to do" if nid == 150424
	replace case_definition = "Somebody exposed him/herself indecently toward you, touched your body, excluding genitals, in an indecent way, touched your genitals, persuaded, pressed or forced you to touch his/her genitals, or forced you to have intercourse" if nid == 150429
	replace case_definition = "Unwanted sexual touching and unwanted sexual intercourse before the age of 18" if nid == 150446 
	replace case_definition = "Range of sexual victimization including rape, sexual assault, flashing, sexual harrassment, statutory sexual offense, or internet sex talk" if nid == 150447
	replace case_definition = "Sexual abuse before the age of 15 years including whether anyone had ever touched them sexually or made them do something sexual that they did not want" if inlist(nid == 150513, 150514, 150515, 150516, 150517, 150518, 150522, 150523, 150524)
	replace case_definition = " " if nid == 150532 
	replace case_definition = " " if nid == 150747 


	foreach var in cv_noncontact cv_intercourse cv_contact { 
		rename `var' `var'_old
	}

		//drop cv_noncontact cv_intercourse cv_contact 

	gen cv_noncontact = case_name == "Ever_non_contact_CSA" | regexm(case_definition, "Without Contact") | regexm(case_definition, "non-contact victimization csa") | cv_noncontact_old == 1

	gen cv_intercourse = case_name == "Ever_intercourse_CSA" | regexm(case_definition, "Forced sexual intercourse by a man") | regexm(case_definition, "unwanted intercourse prior to survey date") | cv_intercourse_old == 1 

	//naming this contact only so i can upload but should really be contact_noncontact
	
	gen cv_contact_noncontact = case_name == "Ever_any_CSA" & case_definition == "ever_any_CSA" & regexm(case_definition, "watch sexual things") | regexm(case_definition, "6 items: All forms") | regexm(case_definition, "sexual activity beyond their understanding") | regexm(case_definition, "exposed themselves to you against your will") | regexm(case_definition, "Telephone Interview") | regexm(case_definition, "(c) non-contact forms") | regexm(case_definition, "contact or noncontact CSA") | regexm(case_definition, "unwanted sexual comments") | regexm(case_definition, "flashing") | regexm(case_definition, "exhibiting his or her genitalia") | regexm(case_definition, "one or more unwanted sexual experiences") | regexm(case_definition, "showing pornographic  material or talking about sexual things in an erotic way") | regexm(case_definition, "taking nude photographs of you") | regexm(case_definition, "contact or noncontact") | regexm(case_definition, "posing for sex photos") | regexm(case_definition, "made you do something sexual that you didn't want to do") | regexm(case_definition, "serious noncontact, contact") | regexm(case_definition, "sexual exposure/flashed") | regexm(case_definition, "made to do sexual things that they did not wish to do") | regexm(case_definition, "indecent exposure") | regexm(case_definition, "with and without contact") | regexm(case_definition, "no physical contact, physical contact") | regexm(case_definition, "verbal propositions, or contact") | regexm(case_definition, "showing their sex organs") | regexm(case_definition, "expose themselves") | regexm(case_definition, "tell lies about them") | regexm(case_definition, "non-contact abuse, contact abuse") | regexm(case_definition, "exposed him/herself indecently") | regexm(case_definition, "internet sex talk") 

	drop cv_noncontact_old cv_intercourse_old cv_contact_old
// just have to look into case_definition that was "ever_any_CSA" 

/*
	replace case_definition = "" if case_definition == "ever_any_CSA" & cv_intercourse == 1 | cv_contact == 1 | cv_noncontact == 1
	replace case_name = "ever_any_csa" if cv_intercourse == 0 & cv_contact == 0 & cv_noncontact == 0
	replace case_name = "ever_contact_csa" if cv_intercourse == 0 & cv_contact == 1 & cv_noncontact == 0
	replace case_name = "ever_contact_or_intercourse" if cv_intercourse == 1 & cv_contact == 1 & cv_noncontact == 0
	replace case_name = "ever_intercourse_csa" if cv_intercourse == 1 & cv_contact == 0 & cv_noncontact == 0
	replace case_name = "ever_noncontact_csa" if cv_intercourse == 0 & cv_contact == 0 & cv_noncontact == 1
	
	*/ 

// Fill in epi variables
		** Fill in sex-specific variables
	drop sequela_name
	gen modelable_entity_id = 3053 if sex == 1
	replace modelable_entity_id = 3054 if sex == 2
	gen modelable_entity_name = "Female childhood sexual abuse" if sex == 2
	replace modelable_entity_name = "Male childhood sexual abuse" if sex == 1
	
	** Try including mixed sex data points in both models with study level covariate
	drop if sex == 3 

	tostring sex, replace 
	replace sex = "Male" if sex == "1"
	replace sex = "Female" if sex == "2"

	destring location_id, replace
	
// Final things for epi uploader
	 rename sample_size effective_sample_size

	gen unit_value_as_published = 1 
	gen unit_type = "Person"
	gen measure = "proportion"	
	replace recall_type = "Lifetime" if recall_type == "" 
	replace extractor = "lalexan1" if extractor == "" 
	gen is_outlier = 0 
	gen underlying_nid = . 
	//gen sampling_type = . 
	//gen recall_type_value = . 
	gen input_type = "" 
	gen sample_size = . 
	gen cases = . 
	//gen design_effect = . 
	gen site_memo = "" 
	//gen case_diagnostics = . 
	gen note_SR = "" 
	gen note_modeler = "" 
	gen row_num = . 
	gen parent_id = . 
	gen data_sheet_file_path = "" 


// Mark data points that should be excluded
	tostring data_status, replace
	replace data_status = "outlier" if iso3 == "AUS" & representative_name == "Representative for subnational location only" // Have plenty of nationally representative data and these data points seemed far too high
	replace data_status = "outlier" if sex == "." // Decided not to use combined sex data points after all
	// tabmiss `variables'
	

// Only keep necessary variables
	local variables row_num modelable_entity_id modelable_entity_name description measure	nid	file location_name	location_id	/// 
	sex	year_start	year_end	age_start	age_end	measure	mean	lower	upper	standard_error	effective_sample_size	/// 
	unit_type	uncertainty_type uncertainty_type_value	representative_name	urbanicity_type	case_definition	extractor ///
	unit_value_as_published cv_* source_type is_outlier underlying_nid /// 
	sampling_type recall_type recall_type_value input_type sample_size cases design_effect site_memo case_name /// 
	case_diagnostics response_rate note_SR note_modeler data_sheet_file_path parent_id case_name lit 

	keep `variables'
	drop cv_loqual cv_parental_report cv_child_16_17 cv_child_18 cv_child_18plus cv_notviostudy1 cv_notviostudy
	//rename cv_contact cv_contact_csa 
	rename cv_school cv_students
	rename cv_anym_quest cv_questionnaire
	rename cv_child_over_15 cv_recall_over_age_15
	rename cv_child_under_15 cv_recall_under_age_15
	rename cv_noncontact cv_noncontact_csa
	gen cv_subnational = 1 if location_name != "" & !regexm(location_name, "Peru|Uganda|United States|United Kingdom|Spain|Czech Republic|Canada|Belize|Argentina|Costa Rica|Nigeria|Sri Lanka|Kazakhstan|Uruguay|New Zealand|Nicaragua")
	replace cv_subnational = 0 if cv_subnational != 1 
	rename cv_questionnaire cv_questionaire
	drop cv_nointrain

	order `variables'
	
// Validation checks
	drop if mean == . | (upper == . & lower == . & effective_sample_size == . & standard_error == .) // Need mean and some variance metric
	drop if mean < lower & lower != .
	drop if upper < mean 
	drop if mean > 1

	//destring location_id, replace

// Save compiled dataset
	
	export excel "`outdir'/gbd2015_abuse_csa_revised.xlsx", sheet("Data") sheetreplace firstrow(variables)


// Save DisMod outputs
	
	// CSA IN FEMALES

	preserve 
	keep if modelable_entity_id == 3054
	//keep if nid == 239733 // just adding Turkey source, lalexan1 2/17/16
	//keep if lit == "1"  // just adding literature sources for GBD 2015, lalexan1 2/10/16

	tempfile girls 
	save `girls', replace

	export excel "`dismod_dir_female'/gbd2015_abuse_csa_female_$S_DATE.xlsx", sheet("extraction") firstrow(variables) replace


	// CSA IN MALES

	restore 
	keep if modelable_entity_id == 3053
	//keep if lit == "1" // just adding literature sources for GBD 2015, lalexan1 2/10/16

	export excel "`dismod_dir_male'/gbd2015_abuse_csa_male_$S_DATE.xlsx", sheet("extraction") firstrow(variables) replace


	//	gen cv_not_represent = 1 if representative_name == "Representative for subnational location only" & (location_name != "Karnataka, Rural" & location_name != "Karnataka, Urban" & location_name != "Delhi, Urban")  
	// replace cv_not_represent = 0 if cv_not_represent != 1
