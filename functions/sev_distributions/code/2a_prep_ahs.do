// INPUT: RAW NESARC DATA IN TWO WAVES
// OUTPUT: CLEANED AS ON DATASET WITH CONDITION INDICATORS, IDS, DEMOGRAPHIC INFO, AND SF12 SCORES.


// Bring in wave 1
use "$DATADIR/2_ahs/slim MHS Aus97 12 mnth diagnoses added.dta", clear

rename	c1a		Iresp_asthma
rename	c2		Iuri // Upper resp
rename	c3		Ianaemia
rename	c4		Iblood_press
rename	c5		Iheart_troub
rename	c6		Iarthritis
rename	c7		Ikidney_dis
rename	c8		Idiabetes
rename	c9		Icancer
rename	c10		Iulcer
rename	c11		Iliver_gallbladder
rename	c12		Ihernia_rupture

rename	danx12	Imental_anxiety12
rename	ddepa12	Imental_unipolar_mdd__mdd_mild12
rename	ddepb12	Imental_unipolar_mdd__mdd_mod12
rename	ddepc12	Imental_unipolar_mdd__mdd_sev12
rename	ddys12	Imental_unipolar_dys12
rename	dalcd12	Imental_alcohol12
rename	ddrgd12	Imental_drug_other12

rename	danx1	Imental_anxiety1
rename	ddepa1	Imental_unipolar_mdd__mdd_mild1
rename	ddepb1	Imental_unipolar_mdd__mdd_mod1
rename	ddepc1	Imental_unipolar_mdd__mdd_sev1
rename	ddys1	Imental_unipolar_dys1
rename	dalcd1	Imental_alcohol1
rename	ddrgd1	Imental_drug_other1

// Get "other mental" exclusive of affective and substance use disorders
recode dment12 (2=1) (1=0), gen(any_mental)
recode daff12 (2=1) (1=0), gen(any_affective)
recode dsubs12 (2=1) (1=0), gen(any_substance)

foreach var of varlist I* {
	recode `var' 0=0 1=0 5=1 2=1
}

gen Imental_other12 = 1 if any_mental==1 & any_affective==0 & any_substance==0
replace Imental_other12 = 0 if Imental_other12==.

egen Imental_unipolar_mdd12 = rowtotal(Imental_unipolar_mdd*12)
replace Imental_unipolar_mdd12 = 1 if Imental_unipolar_mdd12 > 1

egen Imental_unipolar_mdd1 = rowtotal(Imental_unipolar_mdd*1)
replace Imental_unipolar_mdd1 = 1 if Imental_unipolar_mdd1 > 1

rename		Imental_unipolar_mdd__mdd_mild12    Xmental_unipolar_mdd__mdd_mild12
rename		Imental_unipolar_mdd__mdd_mod12     Xmental_unipolar_mdd__mdd_mod12
rename		Imental_unipolar_mdd__mdd_sev12   Xmental_unipolar_mdd__mdd_sev12

rename		Imental_unipolar_mdd__mdd_mild1    Xmental_unipolar_mdd__mdd_mild1
rename		Imental_unipolar_mdd__mdd_mod1     Xmental_unipolar_mdd__mdd_mod1
rename		Imental_unipolar_mdd__mdd_sev1   Xmental_unipolar_mdd__mdd_sev1

// make reference category healthy
gen I_NONE = 0

// age dummies
rename age _age
decode _age, gen(age)
replace age = substr(age,1,2)
destring age, replace
drop if age == 18

rename a1 sex

// Crosswalk SF to DW
gen composite = pcs + mcs
gen key = _n

rename composite predict

append using "$SAVE_DIR/1_crosswalk_data.dta"
replace key = -999 if key == .
save "$SAVE_DIR/2a_ahs_prepped_to_crosswalk.dta", replace

keep sf dw key predict
saveold "$SAVE_DIR/2a_ahs_crosswalk_key.dta", replace

// END OF DO FILE
