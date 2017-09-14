*** BOILERPLATE ***
	clear all
	set more off
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "FILEPATH"
		set odbcmgr unixodbc
		}
	else if c(os) == "Windows" {
		global prefix "FILEPATH"
		}
	
*** LOAD FUNCTIONS ***

	adopath + FILEPATH  
	adopath + FILEPATH/stata
	
	
*** GET LOCATION METADATA ***	
	get_location_metadata, location_set_id(35) clear
	keep location_id ihme_loc_id 
	tempfile locMeta
	save `locMeta'


	
*** GET GEOGRAPHIC RESTRICTIONS ***	
	import delimited using "FILEPATH/leish_c_cc.csv", clear
	drop cause_id 
	drop if year_id<1980
	tempfile gr
	save `gr', replace	
	
	
*** GET & PROCESS INCIDENCE DATA ***
	get_epi_data, bundle_id(54) clear
	keep if measure=="incidence"
	
	generate caseTemp = mean * effective_sample_size
	assert !missing(effective_sample_size)
	assert !missing(mean)
	assert !missing(caseTemp)
	assert abs(cases - caseTemp)<=1 if !missing(cases)
	replace cases = caseTemp if missing(cases)
	assert !missing(cases)
	
	drop ihme_loc_id
	merge m:1 location_id using `locationMeta', assert(2 3) keep(3) nogenerate
	generate countryIso = substr(ihme_loc_id, 1, 3)
	generate iso3 = substr(ihme_loc_id, 1, 3)


	* dropping zero prior data (USERNAME), and duplicative sources
	drop if is_outlier==1 | extractor=="USERNAME" | USERNAME==1 | strmatch(source_type, "Facility*") | inlist(nid, 118116, 121993, 122008, 122011, 150217, 150219, 150230, 220684, 220701, 220735, 220753, 220755, 220767, 220821, 220829, 221048, 221052)
	drop if nid==117901
	drop if nid==150228 & year_start==2000
	drop if ihme_loc_id=="BRA" & nid==150228
	drop if ihme_loc_id=="BRA_4752" & nid==220552 & (year_start!=year_end | year_start>=2007)
	drop if nid==118119 & ihme_loc_id=="IRQ" & year_start>1988
	drop if nid==118119 & ihme_loc_id=="JOR"
	drop if nid==220713 & ihme_loc_id=="JOR"
	drop if nid==118119 & ihme_loc_id=="OHM" & year_start==1994
	drop if nid==118110 & ihme_loc_id=="PRY" & year_start==1982
	drop if inlist(nid, 118110, 150233) & ihme_loc_id=="PAN" 
	drop if inlist(nid, 150224, 150227) & inlist(ihme_loc_id, "TUR", "VEN")
	drop if inlist(nid, 150224) & ihme_loc_id=="SYR" & year_end>=19994
	drop if inlist(nid, 150227) & ihme_loc_id=="SYR"
	drop if case_name=="vl + cl data"
	

	generate ageCat = string(age_start) + "-" + string(age_end)


	bysort location_id year_start: egen anyWhoIrn = max(nid==149776)
	drop if nid!=149776 & anyWhoIrn==1 & ihme_loc_id=="IRN"

	bysort location_id year_start nid sex: egen minAge = min(age_start)
	bysort location_id year_start nid sex: egen maxAge = max(age_end)

	generate isAllAge = (age_start==0 & age_end>=99) | (age_start<=1 & minAge==age_start & age_end>=80 & maxAge==age_end) | (location_id==566 & age_start<10 & age_end>70)
	drop minAge maxAge

	bysort location_id year_start nid: egen anyAllAge = max(isAllAge)
	bysort location_id year_start ageCat nid: egen anyMale = max(sex=="Male")
	bysort location_id year_start ageCat nid: egen anyFemale = max(sex=="Female")
	bysort location_id year_start ageCat nid: egen anyBoth = max(sex=="Both")

	generate whatSex = "1" if anyMale==1
	replace  whatSex = whatSex + "2" if anyFemale==1
	replace  whatSex = whatSex + "3" if anyBoth==1


	order bundle_id seq field_citation_value source_type nid underlying_nid location_id location_name ihme_loc_id year_start year_end sex age_start age_end measure mean lower upper standard_error cases effective_sample_size sample_size


	bysort location_id year_start nid: egen anyAllAgeSexByNid = max(isAllAge & sex=="Both")
	drop if anyAllAgeSexByNid==1 & (isAllAge ==0 | sex!="Both")

	preserve
	keep if isAllAge==1 & sex=="Both"
	gen file = "allAgeBothSex"
	tempfile allAgeBothSex
	save `allAgeBothSex'

	
	restore 
	preserve
	keep if isAllAge==1 & whatSex=="12"
	collapse (sum) cases *sample_size, by(location_id location_name ihme_loc_id year_* nid field_citation_value source_type extractor cv_*)
	gen file = "allAgeSepSex"
	tempfile allAgeSepSex
	save `allAgeSepSex'
	
	
	restore 
	preserve
	drop if (isAllAge==1 & sex=="Both") | (isAllAge==1 & whatSex=="12") 
	keep if strmatch(ihme_loc_id, "BRA*") & strmatch(field_citation_value, "Ministry of Health (Brazil)*")
	collapse (sum) cases, by(location_id location_name ihme_loc_id year_* nid field_citation_value source_type extractor cv_*)
	
	levelsof year_start, local(years) clean
	levelsof location_id, local(locations) clean
	
	tempfile sinan
	save `sinan'
	
	get_population, year_id(`years') location_id(`locations') age_group_id(22) sex_id(3) clear
	drop age sex process
	rename year_id year_start
	
	merge 1:1 location_id year_start using `sinan', assert(1 3) keep(3) nogenerate
	rename population sample_size
	
	gen file = "sinan"
	save `sinan', replace



	restore
	drop if (isAllAge==1 & sex=="Both") | (isAllAge==1 & whatSex=="12") 
	drop if strmatch(ihme_loc_id, "BRA*") & strmatch(field_citation_value, "Ministry of Health (Brazil)*")

	bysort location_id year_start nid sex: egen minAge = min(age_start)
	bysort location_id year_start nid sex: egen maxAge = max(age_end)
	bysort location_id year_start nid sex (age_start): gen ageGap = age_start - age_end[_n-1]
	bysort location_id year_start nid sex: egen maxAgeGap = max(ageGap)

	gen complete = (minAge<=1 & maxAge>=70 & inrange(ageGap, 0 , 1))
	keep if complete==1

	collapse (sum) cases, by(location_id location_name ihme_loc_id year_* nid field_citation_value source_type extractor cv_*)

	levelsof year_start, local(years) clean
	levelsof location_id, local(locations) clean
	
	tempfile ageSpecific
	save `ageSpecific'
	
	get_population, year_id(`years') location_id(`locations') age_group_id(22) sex_id(3) clear
	drop age sex process
	rename year_id year_start
	
	merge 1:m location_id year_start using `ageSpecific', assert(1 3) keep(3) nogenerate
	rename population sample_size
	
	gen file = "ageSpecific"
	save `ageSpecific', replace
	
	
	append using `allAgeBothSex' `allAgeSepSex' `sinan' FILEPATH/whoClClean.dta  FILEPATH/cl_final_merge_6_5_17.dta FILEPATH/clMex.dta
	
	replace bestSource = 0 if missing(bestSource)

	gen year_id = floor((year_start + year_end) / 2)
	replace year_id = 1980 if year_id<1980 & year_end>=1980

	bysort location_id year_id: egen anyBest = max(bestSource)
	drop if bestSource==0 & anyBest==1

	bysort location_id year_id: egen anyUpdated = max(source=="updated WHO")
	drop if anyUpdate==1 & source!="updated WHO"
	
	bysort location_id year_id: gen count = _N
	bysort location_id year_id: egen anyAllAgeBothSex = max(file=="allAgeBothSex")
	drop if count>1 & anyAllAgeBothSex==1 & file!="allAgeBothSex"
	
	
	keep nid field location_id location_name ihme_loc_id year_id mean lower upper cases sample_size nid is_outlier bestSource file count
	order nid field location_id location_name ihme_loc_id year_id mean lower upper cases sample_size nid is_outlier bestSource file count

	sort ihme_loc_id year_id 
	generate iso3 = substr(ihme_loc_id, 1, 3)

	

