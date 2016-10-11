
*Purpose: For Guillain Barre, we only model nonfatal outcomes of surviving cases, since mortality only occurs in acute phase. 


*****************************************************************************************************
*****************************************************************************************************


//ADJUST FOR CASE FATALITY 
		
			import excel "J:\Project\GBD\CUSTOM_INPUT_DATABASE\Inputs_2015\imp_gbs_cfr_2015.xlsx", firstrow clear 


				gen survived = cases - deaths 
				metaprop survived cases, random lcols(location_name) title("GBS SR") // saving("$prefix/WORK/04_epi/01_database/02_data/imp_gbs/04_models/02_inputs/gbs_SR_metaanalysis", replace)
				local sr_pooled = `r(ES)'
				local sr_pooled_se = `r(seES)'


* local source marketscan 
foreach source in hospital marketscan {
	
//LOAD DATA
	cd ``source'_dir'
	import excel "``source'_data'.xlsx", firstrow clear  
	sum mean 
	
		di in red "adjusting standard error"
			//variance of mean*cfr 
			*var(X)var(Y)+var(X)E(Y)^2+var(Y)E(X)^2  
			gen var_mean = standard_error^2
			gen var_SR = `sr_pooled_se'^2
		sum standard_error
		gen variance = var_mean * var_SR + var_SR * mean^2 + var_mean * `sr_pooled'^2
		replace standard_error = sqrt(variance)
		sum standard_error

		di in red "adjusting for survival rate: pooled estimate  = `sr_pooled'"
		sum mean 
		replace mean = mean * `sr_pooled'
		sum mean 	
		drop var*
	}
	
	di in red "adjusting for survival rate: pooled estimate  = `sr_pooled'"
		replace cases = cases * `sr_pooled'


export excel "J:/WORK/04_epi/01_database/02_data/imp_gbs/2404/04_big_data/gbs_`source'_CFR_adjusted.xlsx", firstrow(var) sheet("extraction") replace

}







