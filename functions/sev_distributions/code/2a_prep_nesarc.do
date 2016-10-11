// INPUT: RAW NESARC DATA IN TWO WAVES
// OUTPUT: CLEANED AS ON DATASET WITH CONDITION INDICATORS, IDS, DEMOGRAPHIC INFO, AND SF12 SCORES.


// Bring in wave 1
use "$DATADIR/2_nesarc/wave1/2001_Nesarc.dta", clear

// rename some variables
rename IDNUM id
rename SEX sex
rename NBPCS pcs
rename NBMCS mcs
recode AGE 98=., gen(age)

// create age bands
gen age_gr = .
forvalues i = 15(5)80 {
	replace age_gr = `i' if age >= `i' & age <= (`i' + 4)
}
replace age_gr = 80 if age >= 80
replace age_gr = . if age == .

// average daily ethonol consumed
gen avg_oz_ethonol_daily = ETOTLCA2

// all for withing the last 12 months, lifetime is possible in this survey too. I = Disease, R = Risk
gen R_mental_alcohol = 0
replace R_mental_alcohol = 1 if ALCABDEP12DX == 2 | ALCABDEP12DX == 3
gen R_alc_abuse = 0
replace R_alc_abuse = 1 if ALCABDEP12DX == 1 | ALCABDEP12DX == 2

// other comos, last twelve months (non-confirmed by dr)
rename PANDX12 A_panic // py no agor
rename APANDX12 A_panic3 // py w agor
rename GPANDX12 A_agor  // py  agor
rename SOCPDX12 A_socialphobia1 // py
rename SPHOBDX12 A_spec_phobia
rename GENAXDX12 A_gen_anxiety
egen mental_anxiety = rowtotal(A_*)
replace mental_anxiety = 1 if mental_anxiety > 1

// Recode "other mental"
rename ANTISOCDX2 M_OTHER_antisoc
rename AVOIDPDX2 M_OTHER_avoid
rename DEPPDDX2 M_OTHER_depend
rename OBCOMDX2 M_OTHER_ocpd
rename PARADX2 M_OTHER_paranoid
rename SCHIZDX2 M_OTHER_schizo
rename HISTDX2 M_OTHER_histr

egen any_other_mental = rowtotal(M_OTHER*)
replace any_other_mental = 1 if any_other_mental > 0

// recode S13Q5 1/98=1 99=., gen(I_Injury)
recode S13Q6A1 2=0 9=., gen(I_arteriosclerosis)
recode S13Q6A2 2=0 9=., gen(I_hypertension)
recode S13Q6A3 2=0 9=., gen(I_cirrhosis)
recode S13Q6A4 2=0 9=., gen(I_otherliver)
recode S13Q6A5 2=0 9=., gen(I_anginapectoris)
recode S13Q6A6 2=0 9=., gen(I_tachycardia)
recode S13Q6A7 2=0 9=., gen(R_cvd_ihd)
recode S13Q6A8 2=0 9=., gen(I_otherheart)
recode S13Q6A9 2=0 9=., gen(I_stomach_ulcer)
recode S13Q6A10 2=0 9=.,gen(I_gastritis)
recode S13Q6A11 2=0 9=.,gen(I_arthritis)
recode S13Q7C 2=0 .=0, 	gen(I_preg_complications)
recode S13Q6D 2=0 9=., 	gen(I_diag_schizophrenia)

rename MAJORDEP12 MD_1
egen mental_unipolar_mdd = rowtotal(MD_*)
replace mental_unipolar_mdd = 1 if mental_unipolar_mdd > 1

rename DYSDX12 D_1
egen mental_unipolar_dys = rowtotal(D_*)
replace mental_unipolar_dys = 1 if mental_unipolar_dys > 1

rename NMANDX12 M_1
egen Mania = rowtotal(M_*)
replace Mania = 1 if Mania > 1

rename NHYPO12DX H_1
egen Hypomania = rowtotal(H_*)
replace Hypomania = 1 if Hypomania > 1

egen Mood = rowtotal(mental_unipolar_mdd mental_unipolar_dys Mania Hypo)
replace Mood = 1 if Mood > 1

egen any_affective = rowtotal(Mood mental_anxiety)
replace any_affective = 1 if any_affective > 0