*** MERGE INCIDENCE & UNDERREPORTING DATA ***	
	merge m:1 iso3 using "FILEPATH/cl_underreporting.dta", assert(2 3) keep(3) nogenerate
	keep location_id location_name ihme_loc_id iso3 year_id mean lower upper cases sample_size nid uf_* is_outlier

	
*** ADJUST INCIDENCE DATA FOR UNDERREPORTING ***	
	assert !missing(cases)
	assert !missing(sample_size)
	replace mean = cases / sample_size if missing(mean)
	assert !missing(mean)
	
	generate betaCases  = cases 
	generate betaSample = sample_size
	
	replace  betaCases  = mean * 0.999e+8 if betaSample>0.999e+8
	replace  betaSample = 0.999e+8 if betaSample>0.999e+8
	replace  betaCases  = betaCases + 1.1e-4
	
	egen ufMean = rowmean(uf_*)

	forvalues i = 0 / 999 {
		quietly {
			generate gammaA = rgamma(betaCases, 1)
			generate gammaB = rgamma((betaSample - betaCases), 1)
			
			generate inc_`i' = uf_`i' * gammaA / (gammaA + gammaB) 
			
			gen inc10k_`i' = inc_`i' * 10000
			
			noisily assert !missing(inc_`i') & inc_`i'>=0
			drop gammaA gammaB
			
			}
		
		di "." _continue
		}
	
	gen data = mean * ufMean
	egen variance = rowsd(inc_*)
	replace variance = variance^2
	
	gen data10k = mean * ufMean * 10000
	egen variance10k = rowsd(inc10k_*)
	replace variance10k = variance10k^2
	
	keep year_id location_id ihme_loc_id nid data* sample_size variance* is_outlier
		
		

*** MERGE IN GEOGRAPHIC RESTRICTIONS ***	
	merge m:1 location_id year_id using `gr', gen(grMerge)

	gen endemic = grMerge==1	
	replace endemic=0 if strmatch(ihme_loc_id, "GBR*")
	replace endemic=1 if inlist(location_id, 43874, 43875, 43882, 43883, 43884, 43885, 43886, 43890, 43899, 43900, 43904, 43905, 43906, 43910, 43911, 43918, 43919, 43920, 43921, 43922, 43926, 43935, 43936, 43940, 43941, 43942)

	

	
	keep if !missing(data)
	keep year_id location_id data* sample_size variance* nid  

	replace nid = 283125 if missing(nid)
	
	generate me_name = "ntd_cl"
	generate age_group_id = 22
	generate sex_id = 3

	drop data variance
	rename *10k *
	
	gen nonZeroVar = variance if data>0
	bysort location_id: egen meanNzVar = mean(nonZeroVar)
	assert (meanNzVar*0.1)>=variance if !missing(meanNzVar) & data==0
	replace variance =  (meanNzVar*0.1) if !missing(meanNzVar) & (meanNzVar*0.1)>=variance
	drop nonZeroVar meanNzVar
	
	export delimited using FILEPATH/clModellingData_1.csv, replace



