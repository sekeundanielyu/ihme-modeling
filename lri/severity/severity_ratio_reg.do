// Estimates the ratio of severe/very-severe to moderate lower respiratory infections //
// Input data are from systematic review of scientific literature //

set seed 619003744
set more off

// LRI dataset //
import excel "J:\WORK\04_epi\01_database\02_data\lri\1258\03_review\01_download\me_1258_ts_2016_05_16__121431.xlsx", firstrow clear

gen keep = 0
bysort nid: replace keep = 1 if sum(cv_diag_severe)>0

keep if keep==1
keep if is_outlier==0
tempfile base
save `base' 

gen log_mean = log(mean)

// Collapse for analysis //
replace sample_size = mean*(1-mean)/standard_error^2 if nid == 108872

replace sample_size = mean*(1-mean)/standard_error^2 if sample_size== . 
preserve

drop if cv_diag_severe == 0
collapse (sum)mean (sum)cases (sum)sample_size (sum)standard_error, by(nid field_citation_value)
rename mean severe
rename standard_error error_severe
rename sample_size sample_severe
tempfile sev
save `sev'

restore
drop if cv_diag_severe== 1
collapse (sum)mean (sum)cases (sum)sample_size (sum)standard_error, by(nid field_citation_value)

merge m:m nid using `sev', keep(3) nogen

gen se_severe = sqrt(severe*(1-severe)/sample_severe)
gen se_non = sqrt(mean*(1-mean)/sample_size)

forval i = 1/1000 {
	gen sev_`i' = rnormal(severe, se_severe)
	gen non_`i' = rnormal(mean, se_non)
	gen ratio_`i' = sev_`i'/non_`i'
}
drop sev_* non_*
egen mean_ratio = rowmean(ratio*)
egen se_ratio = rowsd(ratio*)
drop ratio_*
gen ratio = severe/mean

sort field_citation_value
gen label = substr(field_citation_value, 1, strpos(field_citation_value, ",")-1)

metan mean_ratio se_ratio, label(namevar = label) random

// Get information about input data //
merge 1:m nid using `base', keep(3) 
duplicates tag nid age_start age_end, gen(dup)
drop if dup > 1
sort field_citation_value
br
