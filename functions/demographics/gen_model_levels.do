** Generate mortality flat file that identified all modeled units and establishes a modeling hierarchy based on the mortality hierarchy in the database
	
	clear all
	set more off
	
	odbc load, exec("select ch.location_set_id,c.location_id, c.location_name, ch.parent_id, ch.ihme_loc_id , ch.path_to_top_parent, ch.level, ch.is_estimate, ch.sort_order, ch.location_set_version_id from shared.location_hierarchy_history ch, shared.location c where c.location_id=ch.location_id AND location_set_id=21 AND location_set_version_id=39 order by sort_order;") dsn(shared) clear
	
	drop if level < 3
	drop if is_estimate == 0
	gen level_all = 0
	gen level_1 = 0
	gen level_2 = 0
	gen level_3 = 0
	
	** places we parallelize GPR jobs on, for example
	replace level_all = 1 if !inlist(location_id,44538,44539,44540) 
		** include six territories
		replace level_all = 1 if inlist(location_id,44538,44539,44540) 
	
	
	** places we treat as "nationals"
	replace level_1 = 1 if level == 3
		** include Hong Kong, Macao, China w/o Hong Kong and Macao
		replace level_1 = 1 if inlist(location_id,354,361,44533)
	count if level_1 == 1
		
	
	** nationals and first level subnationals
	replace level_2 = 1 if level == 3
		** include Hong Kong, Macao
		replace level_2 = 1 if inlist(location_id,354,361)
		** include China provinces, exclude China without Hong Kong and Macao
		replace level_2 = 1 if parent_id == 44533
		replace level_2 = 0 if location_id == 44533
		** include Mexico states
		replace level_2 = 1 if parent_id == 130
		replace level_2 = 0 if location_id == 130
		** include Sweden- Stockholm and Sweden excluding Stockholm
		replace level_2 = 1 if parent_id == 93
		replace level_2 = 0 if location_id == 93
		** include Kenya subnat
		replace level_2 = 1 if parent_id == 180
		replace level_2 = 0 if location_id == 180
		** include South Africa subnat
		replace level_2 = 1 if parent_id == 196
		replace level_2 = 0 if location_id == 196
		** include India states, but exclude 6 minor territories- these will be done post-modeling
		replace level_2 = 1 if parent_id == 163 & location_id != 44538
		** for now, we want to include six minor territories in level 2
		replace level_2 = 1 if location_id == 44538
		replace level_2 = 0 if location_id == 163
		** include UK
		replace level_2 = 1 if parent_id == 4749 | parent_id == 95
		replace level_2 = 0 if location_id == 95
		** include Brazil
		replace level_2 = 1 if parent_id == 135
		replace level_2 = 0 if location_id == 135
		** include US
		replace level_2 = 1 if parent_id == 102
		replace level_2 = 0 if location_id == 102
		** include JPN
		replace level_2 = 1 if parent_id == 67
		replace level_2 = 0 if location_id == 67
		** Include Saudi
		replace level_2 = 1 if parent_id == 152
		replace level_2 = 0 if location_id == 152
		
	count if level_2 == 1
	
	
	** nationals and second level of subnationals
	replace level_3 = 1 if level == 3
		** include Hong Kong, Macao
		replace level_3 = 1 if inlist(location_id,354,361)
		** include China provinces
		replace level_3 = 1 if parent_id == 44533
		replace level_3 = 0 if location_id == 44533
		** include Mexico states
		replace level_3 = 1 if parent_id == 130
		replace level_3 = 0 if location_id == 130
		** include Sweden- Stockholm and Sweden excluding Stockholm
		replace level_3 = 1 if parent_id == 93
		replace level_3 = 0 if location_id == 93
		** include Kenya subnat
		replace level_3 = 1 if parent_id == 180
		replace level_3 = 0 if location_id == 180
		** include South Africa subnat
		replace level_3 = 1 if parent_id == 196
		replace level_3 = 0 if location_id == 196
		** include India states by urban/rural- but exclude 6 minor territories- these will be done post-modeling
		preserve
		keep if parent_id == 163 & location_id != 44538
		keep location_id
		rename location_id parent_id
		tempfile data
		save `data', replace
		restore
		merge m:1 parent_id using `data'
		replace level_3 = 1 if _m == 3
		replace level_3 = 0 if location_id == 163
		drop _m
		** include UK
		replace level_3 = 1 if parent_id == 4749 | parent_id == 95
		replace level_3 = 0 if location_id == 95
		** include Brazil
		replace level_3 = 1 if parent_id == 135
		replace level_3 = 0 if location_id == 135
		** include US
		replace level_3 = 1 if parent_id == 102
		replace level_3 = 0 if location_id == 102
		** include JPN
		replace level_3 = 1 if parent_id == 67
		replace level_3 = 0 if location_id == 67
			** include six territories for now
			replace level_3 = 1 if inlist(location_id,44539,44540) 
		** Include Saudi
		replace level_3 = 1 if parent_id == 152
		replace level_3 = 0 if location_id == 152
		
	count if level_3 == 1
	
	
	
	outsheet using "strPath/modeling_hierarchy.csv", comma replace


