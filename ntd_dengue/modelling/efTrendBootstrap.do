clear

local yearC 2010

set obs `=2015-1979'
generate year_id = _n + 1979 
gen yearC = `yearC' - year_id
tempfile bsPred
save `bsPred'

use "J:\WORK\04_epi\02_models\01_code\06_custom\dengue\data\empiricalExpansionFactors_working.dta", clear


keep if modelled==0  & !missing(efTotal) & efN==0 & childrenonly==0
gen yearC = `yearC' - year_id


  
local i = 0
while `i'<1000 {
  quietly {
  preserve
  bsample, cluster(series)
  append using `bsPred'
  
  capture mepoisson efTotal yearC ||  series:
  
  noisily di as text "." _continue	
	
  generate ef_`i' =  exp(_b[yearC]*yearC)	

  
  keep if missing(efTotal)
  save `bsPred', replace
  restore
  local ++i
  }
  }
  
use `bsPred', clear
keep year* ef_*

foreach var of varlist ef_* {
  quietly replace `var' = 1 if year_id>2010
  }
  
egen efMean = rowmean(ef_*)
egen efLower = rowpctile(ef_*), p(2.5)
egen efUpper = rowpctile(ef_*), p(97.5)

twoway (rarea efLower efUpper year_id, fcolor(gs12) lcolor(gs12)) (line efMean year_id, lcolor(navy)), legend(off)

keep year_id ef_*
save J:\WORK\04_epi\02_models\01_code\06_custom\dengue\data\efInflatorDraws.dta, replace