// other abuses/dependencies - last 12 mo
rename TAB12MDX R_nicotine_dep
recode STIM12ABDEP 2/3=1, gen(R_mental_drug_amphet)
recode PAN12ABDEP 2/3=1, gen(R_mental_drug_opioids)
recode SED12ABDEP 2/3=1, gen(R_sedative_a_d)
recode TRAN12ABDEP 2/3=1, gen(R_tranquilizers_a_d)
recode COC12ABDEP 2/3=1, gen(R_mental_drug_cocaine)
recode SOL12ABDEP 2/3=1, gen(R_inhalant_a_d)
recode HAL12ABDEP 2/3=1, gen(R_hallucinogen_a_d)
recode MAR12ABDEP 2/3=1, gen(R_mental_drug_cannabis)
recode HER12ABDEP 2/3=1, gen(R_heroin_a_d)

egen any_substance = rowtotal(R_mental_drug_amphet R_mental_drug_opioids R_sedative_a_d R_tranquilizers_a_d R_mental_drug_cocaine R_inhalant_a_d R_hallucinogen_a_d R_mental_drug_cannabis R_mental_alcohol R_heroin_a_d R_alc_abuse)
replace any_substance = 1 if any_substance > 0

gen mental_other = 1 if any_other_mental==1 & any_substance==0 & any_affective==0
replace mental_other = 0 if mental_other==.

// keep needed variables and save
gen wave = 1
keep age_gr I_* mental_anxiety mental_unipolar_mdd mental_unipolar_dys mental_other Mania Hypomania R_* id sex wave mcs pcs PSU WEIGHT

tempfile w1
save `w1',replace

// Clean wave 2 as well -- naming consistent with Wave 1
use "$DATADIR/2_nesarc/wave2/nesarcw2.dta", clear

// uppercase all so easier to clean
foreach var of varlist* {
	local newname = upper("`var'")
	cap rename `var' `newname'
}

// rename some variables
rename IDNUM id
rename W2SEX sex
rename W2NBPCS pcs
rename W2NBMCS mcs
recode W2AGE 98=., gen(age)

// age
gen age_gr = .
forvalues i = 20(5)80 {
	replace age_gr = `i' if age >= `i' & age <= (`i' + 4)
}
replace age_gr = 80 if age >= 80
replace age_gr = . if age == .

// drop if age falls out of evaluation
drop if age_gr == .


gen R_mental_alcohol = 0
replace R_mental_alcohol = 1 if W2AAD12 == 2 | W2AAD12 == 3
gen R_alc_abuse = 0
replace R_alc_abuse = 1 if W2AAD12 == 1 | W2AAD12 == 2

// other comos, last twelve months (non-confirmed by dr) - Need to include any cases in past year - incidence and prevalence (new and chronic cases), in data as PY, SLI, LIFETIME, I, R, and C
rename PANDX12 A_panic // py without agoraphobia  ...  Need a combination of anyone with a 12 mo diagnosis of *any* of these anxiety categories (check if the file also has OCD or PTSD)
rename PANADX12 A_panic4 // PY with agor.
rename AGORALIFEW12 A_agor3 // lifetime agor wo panic
rename SOCDX12 A_socialphobia // py
rename SPEC12 A_spec_phobia // py
rename GENDX12 A_gen_anxiety // py
egen mental_anxiety = rowtotal(A_*)
replace mental_anxiety = 1 if mental_anxiety > 1

// Recode "other mental"
rename ANTISOCW12 M_OTHER_antisoc
rename SKPDX M_OTHER_schizo
rename BPDDX M_OTHER_border
rename NARCDX M_OTHER_narc

egen any_other_mental = rowtotal(M_OTHER*)
replace any_other_mental = 1 if any_other_mental > 0

