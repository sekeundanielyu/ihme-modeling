  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }

local inputDir `j'/WORK/04_epi/02_models/01_code/06_custom/ntd_yellowfever/inputs 
  
import delimited `inputDir'/caseFatality.csv, clear

gen mean = numerator / denominator
gen lower = .
gen upper = .

forvalues i = 1/`=_N' {
  local n = numerator in `i'
  local d = denominator in `i'
  cii `d' `n', wilson
  replace upper = `r(ub)' in `i'
  replace lower = `r(lb)' in `i'
}

metan mean lower upper, random nograph

local mu    = `r(ES)'
local sigma = `r(seES)'

generate alphaCf = `mu' * (`mu' - `mu'^2 - `sigma'^2) / `sigma'^2 
generate betaCf  = alpha * (1 - `mu') / `mu'

keep in 1
keep alphaCf betaCf

save `inputDir'/caseFatalityAB.dta, replace
