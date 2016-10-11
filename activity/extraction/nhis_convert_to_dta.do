/* Convert raw BRFSS XPTs to DTA format */

local outdir = "J:/WORK/05_risk/risks/activity/data/exp/raw/brfss"

forvalues year = 1984(1)2012 {

	local dir_name = "J:/DATA/USA/BRFSS/`year'"

	local xpt_files : dir "J:/DATA/USA/BRFSS/`year'" files "usa_brfss_`year'_y*.xpt"
	local num_xpt_files : word count `xpt_files'
	
	if `num_xpt_files' == 1 {
		! "C:/Apps/StatTransfer11-64/st.exe" "`dir_name'/`xpt_files'" "`outdir'/brfss_`year'.dta"
	}
	
}
