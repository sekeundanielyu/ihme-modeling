
// PURPOSE: Sort a dataset by n-code


cap program drop sort_by_ncode
program define sort_by_ncode
	version 12
	syntax varname [, OTHER_sort(varlist)]
	
	quietly {
	gen sort_tmp = subinstr(`varlist',"N","",1)
	destring sort_tmp, replace
	sort sort_tmp `other_sort'
	drop sort_tmp
	}
	
end
