** Purpose: Format the Robert Strauss Center data for the war/ terrorism/ legal intervention database


** ACLED ** 
	import delimited using "ACLED_ARMED_CONFLICT_LOCATION_AND_EVENT_DATASET_REALTIME_COMPLETE_ALL_AFRICA_Y2015M11D03.csv", clear varnames(1)

	// variable plans and notes
	// COUNTRY: never missing, always contains an actual country. trim it, merge with ihme country names, fix up any misses
	// event_type: use as cause along with other info
	//		- protests: legal intervention, as they are non-violent on side of civilians
	// 		- drop any completely non-violent events
	//		- split violence against civilians to legal intervention and terrorism
	// 		- use any battles as war, including rebellions
	// 		- riots: consider same as rebellion, include all deaths in the war deaths for the country
	//

	drop if fatalities==0

	// war - battles
	gen cause = "war" if regexm(event_type, "Battle")
	// war - riots
	replace cause = "war" if regexm(event_type, "Riots") & (regexm(actor1, "Rioters") | regexm(actor2, "Rioters"))
	// legal intervention - quelled protest
	replace cause = "legal intervention" if regexm(event_type, "Riots") & cause==""
	// legal intervention - government brutality
	replace cause = "legal intervention" if regexm(event_type, "Violence") & interaction>=10 & interaction<=19
	// terrorism
	replace cause = "terrorism" if regexm(event_type, "Violence") & cause==""
	// war - the remaining deaths
	replace cause = "war" if cause==""

	rename (year country adm_level_1 fatalities) (year location_name subdiv war_deaths_best)
	keep year location_name subdiv cause war_deaths_best
	replace location_name = trim(location_name)
	destring year, replace force
	tempfile data
	save `data', replace

	use "IHME_COUNTRYCODES.DTA", clear
	keep countryname countryname_ihme iso3
	
	drop if iso3 == ""
	
	tempfile iso3
	save `iso3', replace
	rename countryname location_name
	merge 1:m location_name using `data', nogen keep(2 3)

	replace iso3="SSD" if location_name=="South Sudan"
	replace subdiv = "Free State" if subdiv == "Orange Free State"
	collapse (sum) war_deaths_best, by(iso3 subdiv year cause)
	gen source = "ACLED"
	
	drop if iso3 == ""
	gen nid = 135380
	
	tempfile acled
	save `acled', replace
	
** SCAD **
	import excel "SCAD_1990_2012_V_3_0_Y2014M08D29.XLSX", firstrow clear
	rename ndeath war_deaths_best
	keep if sublocal==1
	drop if war_deaths_best<=0
	
	// get iso3
	replace countryname = trim(countryname)
	merge m:1 countryname using `iso3', keep(1 3)
	replace iso3="SSD" if countryname=="South Sudan"


	** get deaths in each county-year
	** for the conflicts that spreadout over multiple years: distribute the deaths across the years
		generate multiyr_indic = 1 if styr != eyr
		replace multiyr_indic = 0 if styr == eyr 
		
		** how many years are in each event? make each year a row
		generate expand_multiplier = eyr - styr + 1
		expand expand_multiplier if multiyr_indic == 1
	
	** for multi year events: generate the 1st of the year of the 2nd year (or 3rd year) to be able to get the length of time in each year. 
	sort eventid id ccode
	bysort eventid id ccode: gen yearnum = _n
	
		replace stday = 1 if multiyr_indic == 1 & inlist(yearnum, 2, 3)
		replace stmo = 1 if multiyr_indic == 1 & inlist(yearnum, 2, 3)
		replace styr = styr + yearnum - 1 if inlist(yearnum, 2, 3)
	
		replace eday = 31 if multiyr_indic == 1 & yearnum == 1
		replace emo = 12 if multiyr_indic == 1 & yearnum == 1
		
		replace eday = 31 if multiyr_indic == 1 & yearnum == 2 & expand_multiplier == 3
		replace emo = 12 if multiyr_indic == 1 & yearnum == 2 & expand_multiplier == 3
		
		replace eyr = styr if multiyr_indic == 1
		
		** get length of conflict within each year.  the mdy() function returns days since jan 1, 1960.  so subtract the 2 dates to get length in dates
		generate cmc_startdate = mdy(stmo, stday, styr)
		generate cmc_enddate = mdy(emo, eday, eyr)
		generate length = cmc_enddate - cmc_startdate + 1
		
		** figure out proportion of the deaths that are in each year.  we already have the full duration, so divide the length in each year by the full duration to get the proportion
		generate double proportion_deaths_in_year = length/duration
		replace war_deaths_best = war_deaths_best*proportion_deaths_in_year
		
		rename styr year
	
	
	gen cause=""
	// intra-government violence
	replace cause="war" if etype==10
	// pro-government violence
	replace cause = "legal intervention" if etype==7
	// riot responded to by government with lethal or non-lethal force
	replace cause = "legal intervention" if etype <=6 & repress != 0
	// extra-government violence
	replace cause="terrorism" if etype==9
	// everything else
	replace cause="war" if cause==""
	
	// Subnational for ZAF
	gen subdiv = ""
	replace subdiv = "Eastern Cape" if inlist(ilocal, "Cuylerville")
	replace subdiv = "Free State" if inlist(ilocal, "President Steyn mine near Welkom", "Wildebeestfontein South mine")
	replace subdiv = "Gauteng" if inlist(ilocal, "Tokoza", "Zonkwezizwe squatter camp southeast of Johannesburg", "Sebokeng", "Johannesburg area townships", "Soweto", "Johannesburg townships", "Johannesburg", "Boipatong") | inlist(ilocal, "Johannesburg region", "Katlehong", "East Rand")
	replace subdiv = "KwaZulu-Nata" if inlist(ilocal, "Lusaka district", "Natal", "KwaZulu-Natal province")
	replace subdiv = "North-West" if inlist(ilocal, "Orkney", "Marikana")
	expand 3 if ilocal == "Cape Province"
		bysort eventid ilocal : gen mult = _n
		replace war_deaths_best = war_deaths_best / 3 if ilocal == "Cape Province"
		replace subdiv = "Eastern Cape" if ilocal == "Cape Province" & mult == 1
		replace subdiv = "Northern Cape" if ilocal == "Cape Province" & mult == 2
		replace subdiv = "Western Cape" if ilocal == "Cape Province" & mult == 3
		drop mult
	

	collapse (sum) war_deaths_best, by(iso3 subdiv year cause)
	gen source = "SCAD"
	gen nid = 135381
	
	tempfile scad
	save `scad', replace
	append using `acled'
	gen dataset_ind=101
saveold "robert_strauss_center_data.dta", replace
	
