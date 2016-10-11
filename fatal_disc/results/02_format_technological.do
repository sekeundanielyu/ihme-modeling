** Purpose: format EMDAT technological disaster data, taking into account length of disaster

clear all
set more off
cap restore, not

** for saving purposes: 
local date = c(current_date)

if c(os)=="Windows" {
	global prefix=""
	}
if c(os)=="Unix" {
	global prefix=""
	}
	
// pdfstart.ado
cap do "pdfstart_Acrobat11.ado"
local acrobat_distiller_path "acrodist.exe"

do "get_location_metadata.ado"

local input_folder ""

// old GBD2013 folder
local oldpath ""



** dB setup
do "create_connection_string.ado"
create_connection_string, strConnection
local conn_string `r(conn_string)'

** location_set_version_id
local location_ver = 46

** prep country codes
	** Subnationals
	clear
	gen iso3 = ""
	tempfile codes_sub
	save `codes_sub', replace
	foreach sub in CHN GBR MEX IND BRA JPN SAU SWE USA KEN ZAF {
		if inlist("`sub'", "JPN") local admin = 4
		else if inlist("`sub'", "IND") local admin "4, 12"
		else local admin = 3
		odbc load, exec("SELECT location_id, location_ascii_name as location_name, region_name, ihme_loc_id FROM shared.location_hierarchy_history loc_hh JOIN shared.location USING (location_id) WHERE loc_hh.ihme_loc_id LIKE '`sub'%' AND loc_hh.location_type_id IN (`admin') AND loc_hh.location_set_version_id = `location_ver'") `conn_string' clear
		replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
		rename (location_name region_name ihme_loc_id) (countryname gbd_region iso3)
		if "`sub'" == "IND" {
			replace countryname = subinstr(countryname, "?", "a", .) if regexm(countryname, "Arun\?chal|Bih\?r|Gujar\?t|Hary\?na|Karn\?taka|Mah\?r\?shtra|Megh\?laya|N\?g\?land|R\?jasth\?n|N\?du")
			replace countryname = subinstr(countryname, "?", "i", .) if regexm(countryname, "Chhatt\?sgarh|Kashm\?r")
		}
		else if "`sub'" == "JPN" {
			replace countryname = subinstr(countryname, "?", "o", .)
			replace countryname = subinstr(countryname, "Ô", "O", .)
			replace countryname = proper(countryname)
		}
		append using `codes_sub'
		save `codes_sub', replace
	}
	
	drop if countryname == "Distrito Federal" & iso3 == "BRA"	// Drop to keep countryname unique. There are Distrito Federal in both Mexico and Brazil
	save `codes_sub', replace
	
	** Nationals
	odbc load, exec("SELECT location_id, location_name, region_name, ihme_loc_id, location_type_id FROM shared.location_hierarchy_history WHERE location_type_id IN (2,3,4,8,12) AND location_set_version_id = `location_ver'") `conn_string' clear
	replace ihme_loc_id = substr(ihme_loc_id, 1, 3)
	drop if regexm(location_name, "County") & regexm(region_name, "High-income North America")
	drop if location_id == 891
	rename (location_name region_name ihme_loc_id) (countryname gbd_region iso3)
	// Drop unnecessary codes
	drop if iso3 == "USA" & (location_type_id == 3 | location_type_id == 4)
	drop if location_type_id == 3 & inlist(iso3, "JPN", "BRA", "MEX", "IND")
	tempfile codes
	save `codes', replace
	
** subnational population weights
	use "population_gbd2015.dta", clear
		keep if sex == "both" & age_group_id == 22
		gen keep = 0
		foreach iso in BRA CHN GBR IND JPN KEN MEX SWE SAU USA ZAF {
			replace keep = 1 if regexm(ihme_loc_id, "`iso'")
		}
		replace keep = 0 if ihme_loc_id == "CHN_44533"
		drop if keep == 0
		drop sex* age* parent_id keep source location_id
		drop if length(ihme_loc_id)==3
		rename pop pop_
		// Drop India state, only use urban rural
			gen iso_length = length(ihme_loc_id)
			drop if regexm(ihme_loc_id, "IND_") & iso_length == 8
			drop iso_length
		// Drop England
			drop if ihme_loc_id == "GBR_4749"
		levelsof ihme_loc_id, local(ids) clean
		bysort ihme_loc_id : assert location_name == location_name[1]
		foreach id of local ids {
			levelsof location_name if ihme_loc_id == "`id'", local(`id'_name) clean
		}
		drop location_name
		reshape wide pop_, i(year) j(ihme_loc_id) string
		foreach iso in BRA CHN GBR IND JPN KEN MEX SWE SAU USA ZAF {
			lookfor pop_`iso'
			local varlist `r(varlist)'
			egen pop_`iso'_tot = rowtotal(pop_`iso'_*)
			foreach var of local varlist {
				local stub = subinstr("`var'", "pop_", "", 1)
				gen weight_`stub' = `var' / pop_`iso'_tot
			}
		}
		drop *tot pop_*
		reshape long weight_, i(year) j(ihme_loc_id) string
		drop if weight_ == .
		split ihme_loc_id, parse("_")
		rename ihme_loc_id1 iso3
		rename ihme_loc_id2 location_id
		rename weight_ weight
		drop if location_id == "tot"
		destring location_id, replace
		gen gbd_country_iso3 = iso3
		gen location_name = ""
		foreach id of local ids {
			replace location_name = "``id'_name'" if ihme_loc_id == "`id'"
		}
		
		rename year disyear
		expand 25
		gen type = ""
		bysort disyear location_id : gen indic = _n
			replace type = "Air" if indic == 1
			replace type = "Chemical spill" if indic == 2
			replace type = "Cold wave" if indic == 3
			replace type = "Collapse" if indic == 4
			replace type = "Drought" if indic == 5
			replace type = "Earthquake" if indic == 6
			replace type = "Explosion" if indic == 7
			replace type = "Famine" if indic == 8
			replace type = "Fire" if indic == 9
			replace type = "Flood" if indic == 10
			replace type = "Gas leak" if indic == 11
			replace type = "Heat wave" if indic == 12
			replace type = "Other" if indic == 13
			replace type = "Other Geophysical" if indic == 14
			replace type = "Other hydrological" if indic == 15
			replace type = "Poisoning" if indic == 16
			replace type = "Rail" if indic == 17
			replace type = "Road" if indic == 18
			replace type = "Volcanic activity" if indic == 19
			replace type = "Water" if indic == 20
			replace type = "Wildfire" if indic == 21
			replace type = "legal intervention" if indic == 22
			replace type = "storm" if indic == 23
			replace type = "terrorism" if indic == 24
			replace type = "war" if indic == 25
		drop indic
		isid disyear location_id type
		gen _merge = 1

		tempfile subnatl_popweight
		save `subnatl_popweight', replace
		
		
	// Find pop-weights to split India states by urbanicity
	get_location_metadata, location_set_id(35) clear
		keep if (location_type == "admin2" | location_type == "urbanicity") & regexm(ihme_loc_id, "IND_")
		keep parent_id location_id
		tempfile india_urbanicity
		save `india_urbanicity', replace
	
	use "population_gbd2015.dta", clear
		levelsof ihme_loc_id if regexm(ihme_loc_id, "IND_") & level == 5, local(inds) clean
		gen keep = 0
		foreach iso of local inds {
			qui replace keep = 1 if ihme_loc_id == "`iso'"
		}
		keep if keep == 1
		keep if sex == "both" & age_group_id == 22
		drop sex* age* parent_id keep source location_id location_name
		rename pop pop_
		split ihme_loc_id, parse("_")
		drop ihme_loc_id1
		rename ihme_loc_id2 location_id
		destring location_id, replace
		
		merge m:1 location_id using `india_urbanicity', assert(3) nogen
		bysort parent_id year : egen total = total(pop)
		gen weight = pop / total
		keep year weight location_id parent_id
		
		rename year disyear
		expand 25
		gen type = ""
		bysort disyear location_id : gen indic = _n
			replace type = "Air" if indic == 1
			replace type = "Chemical spill" if indic == 2
			replace type = "Cold wave" if indic == 3
			replace type = "Collapse" if indic == 4
			replace type = "Drought" if indic == 5
			replace type = "Earthquake" if indic == 6
			replace type = "Explosion" if indic == 7
			replace type = "Famine" if indic == 8
			replace type = "Fire" if indic == 9
			replace type = "Flood" if indic == 10
			replace type = "Gas leak" if indic == 11
			replace type = "Heat wave" if indic == 12
			replace type = "Other" if indic == 13
			replace type = "Other Geophysical" if indic == 14
			replace type = "Other hydrological" if indic == 15
			replace type = "Poisoning" if indic == 16
			replace type = "Rail" if indic == 17
			replace type = "Road" if indic == 18
			replace type = "Volcanic activity" if indic == 19
			replace type = "Water" if indic == 20
			replace type = "Wildfire" if indic == 21
			replace type = "legal intervention" if indic == 22
			replace type = "storm" if indic == 23
			replace type = "terrorism" if indic == 24
			replace type = "war" if indic == 25
		drop indic
		isid disyear location_id type
		save `india_urbanicity', replace
	
	// Get Indian state location_ids
	get_location_metadata, location_set_id(35) clear
		keep if location_type == "admin1" & regexm(ihme_loc_id, "IND_")
		keep location_id location_ascii_name
		rename location_ascii_name countryname
		tempfile india_states
		save `india_states', replace
	

** bring in 2015 Hajj Collapse
	import excel using "hajj_collapse_wiki.xlsx", clear firstrow
	replace cause = "Other" if cause == "Hajj Collapse"
	gen year = 2015
	
	rename iso3 countryname
	replace countryname = "Cote d'Ivoire" if countryname == "Ivory Coast"
	gen source = "Hajj Wiki"
	gen nid = 251829
	
	merge 1:1 countryname using `codes', keep(3) assert(2 3) nogen
	
	keep iso3 location_id year numkilled gbd_region cause source nid
	
	tempfile hajj_sup
	save `hajj_sup', replace


** bring in EMDAT data
	import delimited using "emdat_data_updated.csv", clear bindquote(strict)
		
	** initial formatting	
		keep if disaster_group_orig == "Technological"
		
		rename country_name country
		rename dis_type type
		rename dis_subtype subtype
		rename total_deaths numkilled
		rename start_date startdate
		rename end_date enddate
		
		
		** drop irrelevant variables
		drop v1 associated_dis* continent_orig disaster_group_orig insur_dam
		drop total_affected total_dam disaster_no

		replace type = proper(type)
		
		** if number killed is missing, make it equal to 0
		replace numkilled = 0 if numkilled== .
		
		** drop if number of deaths is less than 10
		drop if numkilled < 10
		
	** merge on iso3 codes
	rename country countryname
		
		replace countryname = trim(countryname)
		
		** need to first make some changes to country names so that they'll merge
		** drop the countries that no longer exist
		drop if inlist(countryname, "Azores", "Soviet Union", "Canary Is", "Czechoslovakia", "Germany Dem Rep", "Germany Fed Rep", "Serbia Montenegro", "Yugoslavia") | regexm(countryname, "Wallis")==1
		
		** some automated changes
		split countryname, parse( " (")
		split countryname2, parse( ")")
		replace countryname = countryname1+", "+ countryname21 if regexm(countryname2,"China")==1 & countryname1 != "Taiwan"
			replace countryname = countryname1 if countryname1 == "Taiwan"
			replace countryname = countryname21 if countryname1 == "Palestine" 
			replace countryname = countryname21+ " "+countryname1 if countryname21=="US"
			replace countryname = "British " + countryname1 if countryname21 == "UK"
		drop countryname1-countryname21
		
		replace countryname = subinstr(countryname, "Rep", "Republic",.)
			replace countryname = subinstr(countryname, " Republic", ", Republic of",.) if regexm(countryname,"Moldova")==1
		replace countryname = subinstr(countryname, " P ", " People's ",.)
			replace countryname = subinstr(countryname, " P ", " People's ",.) if regexm(countryname,"Korea Dem")==1
		replace countryname = subinstr(countryname, " Dem ", " Democratic ", .)
		replace countryname = subinstr(countryname, " Dem. ", " Democratic ", .)
		replace countryname = subinstr(countryname, " Is", " Islands",.)
			replace countryname = "Iran, Islamic Republic of" if countryname == "Iran Islandslam Republic"
			replace countryname = subinstr(countryname, "Islandsland", "Island",.)
		replace countryname = subinstr(countryname, "St ", "St. ",.)
		
		replace countryname = "The Bahamas" if countryname == "Bahamas"
		replace countryname = "Virgin Islands, British" if countryname == "British Virgin Islands"
		replace countryname = "Virgin Islands, U.S." if countryname == "US Virgin Islands"
		replace countryname = "Brunei" if countryname == "Brunei Darussalam"
		replace countryname = "Bosnia and Herzegovina" if countryname == "Bosnia-Hercegovenia"
		replace countryname = "Cape Verde" if countryname == "Cape Verde Islands"
		replace countryname = "China" if countryname == "China People's Republic"
		replace countryname = "Federated States of Micronesia" if countryname == "Micronesia, Federated States"
		replace countryname = "Germany, Former Democratic Republic" if countryname == "Germany Democratic Republic" 
		replace countryname = "Germany, Former Federal Republic" if countryname == "Germany Fed Republic"
		replace countryname = "Guinea-Bissau" if countryname == "Guinea Bissau"
		replace countryname = "Hong Kong Special Administrative Region of China" if countryname == "Hong Kong, China" | countryname == "Hong Kong Special Administrative Region of China"
		replace countryname = "Iran" if countryname == "Iran, Islamic Republic of"
		replace countryname = "Laos" if countryname == "Lao People's Democratic Republic"
		replace countryname = "Libya" if countryname == "Libyan Arab Jamah"
		replace countryname = "Macao Special Administrative Region of China" if countryname == "Macau"
		replace countryname = "Macedonia" if regexm(countryname, "Macedonia")==1
		replace countryname = subinstr(countryname, " Fed ", ", Federated ",.)
		replace countryname = "Moldova" if countryname == "Moldova, Republic of"
		replace countryname = "South Korea" if countryname == "Korea Democratic People's Republic"  | countryname == "Korea Republic" | countryname == "Korea, Democratic Peoples Republic of"
		replace countryname = "Saint Kitts and Nevis" if countryname == "St. Kitts and Nevis"
		replace countryname = "Saint Helena" if countryname == "St. Helena"
		replace countryname = "Saint Lucia" if countryname == "St. Lucia"
		replace countryname = "Saint Vincent and the Grenadines" if countryname == "St. Vincent and the Grenadines"
		replace countryname = "Sao Tome and Principe" if countryname == "Sao Tome et Principe"
		replace countryname = "Serbia and Montenegro" if countryname == "Serbia Montenegro"
		replace countryname = "St. Vincent and the Grenadines" if countryname == "St. Vincent and The Grenadines"
		replace countryname = "Syria" if countryname == "Syrian Arab Republic"
		replace countryname = "Tanzania" if countryname == "Tanzania Uni Republic"
		replace countryname = "The Gambia" if countryname == "Gambia The"
		replace countryname = "Vietnam" if countryname == "Viet Nam"
		replace countryname = "Yemen" if regexm(countryname, "Yemen")==1
		replace countryname = "Democratic Republic of the Congo" if countryname== "Zaire/Congo Democratic Republic" | countryname == "Congo, the Democratic Republic of the"
		replace countryname = "Israel" if countryname == "Palenstine (West Bank)"	// yikes...
		
		
		** drop the countries that are not in CoD computation
		drop if inlist(countryname, "Anguilla", "Cayman Islands", "Cook Islands", "French Polynesia", "Guadeloupe", "Martinique", "Micronesia, Federated States") | inlist(countryname, "Montserrat", "Netherlands Antilles", "New Caledonia", "Niue", "Palau", "Reunion", "Saint Helena", "Saint Kitts and Nevis") | inlist(countryname, "Tokelau", "Turks and Caicos Islands", "Tuvalu", "Virgin Islands, British", "West Bank", "French Guiana") | inlist(countryname, "Mayotte")

		** time to merge on the iso3 codes	
		merge m:1 countryname using `codes'
			drop if _m==2
			assert _m==3
			drop _m
			
	** figure out start and end date
		foreach var of varlist startdate enddate {
			split `var', parse( "/")
				rename `var'1 `var'_day
				rename `var'2 `var'_month
				rename `var'3 `var'_year
		}

		drop startdate enddate
		
		foreach var of varlist startdate_day-enddate_year {
			destring `var', replace
		}
		
	** is it a multi-year conflict?
	gen numyears = enddate_year-startdate_year+1
		** if it is a multi-year conflict, divide the number of deaths by length of interval
		**		and interpolate years between start year and end year
		expand numyears if numyears != 1
		sort iso type subtype startdate_year startdate_month startdate_day
		
		bysort iso type subtype startdate_year startdate_month startdate_day numkilled: gen nn = _n-1
		gen disyear = startdate_year+nn
		replace disyear = enddate_year+nn if disyear == .
		drop if disyear == .
		
		** do some checks
		assert startdate_year == enddate_year if numyears == 1
		assert disyear == startdate_year+nn | disyear == enddate_year+nn
		
		** now replace the number killed by the length of the interval
		replace numkilled = numkilled/numyears
		
	******************************************************************************************************	
	** CHECK HERE TO SEE IF THERE ARE UNDERLYING DIFFERENCES IN THE DATA BETWEEN UPDATE AND PREVIOUS VERSION
	if "`makecomparison'" == "yes" {
		tempfile temp
		save `temp', replace
		
		preserve
		keep iso3 numkilled disyear
		rename numkilled newtot 
		rename disyear year
		collapse (sum) newtot, by(iso3 year)
		merge 1:1 iso3 year using "formatted_type_specific_disaster_deaths_`old_date'.dta"
		keep if ihme_indic == 1
		keep iso3 year Total newtot
		rename Total oldtot
		gen absdiff = abs(oldtot-newtot)
		gen percentdiff = (absdiff/oldtot)*100
		count if percentdiff >= 1
		di in red "There are `r(N)' country-years with a >=1% difference between new and currently used TOTAL death numbers"

			** graph
			levelsof iso3, local(isos)
			quietly do "pdfmaker_Acrobat10.do"
			pdfstart using "compare_new_old_disaster_deaths_after_redistrib_of_multiyrs_`date'.pdf", distexe("`acrobat_distiller_path'")

			foreach iso of local isos {
				tw scatter oldtot year if iso3 == "`iso'" & percentdiff <1 & percentdiff != ., mcol(red) msymb(O) || ///
				scatter oldtot year if iso3 == "`iso'" & percentdiff >=1 & percentdiff != ., mcol(red) msymb(X) || ///
				scatter newtot year if iso3 == "`iso'" & percentdiff <1 & percentdiff != ., mcol(blue) msymb(Th) || ///
				scatter newtot year if iso3 == "`iso'" & percentdiff >=1 & percentdiff != ., mcol(blue) msymb(X)  ///
				title( "Currently used vs. updated disaster death numbers, `iso'") xtitle( "Year") ytitle( "Number of deaths") ///
				legend(label(1 "Currently used, <1% diff") label(2 "Currently used, >=1% diff") label(3 "Updated, <1% diff") label(4 "Updated, >=1% diff")) ///
				note( "X's denote years that have a >=1% diff between new and old") ///
				subtitle( "Before redistrib. of deaths in multi-yr disasters")
				pdfappend
			}
			pdffinish, view
		restore
	}
	************************************************************************************************************
	
	** DROP 2015 SAU HAJJ COLLAPSE, Using compiled data from wikipedia
	drop if iso3 == "SAU" & disyear == 2015 & type == "Miscellaneous Accident" & subtype == "Other" & numkilled == 2177

	drop numyears nn
	tempfile all_emdat_data
	save `all_emdat_data', replace
	
	** add in subnational data for MEX, CHN, UK, IND, BRA, JPN, SAU, SWE, USA
	** duplicate the data that is for these countries, and then assign the duplicates to the subnational locations
	use `all_emdat_data', clear
	keep if inlist(iso3, "CHN", "MEX", "GBR", "IND", "BRA", "JPN") | inlist(iso3,"SAU","SWE","USA","KEN","ZAF")
	
		** keep only years post 1989 and disasters with more than 300 deaths
		keep if disyear > 1989
		
		** split out the province/states
		** if it's missing, or is incomplete (has an ellipses), make it so that it says "not specified"
		replace location = "not specified" if location == ""
		drop if location == "not specified"
		replace location = subinstr(location, " ,", ",", .)
		split location, parse( ",")
		
		** reshape the data so that each line is an event-region
		rename (location location_id) (mainlocation mainlocation_id)
		generate event_id = _n
		reshape long location, i(event_id) j(area_number)
		drop if location == ""
		replace location = trim(location)
		
			** if it's not a full province you can figure out, make it missing, and drop it
			replace location = subinstr(location, " ...", "",.)
			replace location = subinstr(location, "province", "", .)
			replace location = subinstr(location, "pr", "", .)
			replace location = subinstr(location, " ", "", 1) if location != "not specified" & !inlist(iso3, "BRA", "GBR", "MEX")
			drop if location == ""
				
	**mini formatting for easier fixing of location names
	
		generate location2 = mainlocation
		drop location
		rename location2 location
		
		split location,p("Near"|"near")
		egen location3 = concat(location1 location2)
		
		replace location=location3
		drop location1 location2 location3
		
		sort iso3 location
		order iso3 location 		
		
	** fix the location names so you can merge on country-codes; drop the ones you can't figure out
	
		tempfile sub_work
	
			
			** BRA
			****************************************************************************************
			** Unkown, unclear, not in BRA
			preserve
			keep if iso3 == "BRA"
			
			replace location = "Maranhao" if regexm(location,"aranhao")|inlist(location,"Alcantara") 
			replace location = "Para" if inlist(location,"Altamira","Para state")
			replace location = "Amapa" if location == "Amapa state coasts"
			replace location = "Amazonas" if regexm(location,"Amazon")|regexm(location,"Manau")|location=="Urucurituba"
			replace location = "Bahia" if regexm(location,"Bahia")|inlist(location, "Antonio De Jesus","Barraeiras", "Salvador") 
			replace location = "Sao Paulo" if regexm(location,"Sao Paulo")|inlist(location, "Araras","Franca region","Guaratingueta","Guarulhos","Itaquaquecetuba","Guaratingueta","Orlandia","Rio Claro") | inlist(location, "Sau Paulo")
			replace location = "Minas Gerais" if regexm(location,"Minas Gerais")|inlist(location,"Belo Horizonte", "Mariana")
			replace location = "Ceara" if regexm(location,"Ceara")|inlist(location,"Barro","Tabosa region")
			replace location = "Rio de Janeiro" if regexm(location,"Rio de J")|inlist(location,"Campos (Rio State)","Mesquita (Rio state)","Niteroi","Rio","Paraty")
			replace location = "Mato Grosso" if regexm(location,"Grosso")|inlist(location,"Bom Futoro")
			replace location = "Rio Grande do Sul" if regexm(location,"Grande do S")|inlist(location, "Erechim","Uruguaiana (Rio Grande state)")
			replace location = "Rio Grande do Norte" if regexm(location,"Grande do N")
			replace location = "Parana" if regexm(location,"Parana")|inlist(location,"Faznda Rio Grande","Guaratuba", "Campo Mourao")
			replace location = "Sergipe" if regexm(location,"ergipe")|inlist(location,"Aracaju")
			replace location = "Distrito Federal" if inlist(location,"Brasilia")
			replace location = "Santa Catarina" if regexm(location,"atarina")
			replace location = "Mato Grosso do Sul" if inlist(location,"Porto Murtinho")
			replace location = "Acre" if regexm(location,"Acre")
			replace location = "Pernambuco" if regexm(location,"ernambouc")|location == "Recife"
			replace location = "Rondonia" if regexm(location,"ondoni")
			replace location = "Espirito Santo" if location == "Vitoria"
			replace location = "Goias" if location == "Goias state"
			
			save `sub_work', replace
			restore
			drop if iso3 == "BRA"
			append using `sub_work'
			
			
	
			** CHN
			*********************************************************************************************************
			** Unknown, unclear, not in CHN
			preserve
			keep if iso3 == "CHN"
			
			replace location = "Anhui" if regexm(location,"Anhui")|inlist(location,"Liji","Anqing")
			replace location = "Sichuan" if regexm(location,"Sichuan")|regexm(location,"Sichouan")|inlist(location,"Dingiapingmine","Dujiangyan")|regexm(location,"Luzhou")
			replace location = "Guangdong" if regexm(location,"uangdong")|regexm(location,"Canton")|regexm(location,"Guandong")|inlist(location,"Shunde","Kuiyong","Canton")|regexm(location,"Shenzhen")|inlist(location,"Shezhen","Shenzen","Zhuhai")
			replace location = "Guizhou" if regexm(location,"Guizhou")| regexm(location,"Panxian")|inlist(location,"Luipanshui","Fuquan","Guiyang","Gueizhou province","Fengxianpo(Kaiyang district","Andesheng(Jinsha county")|regexm(location,"Anshun")
			replace location = "Liaoning" if regexm(location,"Liaoning")|inlist(location,"Anshan","Dalian","Au large  de Dalian","Caijiagou(Shanxi )","Chaoyang")|regexm(location,"Fushun")|regexm(location,"Fuxin")|regexm(location,"Shenyang")
			replace location = "Chongqing" if regexm(location,"Chongq")|regexm(location,"Chongging")|regexm(location,"Fengjie")|regexm(location,"Shizhu")
			replace location = "Henan" if regexm(location,"Henan")|regexm(location,"Dengfeng")|regexm(location,"Kaixian")|regexm(location,"Xinmi")|regexm(location,"Boafeng")|regexm(location,"Pengshui")|inlist(location,"Zhengzou", "Xinxiang")
			replace location = "Jilin" if regexm(location,"Jilin")|regexm(location,"Dehui")|inlist(location,"Taonan","Changchun")|regexm(location,"Shulan")|regexm(location,"Baishan")
			replace location = "Heilongjiang" if regexm(location,"eilongjiang")|regexm(location,"Jixi")|regexm(location,"Heilonjiang")|regexm(location,"Heilongiang")|inlist(location,"Qitaihe","Harbin","Dongfeng(Qitaihe","Baiyanggou")
			replace location = "Hunan" if regexm(location,"Hunan")|inlist(location,"Yongxing (Huaping)","Neixiang","Luoyang","Bailing(Liling municipilaty","Doulishan(Lianyuan city")|regexm(location,"Huanan")
			replace location = "Gansu" if regexm(location,"Gansu")|regexm(location,"Ganzu")|inlist(location,"Tianshui")
			replace location = "Inner Mongolia" if regexm(location,"Inner Mongolia")|location=="Mongolie Interieure"
			replace location = "Beijing" if regexm(location,"Beijing")|regexm(location,"Pekin")|location=="Bejing"
			replace location = "Zhejiang" if regexm(location,"Zhejiang")|inlist(location,"Beilungang(Zheijang )","Changshan","Chehe")
			replace location = "Fujian" if regexm(location,"Fujian")|inlist(location,"Yongtai","Putian","Changle","Fuzhou","Dongjia Island")|regexm(location,"Chenjiashan")|regexm(location,"Jinjiang")
			replace location = "Hubei" if regexm(location,"Hubei")|inlist(location,"Zhushan county","Qianjiang district","Handan")|regexm(location,"Wuhan")
			replace location = "Hebei" if regexm(location,"Hebei")|inlist(location,"Hevei province","Shijiazhuang","Tangshan")
			replace location = "Shandong" if regexm(location,"Shandong")|regexm(location,"Shadong")|inlist(location,"Zaozhuang","Linyi","Laiwu","Changdao county","Qingdao")
			replace location = "Yunnan" if regexm(location,"Kunming")|regexm(location,"Yunnan")
			replace location = "Shanxi" if regexm(location,"Shanxi")|inlist(location,"Dianwan(Zuoyun district","Yangquan")|regexm(location,"Datong")
			replace location = "Shaanxi" if regexm(location,"Shaanxi")|regexm(location,"Xian")|inlist(location,"Wuhai City","Laogaochuan","Yanan")
			replace location = "Jiangsu" if regexm(location,"Jiangsu")|regexm(location,"Nanjing")|inlist(location,"Wuxi","Wuzhou","Nanying","Nankin")
			replace location = "Hainan" if regexm(location,"Hainan")
			replace location = "Xinjiang" if regexm(location,"Xinjiang")|regexm(location,"Sinkiang")|regexm(location,"Xianjiang")|inlist(location,"Urumqi")
			replace location = "Guangxi" if regexm(location,"Guangxi")|regexm(location,"Nanning")|inlist(location,"Huangmao","Guilin")
			replace location = "Jiangxi" if regexm(location,"Jiangxi")|regexm(location,"Jiangwi")|inlist(location,"Yichun","Shangrao","Jianxi","Jinxi")|regexm(location,"Nanchang")
			replace location = "Zhejiang" if regexm(location,"Zhejian")|regexm(location,"Zeijiang")|regexm(location,"Zheijang")|regexm(location,"Hangzhou")|regexm(location,"Zheijiang")|inlist(location,"Wenling","Wenzhou")
			replace location = "Hong Kong Special Administrative Region of China" if inlist(location,"Sai Kung","Lantau","Guanghzou","Guangzhou")|regexm(location,"Hong Kong")|regexm(location,"Kanton")|regexm(location,"Kowloon")
			replace location = "Shanghai" if regexm(location,"Shangai")|regexm(location,"Shanghai")
			replace location = "Qinghai" if regexm(location,"Qinghai")|regexm(location,"Qinhai")
			replace location = "Ningxia" if regexm(location,"Ningxia")
			replace location = "Tianjin" if regexm(location,"Tianjin")|inlist(location,"Tianjian")
			
			save `sub_work', replace
			restore
			drop if iso3 == "CHN"
			append using `sub_work'
			
			
			
			** GBR
			******************************************************************************************
			preserve
			keep if iso3 == "GBR"
			
			replace location = "Scotland" if regexm(location,"Scotland")|regexm(location,"Shetlands")|inlist(location,"Edinburg","Glasgow")
			replace location = "Yorkshire and the Humber" if regexm(location,"Yorkshire")	
			replace location = "Wales" if regexm(location,"Wales")
			replace location = "East of England" if regexm(location,"Au large de Great Yarmouth")
			replace location = "South East England" if inlist(location,"East of England","Bicester")|regexm(location,"Kent")|regexm(location,"Reading")
			replace location = "South West England" if inlist(location,"Bristol","Iralnade Land's End")
			replace location = "Greater London" if regexm(location,"London")
			replace location = "North West England" if inlist(location,"Preston")
			replace location = "England" if inlist(location,"The Channel")
			replace location = "West Midlands" if inlist(location,"Warwickshire")
			
			save `sub_work', replace
			restore
			drop if iso3 == "GBR"
			append using `sub_work'
			
			
			** IND
			*******************************************************************************************
			
			preserve
			keep if iso3 == "IND"
			
			replace location = "Uttar Pradesh" if regexm(location,"Uttar Pradesh state")
			replace location = "Uttar Pradesh, Urban" if regexm(location,"Luchnow")|regexm(location,"Agra")|regexm(location,"Lucknow")|regexm(location,"Allahabad")|regexm(location,"Ballia")|inlist(location,"Firozabad","Gonda-Naghir")|regexm(location,"Gorakhpur")
			replace location = "Uttar Pradesh, Urban" if regexm(location,"Jhansi")|regexm(location,"Kanpur")|regexm(location,"Khalilabad")|regexm(location,"Mathura")|regexm(location,"Meerut")|inlist(location,"Moradabad (Uttar Pradesh)","Moradabad area (Uttar Pradesh)","Choti Gandak River (Kushinagar)")
			replace location = "Uttar Pradesh, Rural" if regexm(location,"Tehri Garwal")|inlist(location,"Tundla (Uttar Pradesh)","Basti (Uttar Pradesh)","Mahiddinpur (Uttar Pradesh)","Kedarnath (Uttar Pradesh)", "Chakisais (Uttar Pradesh)")|regexm(location,"Kullu valley")|regexm(location,"Chamba")|regexm(location,"Chandi")
			
			replace location = "Gujarat" if inlist(location,"Gujarat province", "Gujarat state")
			replace location = "Gujarat, Urban" if inlist(location,"Ahmadabad","Ahmedabad")|inlist(location,"Dakor","Daman")|regexm(location,"Surat")|regexm(location,"Bharuch")|inlist(location,"Morovi")
			replace location = "Gujarat, Rural" if inlist(location, "Ambla (Gujarat state)")
			replace location = "Andhra Pradesh" if inlist(location,"Andra Pradesh","Andhra Pradesh","Andhra Pradesh State","Andhra Pradesh state","Andra Pradesh (Sud-est)")
			
			replace location = "Andhra Pradesh, Rural" if regexm(location,"Poonampalli")|regexm(location,"Godavarru")|inlist(location,"Chimagurhi")
			replace location = "Andhra Pradesh, Urban" if regexm(location,"Hyderabad")|inlist(location,"Nellore","Warangal (Andhra Pradesh)","Vijaywada")|regexm(location,"Kukatpally")|regexm(location,"Kurnool")|regexm(location,"Cuddapah")		
			
			replace location = "Assam" if inlist(location,"Assam state","Noa Dihing River (Assam)")
			replace location = "Assam, Rural" if inlist(location,"Gourmari (Assam province)")
			replace location = "Assam, Urban" if inlist(location,"Brahmapoutre (Guwahati)","Dalgaon","Dhubri district")
			
			replace location = "Maharashtra" if inlist(location,"Maharashtra","Maharashtra state")
			replace location = "Maharashtra, Urban" if inlist(location,"Mumbai","Bombay","Aurangabad","Borivli","Parbani area","Bhiwandi (Maharashtra)")|regexm(location,"Ahmednagar")|regexm(location,"Bombay region")|regexm(location,"Thane")|regexm(location,"Nagpur")|regexm(location,"Nasik")|inlist(location,"Poona","Sathara","Solapur (Maharashtra)","Solapur","Rajapur (Maharahstra state)")
			replace location = "Maharashtra, Rural" if regexm(location,"Dahanu")|regexm(location,"Ghatnandur")|regexm(location,"Kanhan")|inlist(location,"Pusawar ( Bhusawal)","Satara district")|regexm(location,"Raigad")
			
			replace location = "Madhya Pradesh" if inlist(location,"Madhya Pradesh state","Hoshangabad river (Madhya Pradesh state)")|regexm(location,"Moan sea")
			replace location = "Madhya Pradesh, Urban" if regexm(location,"Bhopal")|inlist(location,"Chindwara (Madhya Pradesh)","Datiya (Madhya Pradesh)")|regexm(location,"Gwal")|regexm(location,"Rohtak")
			replace location = "Madhya Pradesh, Rural" if regexm(location,"Datia")|inlist(location,"Shivpuri district","Tikamgarh ( Madhya Pradesh)")
			
			replace location = "Bihar" if inlist(location,"Bihar","Bihar State","Bihar state","Etat De Bihar","Sone River (Bihar)")
			replace location = "Bihar, Rural" if inlist(location,"Arwal (Bihar)","Bela river (Bihar)","Dhanarua (Bihar state)")|regexm(location,"Dumari")|regexm(location,"Jauri")|regexm(location,"Lahtora")|regexm(location,"Mangra")|regexm(location,"Sheohar")|inlist(location,"Singhi Ghat (Bihar)","Bagmati river, Rampurhari (Bihar)","Banka district (Bihar)","Dharminia (Bihar State)", " Bihar, Amlabad") | regexm(location, "Chakradhapur")
			replace location = "Bihar, Urban" if inlist(location,"Siwan","Begusarai (Gange fleuve)","Bhagalpur (Bihar state)","Aurangabad district (Bihar state)")|regexm(location,"Hajipur")|regexm(location,"Jamui")|regexm(location,"Khagaria")|regexm(location,"Khusropur")|regexm(location,"Kishanganj")|regexm(location,"Patna")
			
			replace location = "Punjab, Urban" if regexm(location,"Amritsar")|inlist(location,"Bataia (Punjab)","Kapurthala","Patiala (Punjab)")|regexm(location,"Gurdaspur")|regexm(location,"Khanna")
			replace location = "Punjab, Rural" if regexm(location,"Mansar")|regexm(location,"Sarai Banjara")
			replace location = "Punjab" if inlist(location,"Etat du Penjab","Pendjab","Penjab","Penjab state","Punjab state")
			
			replace location = "Jammu and Kashmir" if inlist(location,"Jammu and Cachemire","Cachemire")|regexm(location,"Kashmir")
			replace location = "Jammu and Kashmir, Rural" if inlist(location,"Bracher (Cachemire)","Nandani (Jammu-Cachemire state)","Poonch district (Cachemire)","Bari Pattan (Jammu)")|regexm(location,"Doda")|regexm(location,"Jandoral")|regexm(location,"Khaliyaneh")|regexm(location,"Kishtiwar")
			replace location = "Jammu and Kashmir, Urban" if inlist(location,"Wular lake (Srinagar)","Srinigar")|regexm(location,"Udhampur")
			
			replace location = "Rajasthan" if inlist(location,"Rajasthan state","Rajastan state")		
			replace location = "Rajasthan, Urban" if inlist(location,"Ajmer District","Beawar ( Amjer)")|regexm(location,"Jaipur")|regexm(location,"Jodhpur")
			replace location = "Rajasthan, Rural" if regexm(location,"Kamrup")
			
			replace location = "Uttarakhand" if inlist(location,"Uttarakhand region","Uttaranchal state")
			replace location = "Uttarakhand, Rural" if inlist(location,"Chakrata Tunni","Pithoragarh")|regexm(location,"Jayalgarh")|regexm(location,"Rudraprayag")
			replace location = "Uttarakhand, Urban" if regexm(location,"Dehradun")|regexm(location,"Srinagar")|inlist(location,"Haridwar","Udham Singh Nagar (Uttaranchal state)")
			
			replace location = "West Bengal" if inlist(location,"Bengal","Bengal state","West Bengal state","On Jalangi River (West Bengal)")|regexm(location,"Calcutta")|(regexm(location,"Golf") & iso3=="IND")|regexm(location,"Bengale")
			replace location = "West Bengal, Urban" if inlist(location,"Berhampore")|regexm(location,"Kharagpur")
			replace location = "West Bengal, Rural" if inlist(location,"Darjeeling","Simla","Simlagarh")|inlist(location,"Gaisan (Bengal Occidental)")|regexm(location,"Manikchack")|regexm(location,"Rangamati")
			
			replace location = "Delhi" if regexm(location,"Jamuna")
			replace location = "Delhi, Urban" if regexm(location,"Ludhiana")
			replace location = "Delhi, Rural" if inlist(location, "Naya (Delhi)")
			
			replace location = "Chhattisgarh, Rural" if regexm(location,"Bawankera")
			replace location = "Chhattisgarh, Urban" if inlist(location,"Bilaspur area","Korba","Raigarth")
			
			replace location = "Himachal Pradesh" if inlist(location,"Himachal Pradesh state")
			replace location = "Himachal Pradesh, Rural" if regexm(location,"Jwali")|regexm(location,"Kalel")|regexm(location,"Kufri")|inlist(location,"Palampur (Himachal Pradesh)","Sarahan","Sundla (Himalach Pradesh)")|regexm(location,"Kullu")
			replace location = "Himachal Pradesh, Urban" if inlist(location,"Rampur (Himachal Pradesh-","Simla (Himachal Pradesh state)")|regexm(location,"Dharamsala")
			
			replace location = "Jharkhand, Urban" if regexm(location,"Angara")|inlist(location,"Geslitand","Jamshedpur")|regexm(location,"Hazaribagh")|regexm(location,"Dhanbad")
			
			replace location = "Karnataka" if inlist(location,"Karnataka state")|inlist(location,"Tungabhadra river (Karnataka)")			
			replace location = "Karnataka, Urban" if regexm(location,"Bangalore")|regexm(location,"Bijjapur")|inlist(location,"Tumkur","Chitradurga (Karnataka)","Hassan district","Mysore","Mangole (Karnataka)")|regexm(location,"Davanagere")|regexm(location,"Hubli")|regexm(location,"Mangalore")
			replace location = "Karnataka, Rural" if inlist(location, "Bidar (Karnataka state)")
			
			replace location = "Orissa, Urban" if inlist(location,"Baripada","Cuttack (Orissa state)")|regexm(location,"Jajpur")
			replace location = "Orissa, Rural" if inlist(location,"Barpali","Kalijai")
			replace location = "Orissa" if inlist(location,"Orissa","Orissa State")			
			
			replace location = "Kerala" if inlist(location,"Kerala state")
			replace location = "Kerala, Urban" if regexm(location,"Calicut")
			replace location = "Kerala, Rural" if regexm(location,"Kalluvathukal")|inlist(location,"Thattekade (Kerala state)","Tirurangadi","Kumarakom (Kottayam district)")
			
			replace location = "Tamil Nadu, Urban" if regexm(location,"Chennai")|regexm(location,"Villupuram")|regexm(location,"Udumalpet")|regexm(location,"Tiruch")|regexm(location,"Katpadi")|regexm(location,"Madras")|inlist(location,"Tirupur (Tamil Nadu)")|regexm(location,"Kumbakonam")
			replace location = "Tamil Nadu, Rural" if inlist(location,"Dharmapuri (Samalpatti)","Thanjavur","Palamedu (Tamil Nadu state)","Pattukottai")|regexm(location,"Ramanathapuram")|regexm(location,"Sattur")|regexm(location,"Sivakasi")
			
			replace location = "Haryana, Urban" if regexm(location,"Faridabad")|inlist(location,"Karnal")
			replace location = "Haryana" if inlist(location,"Haryana state","On road of Haryana state")
			
			replace location = "Goa, Urban" if inlist(location,"Zuarinagar (Goa state)")
			
			replace location = "Jharkhand" if inlist(location,"Jharkhand state")
			replace location = "Jharkhand, Urban" if regexm(location,"Jharia")
			replace location = "Jharkhand, Rural" if regexm(location,"Kalubathan")
			
			replace location = "Manipur, Urban" if regexm(location,"Imphal")
			
			replace location = "Meghalaya, Rural" if regexm(location,"Iwwski")|inlist(location,"Sohryngkham (Meghalaya)")
			replace location = "Meghalaya" if inlist(location,"Meghalaya state")
			replace location = "Meghalaya, Urban" if regexm(location,"Shillong")
			
			replace location = "Arunachal Pradesh, Rural" if regexm(location,"Kurung Kummey")|regexm(location,"Sergaon")|inlist(location,"Twang district (near Chinese border)","West Siang (Arunachal Pradesh)")
			
			replace location = "Telangana, Rural" if regexm(location,"Medak")
			
			replace location = "The Six Minor Territories, Urban" if regexm(location,"Port Blair")
			
			replace location = "Haryana, Rural" if location == "Dabwali (Haryana state)"
			replace location = "Kerala, Rural" if location == "Kottamkoikkal, Kerala"
			replace location = "Kerala, Rural" if location == "Kottamkoikkal, Kerala"
			replace location = "Himachal Pradesh, Rural" if location == "Bhora (Himachal Pradesh)"
			replace location = "Jammu and Kashmir, Rural" if location == "Adharmadi (Jammu & Cachemire)"
			replace location = "Bihar, Urban" if location == "Biharsharif (Bihar)"
			replace location = "Madhya Pradesh, Rural" if location == "Dealwadi Ghat (Madhya Pradesh)"
			replace location = "Bihar, Rural" if location == "Bankaghat area (Bihar)"
			replace location = "Bihar, Rural" if location == "Moradabad (Bihar state)"
			replace location = "Tamil Nadu, Urban" if location == "Karur (Tamil Nadu)"
			replace location = "Andhra Pradesh, Rural" if location == "Bothalapalem, Nalgonda (Andhra Pradesh)"
			replace location = "Andhra Pradesh, Rural" if location == "Bothalapalem, Nalgonda (Andhra Pradesh)"
			replace location = "Assam, Urban" if location == "Khanapara (Assam state)"
			replace location = "Kerala, Rural" if location == "Sabarimala"
			replace location = "Karnataka, Rural" if location == "Devarabelakere (Karnataka)"
			replace location = "Jharkhand, Urban" if location == "Daltonganj (Bihar)"
			replace location = "Jammu and Kashmir, Rural" if location == "Banihal (Cachemire)"
			replace location = "Jammu and Kashmir, Urban" if location == "Sopore (Cachemire)"
			replace location = "Andhra Pradesh, Rural" if location == "Mahaboobghat (Andhra Pradesh)"
			replace location = "Uttar Pradesh, Rural" if location == "Nonapaar station (Uttar Pradesh)"
			replace location = "Andhra Pradesh, Rural" if location == "Nagayalanka Island"
			replace location = "Madhya Pradesh, Rural" if location == "Darritola area (Madhya Pradesh)"
			replace location = "Jammu and Kashmir, Rural" if location == "Leh (Indian Cachemire)"
			replace location = "Jammu and Kashmir, Rural" if location == "Shashu (Cachemire)"
			replace location = "Rajasthan, Rural" if location == "Kama (Rajasthan)"
			replace location = "Jammu and Kashmir, Rural" if location == "Khondroo (Cachemire)"
			replace location = "Gujarat, Urban" if location == "Bodeli (Gujarat State)"
			replace location = "Kerala, Rural" if location == "Sabarimala (Kerala state)"
			replace location = "Andhra Pradesh, Urban" if location == "Penneconda (Andhra Pradesh state)"
			replace location = "Goa, Urban" if location == "Canacona (Goa state)"

			save `sub_work', replace
			restore
			drop if iso3 == "IND"
			append using `sub_work'
			
			
			** JPN
			***************************************************************************************
			
			preserve
			keep if iso3 == "JPN"
			
			expand 4 if location == "Kashima, Ibaraki, Miyagi, Iwate"
				bysort event_id location : generate mult= _n
				replace location = "Kashima" if location == "Kashima, Ibaraki, Miyagi, Iwate" & mult ==1
				replace location = "Ibaraki" if location == "Kashima, Ibaraki, Miyagi, Iwate" & mult ==2
				replace location = "Miyagi" if location == "Kashima, Ibaraki, Miyagi, Iwate" & mult ==3
				replace location = "Iwate" if location == "Kashima, Ibaraki, Miyagi, Iwate" & mult ==4
				drop mult
			drop if location == "Kashima, Ibaraki, Miyagi, Iwate"
			
			replace location = "Hyogo" if regexm(location,"Hyogo")|inlist(location,"Akashi")
			replace location = "Fukushima" if regexm(location,"Fukushima")
			replace location = "Kyoto" if regexm(location,"Kyoto")|inlist(location,"Fukuchiama")
			replace location = "Tokyo" if regexm(location,"Tokyo")|inlist(location,"Izu Oshima Isl.")	
			replace location = "Iwate" if regexm(location,"Marioka")|inlist(location,"Kashima")
			replace location = "Niagata" if regexm(location,"Kashiwazaki")
			replace location = "Aichi" if inlist(location,"Nagoya")|regexm(location,"Aichi")
			replace location = "Fukuoka" if regexm(location,"Fukuoka")
			replace location = "Nagasaki" if regexm(location,"Hirado")
			replace location = "Osaka" if regexm(location,"Osaka")
			replace location = "Hokkaido" if regexm(location,"Hokkaido")
			replace location = "Chiba" if inlist(location,"Sodegaura")|regexm(location,"Chiba")
			replace location = "Shizuoka" if regexm(location,"Shizuoka")
			replace location = "Ibaraki" if inlist(location,"Tokaimura")
			
			save `sub_work', replace
			restore
			append using `sub_work'
			
			
			** USA
			*****************************************************************************************
			preserve
			keep if iso3 == "USA"
			
			expand 5 if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia"
				bysort event_id location : generate mult2 = _n
				replace location = "Pennsylvania" if location=="Pennsylvania, Ohio, Maryland, Virginia, West Virginia" & mult2 ==1
				replace location = "Ohio" if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia" & mult2 ==2
				replace location = "Maryland" if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia" & mult2 ==3
				replace location = "Virginia" if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia" & mult2 ==4
				replace location = "West Virginia" if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia" & mult2 ==5
				drop mult
			drop if location == "Pennsylvania, Ohio, Maryland, Virginia, West Virginia"
			
			replace location = "South Carolina" if regexm(location,"South Carolina")
			replace location = "Alabama" if regexm(location,"Alabama")
			replace location = "Alaska" if inlist(location,"Aleoutiennes isl.","Anchorage","Bering sea")
			replace location = "Pennsylvania" if regexm(location,"Pennsylvani")|inlist(location,"Pittsburgh")
			replace location = "Missouri" if regexm(location,"Missouri")
			replace location = "Colorado" if regexm(location,"Colorado")|inlist(location,"Aspen")
			replace location = "California" if regexm(location,"Californi") & iso3=="USA"|regexm(location,"Los Angeles")|inlist(location,"San Francisco")
			replace location = "Texas" if regexm(location,"Texas")|inlist(location,"Houston","Waco")
			replace location = "Ohio" if regexm(location,"Ohio")|inlist(location,"Cleveland")
			replace location = "Massachusetts" if regexm(location,"Massachusetts")|inlist(location,"Boston","Pocasset")
			replace location = "New York" if regexm(location,"New York")|regexm(location,"New york")|location=="New-York"
			replace location = "Georgia" if regexm(location,"Georgia")
			replace location = "Montana" if regexm(location,"Montana")
			replace location = "New Mexico" if regexm(location,"New Mexico")|regexm(location,"Carlsbad")|regexm(location,"Santa Fe")
			replace location = "North Carolina" if regexm(location,"North Carolina")
			replace location = "Tennessee" if regexm(location,"Tennessee")
			replace location = "Illinois" if regexm(location,"Chicago")|regexm(location,"Illinois")
			replace location = "Florida" if regexm(location,"Florida")|inlist(location,"Floroda coast","Miami")
			replace location = "Michigan" if regexm(location,"Michigan")
			replace location = "Louisiana" if regexm(location,"Louisiana")|inlist(location,"Donaldsonville","New Orleans")
			replace location = "Delaware" if regexm(location,"Delaware")
			replace location = "New Jersey" if regexm(location,"New Jersey")
			replace location = "Indiana" if regexm(location,"Indiana")
			replace location = "Hawaii" if regexm(location,"Hawaii")
			replace location = "Mississippi" if regexm(location,"Mississippi")
			replace location = "Connecticut" if regexm(location,"onnecticut")
			replace location = "Minnesota" if regexm(location,"Minnesota")|inlist(location,"Mineapolis")
			replace location = "Maryland" if regexm(location,"Maryland")
			replace location = "Arizona" if regexm(location,"Arizona")
			replace location = "Maine" if regexm(location,"Maine")
			replace location = "Oregon" if inlist(location,"Oregon State")
			replace location = "Arizona" if inlist(location,"Phoenix")
			replace location = "Nevada" if regexm(location,"Nevada")|inlist(location,"Las Vegas")
			replace location = "Virgina" if inlist(location,"Richmond","Virginia coast")
			replace location = "Oklahoma" if regexm(location,"Oklahoma")
			replace location = "Washington" if regexm(location,"Washington")|inlist(location,"Seattle")
			replace location = "Rhode Island" if regexm(location,"Rhode")
			replace location = "West Virginia" if inlist(event_id,1778,1763)
			replace location = "New Mexico" if (regexm(location, "Mexico") | regexm(location, "Nouveau Mexique")) & iso == "USA"
			replace location = "Pennsylvania" if location == "Philadelphia"
			replace location = "Virginia" if regexm(location, "Tallmansville") | regexm(location, "Virgina")
			
			save `sub_work', replace
			restore
			drop if iso3 == "USA"
			append using `sub_work'
			
			
			** MEX
			************************************************************************************
			preserve
			keep if iso3 == "MEX"
			
			replace location = "Nuevo Leon" if inlist(location,"Anahuac")
			replace location = "Coahuila" if inlist(location,"Barroteran","San Juan Sabinas")|regexm(location,"Coahuila")
			replace location = "Tlaxcala" if regexm(location,"Calpulapan")|inlist(location,"Nativitas")
			replace location = "Campeche" if regexm(location,"Campeche")
			replace location = "Quintana Roo" if regexm(location,"Cancun")|regexm(location,"Quintany")
			replace location = "Guanajuato" if inlist(location,"Salamanca","Celaya","Leon","Predio Arroyo Colorado")
			//Mexico state not country	
			replace location = "Mexico" if inlist(location,"Chalma","Tultepec","Tultitlan")|(regexm(location,"Mexico") & iso == "MEX")
			replace location = "Chiapas" if regexm(location,"Chiapas")
			replace location = "Jalisco" if regexm(location,"Guadalajara")
			replace location = "Distrito Federal" if regexm(location,"Mexico city")|location=="Mexico City"
			replace location = "Veracruz de Ignacio de la Llave" if regexm(location,"Veracruz")|regexm(location,"Cardenas")|inlist(location,"Coatzacoalas")
			replace location = "Oaxaca" if regexm(location,"Oaxaca")|inlist(location,"Santa Catalina","Juchitan")
			replace location = "Yucatan" if regexm(location,"Yucatan")|inlist(location,"Merida")
			replace location = "Chihuahua" if regexm(location,"Chihuahua")
			replace location = "Sonora" if regexm(location,"Obregron")|regexm(location,"Sonora")
			replace location = "Durango" if regexm(location,"Durango")
			replace location = "Sinaloa" if regexm(location,"Sinaloa")|regexm(location,"Mazatlan")|inlist(location,"Los Mochis")
			replace location = "Hidalgo" if regexm(location,"Hidalgo")|inlist(location,"Tula")
			replace location = "Guerrero" if regexm(location,"Guerrero")
			replace location = "Michoacán de Ocampo" if inlist(location,"Micho")
			replace location = "Nuevo Leon" if regexm(location,"Monterrey")
			replace location = "Nayarit" if regexm(location,"Nayarit")
			replace location = "Queretaro" if regexm(location,"Queretaro")|regexm(location,"San Joaquim")|regexm(location,"Jalpan")
			replace location = "Tamaulipas" if regexm(location,"Reynosa")
			replace location = "San Luis Potosi" if regexm(location,"Pontosi")
			replace location = "Puebla" if regexm(location,"Texmelucan")|regexm(location,"Puebla")|inlist(location,"Tehuacan")
			replace location = "Baja California Sur" if regexm(location,"Giganta")
			replace location = "Tabasco" if inlist(location,"Teapa","Villahermosa")
			replace location = "Chiapas" if inlist(location,"Tuxtla Gutierrez")
			replace location = "Michoacan de Ocampo" if regexm(location,"Michoacan")|regexm(location,"Ocampo")
			
			save `sub_work', replace
			restore
			drop if iso3 == "MEX"
			append using `sub_work'
			
			
			** SWE
			***************************************************************************************
			preserve
			keep if iso3 == "SWE"
			
			replace location = "Sweden except Stockholm" if regexm(location,"Gothenburg")|location=="Arson"
			
			save `sub_work', replace
			restore
			drop if iso3 == "SWE"
			append using `sub_work'
			
			** SAU
			***************************************************************************************
			preserve
			keep if iso3 == "SAU"
			
			replace location = "Riyadh" if regexm(location,"Riyadh")|inlist(location,"Ryad")
			replace location = "'Asir" if regexm(location,"Asir")|inlist(location,"Abha")|regexm(location,"Assir")
			replace location = "Eastern Province" if regexm(location,"Abqaiq")|inlist(location,"Ra's Al-Mish'Ab","Khobar","Dharan","Dhahran","Haradh-Uthmaniyah","Hafr al-Baten")|regexm(location,"Qatif")
			replace location = "Makkah" if regexm(location,"Makkah")|inlist(location,"Djeddah")
			replace location = "Makkah" if regexm(location,"La Mecque")|regexm(location,"Mecca")|regexm(location,"Mina")
			replace location = "Madinah" if inlist(location,"Medine")|inlist(location,"Yanbu")
			replace location = "Qassim" if regexm(location,"Qassim")
			replace location = "Jawf" if inlist(location,"Skaka")
			
			
			save `sub_work', replace
			restore
			drop if iso3 == "SAU"
			append using `sub_work'
			
			
			** KEN
			***************************************************************************************
			preserve
			keep if iso3 == "KEN"
			
			replace location = "Machakos" if regexm(location,"Machakos")| inlist(location,"Matuu","Athi River town","Kyanguli")
			replace location = "Mombasa" if regexm(location,"Mombas")|inlist(location,"Darajani, Ngailithia")
			replace location = "Bomet" if regexm(location,"Bomet")
			replace location = "Nairobi" if regexm(location,"Nairobi")|regexm(location,"Parklands")|inlist(location,"Top Lenana region")
			replace location = "HomaBay" if inlist(location,"Homa Bay")
			replace location = "Kilifi" if regexm(location,"Malindi")|regexm(location,"Kilifi")
			replace location = "Makueni" if regexm(location,"Mtito Andei")|inlist(location,"Mbooni","Makindu")|regexm(location,"Makueni")
			replace location = "Kericho" if regexm(location,"Kericho")
			replace location = "Nairobi" if regexm(location,"Kibera")
			replace location = "Kisii" if regexm(location,"Kissi")
			replace location = "Kisumu" if regexm(location,"Kisumu")|inlist(location,"Maseno/Lela")
			replace location = "Lamu" if regexm(location,"Lamu")|regexm(location,"Faza")
			replace location = "Kitui" if regexm(location,"Mutomo")|regexm(location,"Kitui")
			replace location = "Murang'a" if regexm(location,"Murang")|inlist(location,"Makuyu","Murunga district")
			replace location = "Marsabit" if regexm(location,"Marsabit")
			replace location = "UasinGishu" if inlist(location,"Moi (Rift Valley)")
			replace location = "Nakuru" if inlist(location,"Molo")|regexm(location,"Naivasha")
			replace location = "Meru" if inlist(location,"Nithi River")
			replace location = "TaitaTaveta" if regexm(location,"Tsavo")
			replace location = "Bungoma" if location=="Webuye"
			
			
			save `sub_work', replace
			restore
			drop if iso3 == "KEN"
			append using `sub_work'
			
			
			
			** ZAF
			***************************************************************************************
			preserve
			keep if iso3 == "ZAF"
			
			replace location = "Eastern Cape" if regexm(location,"Oriental")|regexm(location,"Eastern Cape")|regexm(location,"astern cape")|inlist(location,"t Port Elisabeth","King Williams","Col Nico Malan (South East)","Fort Beaufort","Jamestown (Cap Province)","Libode (Cape province)","Queenstown","Saint-Francis cape")|regexm(location,"Transkei")
			replace location = "Western Cape" if inlist(location,"Cape town")|inlist(location,"Bethlehem (Libre state)","Stellenbosh ( Cap)","Vredendal","Worcester","Guguletu, Langa (Cap)")
			replace location = "KwaZulu-Natal" if regexm(location,"Kwazulu-Natal")|regexm(location,"Durban")|regexm(location,"Kwazulu Natal")|regexm(location,"Natal")|location=="Kwa-Zulu natal"|inlist(location,"Hlabisa","Nkandla","Pietermaritzburg","Port Edwards")
			replace location = "Free State" if regexm(location,"Free")|inlist(location,"Harrismith","Kroonstad","Villiers")
			replace location = "Free State" if event_id==1922|inlist(location,"Province de l'Etat Libre","Welkom (Libre state)")
			replace location = "Gauteng" if regexm(location,"Johannesb")|inlist(location,"Springs","Pretoria","Ipelegeng","Roberthsham","Soweto")|regexm(location,"Gauteng")|regexm(location,"Carltonville")
			replace location = "Mpumalanga" if regexm(location,"pumalanga")|inlist(location,"Belfast","Komatipoort","Lydenburg","Machadodorp","Malelane","Piet Retief")|regexm(location,"Secunda")
			replace location = "Limpopo" if regexm(location,"Limpopo")|inlist(location,"Baobab","Louis Trichard","Warmbaths")
			replace location = "Western Cape" if regexm(location,"estern cape")|inlist(location,"Mariannu","Beaufort-West","Hex River Pass","Knysna","Malmesbury","Meyerton ( Johnnesburg)","Prince Albert")|regexm(location,"Laingsburg")|regexm(location,"Gamka")
			replace location = "Northern Cape" if regexm(location,"Kleinzee")
			replace location = "North-West" if inlist(location,"Lichtenburg","Rustenburg")
			
			save `sub_work', replace
			restore
			drop if iso3 == "ZAF"
			append using `sub_work'
			
			
			
			/* Get rid of any accented characters
			ASCII table
			dec | char
			225 | á
			227 | ã
			233 | é
			237 | í
			243 | ó
			244 | ô
			250 | ú
			*/
			replace location = subinstr(location, char(225), "a", .)
			replace location = subinstr(location, char(227), "a", .)
			replace location = subinstr(location, char(233), "e", .)
			replace location = subinstr(location, char(237), "i", .)
			replace location = subinstr(location, char(237), "i", .)
			replace location = subinstr(location, char(243), "o", .)
			replace location = subinstr(location, char(244), "o", .)
			replace location = subinstr(location, char(250), "u", .)
			
				
		** get number of provinces affected, distribute deaths across them	
		bysort event_id: gen nn = _n
		bysort event_id: egen number_provinces_affected = max(nn)
		replace numkilled = numkilled/number_provinces_affected 
		drop nn number_provinces_affected area_number event_id
		
		rename mainlocation_id location_id
		replace countryname = location
		drop location
		rename mainlocation location
		
		** add on iso3 codes
		drop iso3 location_id
		merge m:1 countryname using `codes_sub'
			replace _m = 3 if countryname == "The Bahamas" | countryname == "Taiwan" // keep Bahamas & Taiwan
			replace iso3 = "BHS" if countryname == "The Bahamas"
			replace iso3 = "TWN" if countryname == "Taiwan"
		keep if _m!=2
			replace iso3 = iso if _m == 1
		
		** bring together with all the other data (at the national level)
		append using `all_emdat_data'
		drop if _m == . & (inlist(iso3, "CHN", "MEX", "GBR", "IND", "BRA", "JPN") | inlist(iso3,"SAU","SWE","USA","KEN","ZAF"))
		replace _m = 4 if _m == .
		 
	** formatting
	drop start* end*
	replace type = subtype
	drop subtype
	drop if inlist(type, "", "--", "Radiation")
	order countryname iso3 gbd_region disyear, first	
	order numkilled, last
	compress
	

	** make the dataset wide
		** first need to collapse the number killed by iso3-disaster year - type
		collapse (sum) numkilled, by(countryname iso3 location_id gbd_region disyear type _m) fast
		
		** split unknown subnationals
		preserve
			import excel using "tech_SUB_strUser.xlsx", clear firstrow
			
			// First clean up spelling, then match with `codes_sub'. Some obs. are still unknown
			rename CorrectedSubnational countryname
			rename ISO3 iso3
			rename Region gbd_region
			rename Year disyear
			rename Event type
			rename Deaths numkilled
			keep countryname iso3 gbd_region disyear type numkilled
			replace countryname = "N/A Unknown" if countryname == "N/A"
			// Split mulit-location events
			gen id = _n
			split countryname, parse(",")
			drop countryname
			reshape long countryname, i(iso3 disyear gbd_region type numkilled id) j(multi_indic)
			replace countryname = trim(countryname)
			drop if countryname == ""
			bysort id : replace multi_indic = _N
			replace numkilled = numkilled / multi_indic
			drop multi_indic
			// Clean-up countrynames
			replace countryname = proper(countryname)
			// Fix India Urban/Rural spelling
			replace countryname = subinstr(countryname, " (Urban)", ", Urban", 1)
			replace countryname = subinstr(countryname, " (Rural)", ", Rural", 1)
			replace countryname = "Rio de Janeiro" if countryname == "Rio De Janeiro"
			replace countryname = subinstr(countryname, "Andrha", "Andhra", 1)
			replace countryname = subinstr(countryname, "Dehli", "Delhi", 1)
			replace countryname = subinstr(countryname, "Jammu And Kashmir", "Jammu and Kashmir", 1)
			replace countryname = subinstr(countryname, "Karaimnagar", "Telangana", 1)
			replace countryname = "Telangana" if countryname == "Telengana"
			replace countryname = "West Virginia" if countryname == "(West Virginia"
			replace countryname = subinstr(countryname, "Kwazulu", "KwaZulu", 1)
		
			merge m:1 countryname using `codes_sub', keep(1 3)
				gen split = 0 if _m == 3
				replace split = 1 if _m == 1
				drop _merge
				
			drop if numkilled == 0
			
			tempfile sub_researched
			save `sub_researched', replace
			
		restore
		// Drop the observations that were researched above
		drop if _m == 1
		gen split = 0
		append using `sub_researched'
		drop _merge
		
		// Split Indian states by urbanicity
		preserve
			keep if split == 1 & iso3 == "IND" & countryname != "N/A Unknown"
			
			// get state location_id
			drop location_id
			merge m:1 countryname using `india_states', keep(3) assert(2 3) nogen
			
			// split into urbanicity
			collapse (sum) numkilled, by(iso3 location_id gbd_region disyear type) fast
			rename location_id parent_id
			
			merge 1:m parent_id disyear type using `india_urbanicity', keep(3) assert(2 3) nogen
			
			replace numkilled = numkilled * weight
			
			drop parent_id weight
			gen split = 0
			
			save `india_urbanicity', replace
			
		restore
		drop if split == 1 & iso3 == "IND" & countryname != "N/A Unknown"
		append using `india_urbanicity'
		// Split remaining subnationals
		preserve
			keep if split == 1
			
			collapse (sum) numkilled, by(iso3 disyear gbd_region type) fast
			
			merge 1:m iso3 disyear type using `subnatl_popweight', keep(3) assert(2 3) nogen
			
			replace numkilled = numkilled * weight
			
			collapse (sum) numkilled, by(iso3 location_id disyear type gbd_region) fast
			gen split = 0
			
			tempfile subnatl_estimate
			save `subnatl_estimate', replace
			
		restore
			drop if split == 1
			append using `subnatl_estimate'
			assert split == 0
			drop split
		
		
	// FINAL COLLAPSE
		collapse (sum) numkilled, by(iso3 location_id disyear type) fast
		isid iso3 location_id disyear type
		
	rename disyear year
	rename type cause

	generate source = "EMDAT"
	gen nid = 13769

** append sources together
append using `hajj_sup'


** save
	compress
	order iso3 location_id year source, first
	save "formatted_type_specific_technological_deaths.dta", replace
	save "formatted_type_specific_technological_deaths_`date'.dta", replace


