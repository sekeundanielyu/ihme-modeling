//Pull data from dismod and upload into COD database
clear all
set more off

adopath + "strPath/functions"

do strPath/functions/save_results.do
save_results, cause_id(500) description(afib custom CSMR 50129) in_dir("strPath/strUser/afib_csmr") in_rate(yes) mark_best(yes)

