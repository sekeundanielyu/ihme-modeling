import excel "strPath/chagas_input_datafile.xlsx", clear sheet("extraction") firstrow

egen total = sum(cases)
egen mild.cases = sum(cases) if nhya==2
egen moderate.cases = sum(cases) if nhya==3
egen severe.cases = sum(cases) if nhya==4

collapse max total mild.cases moderate.cases severe.cases

gen mild = mild.cases/total
gen moderate = moderate.cases/total
gen severe = severe.cases/total

save "strPath/chagas_splits.dta", replace
