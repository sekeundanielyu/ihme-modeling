clear

if c(os) == "Unix" {
  local j "/home/j"
  set odbcmgr unixodbc
  }
else if c(os) == "Windows" {
  local j "J:"
  }

odbc load, exec("SELECT age_group_id, age_group_years_start AS age_start, age_group_years_end AS age_end FROM age_group WHERE is_aggregate = 0 and age_group_id < 22") dsn(shared) clear
egen age_mid = rowmean(age_start age_end)
expand 2, gen(sex_id)
replace sex_id = sex_id + 1
gen effective_sample_size = 1
tempfile ages
save `ages', replace  
  
import excel using "J:\WORK\04_epi\01_database\02_data\ntd_yellowfever\1509\03_review\01_download\me_1509_ts_2015_12_01__162015.xlsx", clear firstrow case(preserve)
generate sex_id = (sex=="Male") + (sex=="Female")*2 + (sex=="Both")*3
keep if age_start>0 | age_end<99 | sex_id<3
egen age_mid = rowmean(age_start age_end)
replace cases = effective_sample_size * mean if missing(cases)
egen group = group(location_id year_start year_end)
keep cases effective_sample_size sex_id age_mid group

append using `ages'

gen sexC = (-1 * (sex_id==1)) + ((sex_id==2))
replace group = 999 if missing(group)


capture drop ageS* sp
mkspline ageS = age_mid, cubic knots(0.01 1 10 40)
menbreg cases sexC ageS*, exp(effective_sample_size) || group:
predict ageSexCurve, fixedonly	
replace ageSexCurve = 0 if age_group_id==2

scatter ageSexCurve age_mid if group==999, by(sex_id)

keep if group==999
keep ageSexCurve age_group_id sex_id

save "J:\WORK\04_epi\02_models\01_code\06_custom\ntd_yellowfever\inputs\ageDistribution.dta", replace
