local direc = "`1'"
run "/home/j/WORK/10_gbd/00_library/functions/get_demographics.ado"
get_demographics , gbd_team(cod) make_template clear
keep l*
if `direc' == "" { 
save "locations.dta", replace
}
else {
save "`direc'/locations.dta", replace
}
