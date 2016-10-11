capture program drop severitysplit
program define severitysplit

	syntax anything(name=splits)

	tokenize "`splits'"
	local count = 1
	while "`1'"!="" {
		local state`count' "`1'"
		local state_list `state_list' `state`count''

		local pr_`state`count'' = `2'
		local se_`state`count'' = `3'

		macro shift 3
		local ++count
	}

	macro dir

	// * APPLY THE SEVERITY SPLITS *
	foreach state of local state_list {
		local mu = `pr_`state''
		local sigma = `se_`state''

		local alpha`state' = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2
		local beta`state'  = `alpha`state'' * (1 - `mu') / `mu'
		generate `state'Temp = .
	}

	forvalues i = 0 / 999 {
		foreach state of local state_list {
			quietly replace `state'Temp = rbeta(`alpha`state'', `beta`state'')
		}
		egen correction = rowtotal(*Temp)
		foreach state of local state_list {
			quietly generate `state'`i' = `state'Temp / correction
		}
		drop correction
	}


end