// recode S13Q4 1/98=1 99=., gen(I_Injury)  ....  see codings above
recode W2S14Q15A1 2=0 9=., gen(I_arteriosclerosis)
recode W2S14Q15A2 2=0 9=., gen(I_hypertension)
recode W2S14Q15A4 2=0 9=., gen(I_cirrhosis)
recode W2S14Q15A5 2=0 9=., gen(I_otherliver)
recode W2S14Q15A6 2=0 9=., gen(I_anginapectoris)
recode W2S14Q15A7 2=0 9=., gen(I_tachycardia)
recode W2S14Q15A8 2=0 9=., gen(R_cvd_ihd)
recode W2S14Q15A10 2=0 9=., gen(I_otherheart)
recode W2S14Q15A11 2=0 9=., gen(I_stomach_ulcer)
recode W2S14Q15A15 2=0 9=., gen(I_gastritis)
recode W2S14Q15A16 2=0 9=., gen(I_arthritis)
recode W2S14Q18C 2=0 .=0, 		gen(I_preg_complications)
recode W2S14Q16A 2=0 9=., 		gen(I_diag_schizophrenia)

rename DEP12ROBSI MD_py
egen mental_unipolar_mdd = rowtotal(MD_*)
replace mental_unipolar_mdd = 1 if mental_unipolar_mdd > 1

rename DYSROSI12 D_py
egen mental_unipolar_dys = rowtotal(D_*)
replace mental_unipolar_dys = 1 if mental_unipolar_dys > 1

rename MAN12 M_py
egen Mania = rowtotal(M_*)
replace Mania = 1 if Mania > 1

rename HYPO12 H_py
egen Hypomania = rowtotal(H_*)
replace Hypomania = 1 if Hypomania > 1

egen Mood = rowtotal(mental_unipolar_mdd mental_unipolar_dys Mania Hypo)
replace Mood = 1 if Mood > 1

egen any_affective = rowtotal(Mood mental_anxiety)
replace any_affective = 1 if any_affective > 0

// other abuses/dependencies - last 12 mo
rename CURTABDEP R_nicotine_dep
recode STABDEP12 2/3=1, gen(R_mental_drug_amphet)
recode PAABDEP12 2/3=1, gen(R_mental_drug_opioids)
recode SEABDEP12 2/3=1, gen(R_sedative_a_d)
recode TRABDEP12 2/3=1, gen(R_tranquilizers_a_d)
recode COABDEP12 2/3=1, gen(R_mental_drug_cocaine)
recode SOABDEP12 2/3=1, gen(R_inhalant_a_d)
recode HAABDEP12 2/3=1, gen(R_hallucinogen_a_d)
recode MAABDEP12 2/3=1, gen(R_mental_drug_cannabis)
recode HEABDEP12 2/3=1, gen(R_heroin_a_d)

egen any_substance = rowtotal(R_mental_drug_amphet R_mental_drug_opioids R_sedative_a_d R_tranquilizers_a_d R_mental_drug_cocaine R_inhalant_a_d R_hallucinogen_a_d R_mental_drug_cannabis R_mental_alcohol R_heroin_a_d R_alc_abuse)
replace any_substance = 1 if any_substance > 0

gen mental_other = 1 if any_other_mental==1 & any_substance==0 & any_affective==0
replace mental_other = 0 if mental_other==.

// keep needed variables
gen wave = 2
rename W2PSU PSU
rename W2WEIGHT WEIGHT
keep age_gr I_* mental_anxiety mental_unipolar_mdd mental_unipolar_dys Mania Hypomania R_* id sex wave mcs pcs

// append on Wave 1 to make one dataset
append using `w1'


// health status -- create a composite SF12 score to be mapped to DW
gen composite = mcs+pcs
replace composit = . if composit == .


gen key = _n
replace composite = . if composite == 198

rename composite predict


// make drug one category
egen drug_a_d = rowtotal(R_heroin_a_d R_mental_drug_cannabis R_hallucinogen_a_d R_inhalant_a_d R_mental_drug_cocaine R_tranquilizers_a_d R_sedative_a_d R_mental_drug_opioids R_mental_drug_amphet)

// combine opiid and herion
replace R_mental_drug_opioids = 1 if R_heroin == 1
rename R_heroin X_heroin

//  do not include these two.
rename I_hypertension  X_hypertension
rename  I_tachycardia  X_tachycardia
rename R_alc_a	X_alc_a


// Save data in order to map to disability weights in next step
append using "$SAVE_DIR/1_crosswalk_data.dta"
replace key = -999 if key == .
save "$SAVE_DIR/2a_nesarc_prepped_to_crosswalk.dta", replace

keep sf dw key predict
saveold "$SAVE_DIR/2a_nesarc_crosswalk_key.dta", replace

// END OF DO FILE
