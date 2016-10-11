** Go through all the age splits and make them all even for maximum possible RR thing chris wants

clear 
set more off

	if (c(os)=="Unix") {
		** global arg gets passed in from the shell script and is parsed to get the individual arguments below
		global j "/home/j"
	} 
	if (c(os)=="Windows") { 
		global j "J:"
	}

	** 15 20 25 30 35 40 45 50 55 60 65 70 75 80
	
forvalues i = 15 (5) 80 {
	forvalues j = 1/2 {
		insheet using "/clustertmp//alcohol_temp/alc_age_frac_2013_`i'_`j'.csv", clear
		replace mean_pop = 1000
		foreach var of varlist draw* {
			replace `var' = 1/14
		}
		replace mean_frac = 1/14
		outsheet using "/clustertmp//alcohol_temp/alc_age_frac_2013_`i'_`j'.csv", comma replace
	}
}


