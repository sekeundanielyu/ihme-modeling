// Gen draws version 2, cluster parallel



clear
clear matrix
cap restore, not
set more off
set memory 8000m
set seed 1234567

	if c(os) == "Windows" {
		global prefix ""
	}
	else {
		global prefix ""
	}
	
	local i `1'
	local temp_folder ""
	tempfile draws

	use "pre_split_`i'.dta", clear
	
	gen id = _n
	local nn = _N
	
	quietly forvalues j=1/`nn' {
		preserve
			keep if id==`j'
			mat bb=deaths_best[1]
			mat sds=sds[1]
			local iso=iso3[1]
			local yy=year[1]
			local ss=sex[1]
			local aa=age[1]
			local cc=cause[1]

			set seed 1234567
			drawnorm deaths, n(3000) mean(bb) sds(sds) clear
			keep if deaths>0
			set seed 1234567
			sample 1000, count
			count
			assert `r(N)' == 1000
			gen iso3="`iso'"
			gen year=`yy'
			gen sex=`ss'
			gen age=`aa'
			gen cause="`cc'"'
			gen sim=_n
			cap append using `draws'
			save `draws',replace
			restore
			noisily dis "`j' of `nn' sampling done"
	}
	
	use `draws', clear
	compress
	save "post_split_`i'.dta", replace
	
	