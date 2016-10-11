
// PURPOSE: retrieve outputs for gbd 2015 (modified for pulling N-codes, which don't fit cleanly into database hierarchy)



/*
@docstring

Get_outputs is a stata function that is used to query the gbd outputs database
for final estimates (this is the same database that gbd_compare uses). GBD2013
results have been carried over to the new database, so this function can get
both 2013 best results and current 2015 results. See below for descriptions of
each argument, and example usage.

SYNTAX:
	get_outputs , topic(string) [drop_restrictions] [measure_id(string)] [version(string)] 
				[location_id(string) year_id(string) year_start_id(string) year_end_id(string)]
                [age_group_id(string) sex_id(string) cause_id(string) rei_id(string)]
                [sequela_id(string) rank rank_level(string) metric_id(string) gbd_round(string)] 
                [lookup_versions lookup_tables cause_set_id(integer 3) table(string) ] clear

ARGUMENTS:
	get_outputs , 				
		--function call
		
	topic 					
		-- gbd topic area. must be one of ("cause","rei","sequela")
		
	drop_restrictions			
		-- drop all demographics that are restricted at the cause level. (only works for causes)
		
	measure_id				
		-- measure_id that you wish to pull results for. defaults to death. cannot specify "all" for this option
		
	version					
		-- gbd compare version that you wish to pull results for. Defaults to current best results for the gbd round.
           To see a list of gbd compare versions alongside cod/como/dalynator versions, use lookup_versions option

    lookup_versions
        -- instead of returning results, return a table with version id info. Use this if you need to specify a 
           specific version but don't know which id to use.

    lookup_tables
        -- instead of returning results, return a table with info about all output tables that aren't associated with a compare_version.
           For example, a como table before the dalynator runs. Use this in conjuction with "table" argument below, if you need to query
           a specific table before it's associated with a compare_version. In general, you shouldn't need to use this much.
    
    table
        -- if you know the specific table you want to query, you can use this argument. This is useful if the
        table hasn't been added to compare_version_output yet (ie COMO before dalynator run). 
        ie table("output_epi_single_year_v166")

    gbd_round
        -- defaults to 2015. 
		
	location_id				
		-- location_id that you wish to pull results for. defaults to global (1). option "all" pulls the set of locations used by  GBD Reporting in 2015
		
	year_id					
		-- year_id that you wish to pull results for. defaults to 2015 or 2013. option "all" pulls (1990 1995 2000 2005 2010) plus
           either 2015 or 2013 depending on gbd_round argument. Year_id argument is mutually exclusive of year_start and 
           year_end arguments

    year_start_id, year_end_id
        -- space separated list of starting years and ending years (for percent change queries). For instance, 1990-2015
           and 2000-2015 percent change results would be specified like so: year_start_id(1990 2000) year_end_id(2015 2015)
		
    metric_id
        --- space separated list of metric_ids you want. 1 = number (ie cases), 2 = percent (ie cause fraction or paf) 
        3 = per capita rate. "all" pulls all 3 metrics. Defaults to 1, number. Please note that these definitions
        are for single year queries. If you have a multi year query, you're asking for median percent change of
        {cases,fractions,rates}.

	age_group_id				
		-- age_group_id that you wish to pull results for. defaults to all ages (22). option "all" pulls gbd-compare age groups
        (aka ids 1 through 27)
		
	sex_id					
		-- sex_id that you wish to pull results for. defaults to both (3). option all" pulls ("males","females","both")
		
	cause_id				
		-- cause_id that you wish to pull results for. defaults to all cause (294). option "all" pulls all GBD 2015 causes 
        from the reporting hiearchy (unless you've specified a different cause_set_id, see below). Option lvl1, lvl2, lvl3,
        most_detailed will pull from the corresponding level of the cause hierarchy.

    cause_set_id
        -- Defaults to 3, the GBD reporting hierarchy. This value affects which causes are pulled when cause_id = "all"
        (see above). The mortcod paper is 7, and the nonfatal paper is 9. All cause sets are enumerated in shared.cause_set.
		
	rei_id					
		-- rei_id that you wish to pull results for. defaults to all risk factors (169) if "topic" is rei. option "risks" pulls 
           every GBD 2015 risk factor. Option "etiologies" pulls all GBD 2015 etiologies. Options "injuries" and "impairments" do what you'd expect. Option "all" pulls the union of all the options listed above.
		
	sequela_id				
		-- sequela_id that you wish to pull results for. no default. Can also specify "all".
	
    rank
        -- If specified, get rank results instead of burden estimates. Mutually exclusive with multi year queries and sequelae

	rank_level				
		-- if ranks requested, rank_level that you wish to pull results for. Defaults is rank_level 4. Rank level is the
        level of the cause or rei hierarchy that causes/reis are ranked against. IE rank level 4 is the ranking of all 
        most detailed causes or reis for a given demographic. Option "all" pulls all rank levels

	clear					
		-- clears existing dataset from memory
	
	
EXAMPLES:
	get_outputs, topic(cause) clear
		-- pulls global all cause death values for both sex, all age, 2015, GBD2015

	get_outputs, topic(rei) measure_id(3) rei_id(192) year_id(2013) gbd_round(2013) clear 
		-- pulls global ylds for both sex, all age, 2013 due to anemia, GBD2013

	get_outputs, topic(sequela) sequela_id(1) year_id(all) clear
		-- pulls global tuberculosis values for all years, GBD2015

	get_outputs, topic(cause) rank year_id(1990 2013) cause_id(all) gbd_round(2013) clear
		-- pulls global ranks for all level 4 causes in 1990 and 2013 for GBD 2013

	get_outputs, topic(rei) rank location_id(all) rei_id(all) year_id(2013) gbd_round(2013) clear
		-- pulls  ranks for all level 4 risks in 2013 for every location, sex = both, all ages

	get_outputs, topic(cause) cause_id(366) age_group_id(all) sex_id(all) year_id(2013) gbd_round(2013) drop_restrictions clear
		-- pulls global demographic restricted deaths from maternal

    get_outputs, topic(cause) measure_id(2) year_start_id(1990 1990) year_end_id(2013 2005) gbd_round(2013) clear
        -- pulls median percent change from 1990-2013 and 1990-2005 of global all cause DALYs, sex=3, all ages for GBD2013
    
    get_outputs, topic(cause) metric_id(1 2 3) year_id(all) age_group_id(all) cause_id(all) location_id(6) gbd_round(2013) clear
        -- pulls counts, rates, and cause fractions for China deaths for every year, every age, and every cause for gbd 2013

    get_outputs, topic(rei) metric_id(2) rei_id(82) cause_id(all) gbd_round(2013) year_id(2013) clear
        -- pulls Global PAFs for every cause associated with the risk Unsafe Water, Sanitation, and Handwashing
            all ages, both sexes, GBD2013, year 2013
gnirtscod@
*/

*** *************************************************
*** define main
*** *************************************************

cap program drop get_ncode_outputs
program define get_ncode_outputs
	syntax , topic(string) [drop_restrictions] [measure_id(string)] [version(string)] ///
		[location_id(string) year_id(string) year_start_id(string) year_end_id(string) age_group_id(string) sex_id(string)] ///
		[cause_id(string) rei_id(string) sequela_id(string) rank_level(string) gbd_round(integer 2015)] ///
        [metric_id(string) rank debug lookup_versions lookup_tables cause_set_id(integer 3) table(string) _test] ///
		clear

    quiet {
    	*** *************************************************
    	*** load helpers and change directory for duration of function call
    	*** *************************************************
    			
    	// change directories to maintain relative paths
    	local old_dir = "`c(pwd)'"
    	if c(os) == "Unix" global j "/home/j"
    	else global j "J:"
    	cd "$j/WORK/10_gbd/00_library/functions" 
    
    	// load helpers
    	run "./create_connection_string.ado"
    	run "./get_restrictions.ado"
    	run "./get_outputs_helpers/query_table.ado"
    	run "./get_outputs_helpers/keep_in.ado"
    	run "./get_outputs_helpers/confirm_table.ado"
    	run "./get_outputs_helpers/mata_helpers.do"
    	run "./get_outputs_helpers/tables_to_query.ado"
    	run "./get_outputs_helpers/add_sequela_info.ado"
    
       	*** *************************************************
    	*** set intelligent defaults for missing options
    	*** *************************************************
    
    	// set version default
    	if mi("`version'") local version = "best"
    
    	// set demographic defaults for missing
    	if mi("`location_id'") local location_id = 1
    	if mi("`year_id'") & mi("`year_start_id'") local year_id = `gbd_round' // default to 2013 or 2015
    	if mi("`age_group_id'") local age_group_id = 22
    	if mi("`sex_id'") local sex_id = 3
    
    	// set cause_id default for missing
    	if mi("`cause_id'") & "`topic'" != "sequela" local cause_id = 294
    	
    	// set measure_id default for missing
    	if mi("`measure_id'") local measure_id = 1
    
        // set default metric_id, if missing (if rank is specified, metric 
        // will be set as 4)
    	if mi("`metric_id'") & mi("`rank'") local metric_id = 1
    	if mi("`metric_id'") & !mi("`rank'") local metric_id = 4

    	// set rei_id default for missing
    	if mi("`rei_id'") & "`topic'" == "rei" local rei_id = 169
    	
    	// set rank_level default for missing
    	if mi("`rank_level'") & !mi("`rank'") local rank_level = 4
    
    	*** *************************************************
    	*** validate arguments
    	*** *************************************************
    
    	// check topic arguments
    	if !inlist("`topic'","cause","rei","sequela") { 
    		noisily di as error "topic must be one of: cause | rei | sequela"
    		error(1)
    	    }
    
        // check for mutually exclusive argument combinations
        if (!mi("`year_start_id'") & !mi("`year_id'")) | ///
           (mi("`year_start_id'") & mi("`year_id'"))  {
            #delim ; 
            noisily di as error "Must either specify year_id, or year_start and year_end.
            Year range queries are mutually exclusive of single year queries";
            #delim cr
    		error(1)
            }
    
        if (mi("`year_end_id'") & !mi("`year_start_id'")) | ///  
           (!mi("`year_end_id'") & mi("`year_start_id'")) { 
            noisily di as error "year_start_id and year_end_id must be specified together"
    		error(1)
            }
    
        if !mi("`rank'") & "`topic'" == "sequela" {
            noisily di as error "Sequelae are not ranked. Cannot request ranks for sequelae"
    		error(1)
            }
    
        if !mi("`rank'") & !mi("`year_start_id'") {
            noisily di as error "Percent change between years are not ranked. Cannot request ranks of multi-year results"
    		error(1)
            }
    
        if mi("`rank'") & !mi("`rank_level'") {
            noisily di as error "Rank level argument only applies if ranks are requested"
            error(1)
            }

        // Use rank option instead of specifying metric_id = 4
        // (Right now the query won't pull rank values alongside other metrics
        // properly)
        if "`metric_id'" == "4" & mi("`rank'") {
            di as error "Use rank option instead of metric_id = 4"
            error(1)
            }
    
        if !inlist(`gbd_round', 2013, 2015) {
            noisily di as error "Invalid gbd round specified. Must be 2013 or 2015"
            error(1)
            }

        // Can only specify one measure at a time
        local num_measures : list sizeof measure_id
        if !mi("`debug'") noi di "number of measures: `num_measures'"
        if "`measure_id'" == "all" | `num_measures' > 1 {
            noisily di as error "Can only specify one measure at a time"
            error(1)
            }
        
    	*** *************************************************
    	*** create connection string for each db
    	*** *************************************************
        if !mi("`_test'") {
    	    create_connection_string, server(gbd-db-t01) database(gbd)
        }
        else {
    	    create_connection_string, server(modeling-gbd-db) database(gbd)
        }
    	local gbd_string = r(conn_string)
    	create_connection_string, server(modeling-cod-db) database(shared)
    	local shared_string = r(conn_string)
    	create_connection_string, server(modeling-epi-db) database(epi)
    	local epi_2015_string = r(conn_string)
    
       	*** *************************************************
    	*** if lookup_versions option specified, return a view of gbd.compare_version_outputs
        *** that only includes versions that contain data in database (ie exclude old deleted stuff)
    	*** *************************************************
        if !mi("`lookup_versions'") {
            # delim ;
            local query = "
                select compare_version_status, cv.compare_version_id, gbd_process_name, gbd_process_version_note
                from gbd.compare_version_output cvo
                join 
                gbd.compare_version cv using (compare_version_id)
                join
                gbd.compare_version_status cvs using (compare_version_status_id)
                join
                gbd.gbd_process_version gpv using (gbd_process_version_id)
                join
                gbd.gbd_process gp using (gbd_process_id)
                where compare_version_status_id in (1,2)
                order by compare_version_status, compare_version_id ";
            odbc load, exec(`"`query'"') `gbd_string' clear;
            # delim cr 
            cd `"`old_dir'"'
            exit
        }

       	*** *************************************************
    	*** if lookup_tables option specified, return a view of all output tables not associated with
        *** a compare version. For example, como before the dalynator makes a compare_version.
        *** (Only includes output tables with data, to drop empty tables)
    	*** *************************************************

        if !mi("`lookup_tables'") {
            # delim ;
            local query = "
               SELECT gbd_process_version_note, table_name, create_time
               FROM gbd.gbd_process_version gpv
               JOIN
               (SELECT table_name, table_rows, create_time, substring_index(table_name,'_v',-1) as gbd_process_version_id 
                    FROM information_schema.tables) it using (gbd_process_version_id)
               left JOIN
               gbd.compare_version_output cvo using (gbd_process_version_id)
               WHERE 
               cvo.compare_version_id IS NULL 
               and table_rows > 100
               ORDER BY create_time desc ";
            odbc load, exec(`"`query'"') `gbd_string' clear;
            # delim cr 
            cd `"`old_dir'"'
            exit
        }

    	*** *************************************************
    	*** set intelligent defaults for "all" option
    	*** *************************************************
    
        // get gbd_round_id from gbd_round
    	#delim ;
    	odbc load, exec("
        select gbd_round_id from shared.gbd_round where gbd_round = `gbd_round'
    	") `shared_string' clear ; 
        #delim cr
        levelsof gbd_round_id, local(gbd_round_id) clean
    
    	// set demographic defaults for "all"
    	if "`location_id'" == "all" {
            // if querying 2013 results, use gbd reporting hierarchy
            // otherwise, use cod and outputs location set
            if `gbd_round' == 2013 local location_set_id = 1 
            if `gbd_round' >= 2015 local location_set_id = 35 
    		#delim ;
    		odbc load, exec("
    		call shared.view_location_hierarchy_history (shared.active_location_set_version(`location_set_id',`gbd_round_id'))
    		") `shared_string' clear ;
    		#delim cr		
    		levelsof location_id, local(location_id) clean
    	}
    	// years
    	if "`year_id'" == "all" {
            if "`gbd_round'" == "2015" local year_id = "1990 1995 2000 2005 2010 2015" 
            if "`gbd_round'" == "2013" local year_id = "1990 1995 2000 2005 2010 2013" 
    	}
    
    	// age_groups (1-27)
    	if "`age_group_id'" == "all" {
    		#delim ;
    		odbc load, exec("
    		SELECT 
    			age_group_id
    		FROM
    			shared.age_group
    		JOIN
    			shared.age_group_set_list USING (age_group_id)
    		JOIN
    			shared.age_group_set USING (age_group_set_id)
    		WHERE
    			age_group_set_id = 2
    		") `shared_string' clear ;
    		#delim cr
    		levelsof age_group_id, local(age_group_id) clean
    	}
    	// sexes
    	if "`sex_id'" == "all" {
    		local sex_id = "1 2 3"
    	}
    	// causes
        // if not a numlist, it's one of a few special keywords
        if !mi("`cause_id'") & !regexm("`cause_id'", "^[0-9 ]") {
            // get all causes from current active cause_set_version_id for cause set specified (defaults to gbd reporting)
    		#delim ;
    		odbc load, exec("
    		call shared.view_cause_hierarchy_history (shared.active_cause_set_version(`cause_set_id',`gbd_round_id')) 
    		") `shared_string' clear ;
    		#delim cr

            // return subset of causes depending on keyword
            if "`cause_id'" == "all" {
    		    levelsof cause_id, local(cause_id) clean
            }
            else if regexm("`cause_id'", "^lvl[1-3]$") {
                local lvl = substr(strreverse("`cause_id'"), 1, 1) // is this the easiest way to get last element of string?
    		    levelsof cause_id if level == `lvl', local(cause_id) clean
            }    
            else if regexm("`cause_id'", "^lvl4$|^most_detailed$") {
    		    levelsof cause_id if most_detailed, local(cause_id) clean
            }    
            else {
                di as error "cause_id keyword incorrectly specified. Expected all, lvl1, lvl2, lvl3, most_detailed"
                exit(1)
            }

    	}
    
        // metrics
        // "all" is number, rate, percent
    	if "`metric_id'" == "all" {
            local metric_id "1 2 3"
    	}
    
        // sequela
        if "`sequela_id'" == "all" {
    	    #delim ;
    	    odbc load, exec("
            select sequela_id from epi.sequela where active_end IS NULL
    	    ") `epi_2015_string' clear ; 
    	    #delim cr		
    	    levelsof sequela_id, local(sequela_id) clean
        }

    	// risks
        if inlist("`rei_id'", "risks", "etiologies", "impairments", "injuries", "all") {
            // these keywords means REI_ids will be either all etiolgoies, all risks, all imps, all injuries.
            // or union of those sets
    	    if "`rei_id'" == "risks"       local rei_sets = "2"
    	    if "`rei_id'" == "etiologies"  local rei_sets = "3"
    	    if "`rei_id'" == "impairments" local rei_sets = "4"
    	    if "`rei_id'" == "injuries"    local rei_sets = "7"
    	    if "`rei_id'" == "all"         local rei_sets = "2 3 4 7"

            // this could be a one iteration loop
            foreach rei_set of local rei_sets {
    	    	#delim ;
    	    	odbc load, exec("
    	    	call shared.view_rei_hierarchy_history (shared.active_rei_set_version(`rei_set',`gbd_round_id')) 
    	    	") `shared_string' clear ; 
    	    	#delim cr		
                count
    	    	if `r(N)' > 0 {
                    levelsof rei_id, local(rei_set_`rei_set') clean
                }
    	    }
            local rei_id `rei_set_2' `rei_set_3' `rei_set_4' `rei_set_7'
        }

    	// rank level
    	if "`rank_level'" == "all" {
    		local rank_level = "2 3 4"
    	}

    	*** **************************************************
    	*** Display each set of parameters
    	*** **************************************************
        # delim ;
        local args = " topic drop_restrictions measure_id version gbd_round location_id year_id year_start_id year_end_id
        metric_id age_group_id sex_id cause_id rei_id sequela_id rank rank_level";
        # delim cr

        noi di "Arguments used: "
        noi di "--------- "
        foreach arg of local args {
            if !mi("``arg''") {
                noi di "`arg': "
                noi di "``arg''"
                noi di "---"
                noi di " "
            }
        }
            
    	*** **************************************************
    	*** create demographics and measures template to account
    	*** properly for missingness
    	*** **************************************************
    	
    	// import config dataset
    	import delimited using "./get_outputs_helpers/template_map.csv", clear varnames(1) 
    	
    	// make templates for cartesian product
    	forvalues i = 1/`=_N' {
    		preserve
    			local table_name = table_name[`i']
    			local id_col = id_col[`i']
    			local name_col = name_col[`i']
    			local database = database[`i']
    			local server = server[`i']
    			di "`id_col'"
    			query_table, table_name(`table_name') columns(`id_col' `name_col') ///
    						 database(`database') server(`server') clear
    			if !mi("``id_col''") keep_in `id_col', keep_list(``id_col'')
                count
    			if `r(N)' == 0 & "`rei_id'" != "0" {
    				di as error "error `id_col' outside of allowed range"
    				error(1)
    			}
                if !mi("`debug'") {
                    noi {
                        di "cartesian template elements:"
                        di "table_name: `table_name'" 
                        di "`id_col': ``id_col''"
                    }
                }
    			gen cartesian = 1
    			tempfile `table_name'
    			save ``table_name'', replace
    		restore
    	}
    
        // make template for year ranges
        // based on input year ranges. Need to revisit this logic
        clear
        set obs 1
        gen year_start_id = .
        gen year_end_id = .
        local n : word count `year_start_id'
        forvalues i = 1/`n' {
            count
            local new_row_idx = `_N' + 1
            set obs `new_row_idx'
            local yr_start : word `i' of `year_start_id'
            local yr_end : word `i' of `year_end_id'
            replace year_start_id = `yr_start' in `new_row_idx'
            replace year_end_id = `yr_end' in `new_row_idx'
        }
        gen cartesian = 1
        drop if year_start_id == . // one row is null, need to drop it
        tempfile year_ranges
        save `year_ranges'
    
    	// make cause sequela template
        /*
    	if "`topic'" == "sequela" { // todo: review 2015 epi schema for sequelae prevalence
    		query_table, table_name(sequela) columns(sequela_id cause_id sequela_name) ///
    					 database(epi) server(modeling-epi-db) clear		
    		if !mi("`sequela_id'") keep_in sequela_id, keep_list(`sequela_id')
    		if !mi("`cause_id'") keep_in cause_id, keep_list(`cause_id')
    		count 
    		if `r(N)' == 0 {
    			di as error "error sequela_id outside of allowed range"
    			error(1)
    		}
    		tempfile sequela
    		save `sequela', replace
    		
    		// reset cause and sequela id lists
    		levelsof sequela_id, local(sequela_id) clean
    		levelsof cause_id, local(cause_id) clean
    	}
        */
    	// make rank level template
    	if !mi("`rank'")  {
    		// for risk ranks
    		if "`topic'" == "rei" {
                // todo: these rank maps are from 2013. Need to either update csv or find a better way to generate them.
                // Possibly ranking code should post these maps in an easy to grab spot, since the map could change
                // with different versions of results if cause or risk hierarchy changes?
                import delimited using "./get_outputs_helpers/rank_rei_map.csv", clear
    			keep_in rei_id, keep_list(`rei_id')
    			keep_in rank_level_id, keep_list(`rank_level')
                count
                if `=_N' == 0 {
                    di as error "The risks specified (`rei_id') aren't ranked at rank_level `rank_level'"
                    }
                if !mi("`debug'") {
                    noi {
                        di `"rei_id before filtering using rank_map: `rei_id'"'
                        di `"rei_id after filtering using rank_map: "'
    			        levelsof rei_id, local(rei_id) clean
                        }
                    }
                // reset rei_id local, because we want to drop any reis from the 
                // rei template if they're not present at the requested rank_level
    			levelsof rei_id, local(rei_id) clean
    		}
    		// for cause ranks
    		else if "`topic'" == "cause" {
                import delimited using "./get_outputs_helpers/rank_cause_map.csv", clear
    			keep_in cause_id, keep_list(`cause_id')
    			keep_in rank_level_id, keep_list(`rank_level')
                count
                if `=_N' == 0 {
                    di as error "The causes specified (`cause_id') aren't ranked at rank_level `rank_level'"
                    }
    			levelsof cause_id, local(cause_id) clean
    		}
    		else {
    			di as error "Only causes or risks are ranked"
    			error(1)
    		}
    		tempfile rank_template
    		save `rank_template', replace
    
    	}
    	
    	// make cause risk template from shared.cause_risk
    	if "`topic'" == "rei" { 
            odbc load, exec("select rei_id, rei_name from shared.rei") `gbd_string' clear
            tempfile rei_names
            save `rei_names'

    		#delim ;
            local risk_cause = "
                (select rei_id, cause_id
                from shared.cause_risk where gbd_round_id = `gbd_round_id')
                ";
            local eti_cause = "
                (select rei_id, cause_id
                from shared.cause_etiology where gbd_round_id = `gbd_round_id')
                ";
            local imp_cause = "
                (select rei_id, cause_id
                from epi.reporting_group)
                ";
    		odbc load, exec("
                `risk_cause'
                union all
                `eti_cause'
                union all
                `imp_cause'") `epi_2015_string' clear ; 
    		#delim cr		
    		if !mi("`rei_id'") keep_in rei_id, keep_list(`rei_id')
    		if !mi("`cause_id'") keep_in cause_id, keep_list(`cause_id')
    		count 
    		if `r(N)' == 0 & "`rei_id'" != "0" {
    			di as error "error rei_id outside of allowed range"
    			error(1)
    		}
            // join on rei names. This is unusual for cartesian templates but that's the only
            // way I can figure out how to preserve rei_names in the final results, for missing
            // reis
            merge m:1 rei_id using `rei_names', keep(1 3) nogen
    		tempfile rei
    		save `rei', replace
    	}
    
    	
    	*** **************************************************
    	*** create restrictions template
    	*** **************************************************
    	
    	if !mi("`drop_restrictions'") {
    	
    		// sex
    		get_restrictions, type(sex) cause_id(`cause_id') sex_id(`sex_id') gbd_round(`gbd_round') clear 
    		tempfile sex_restrict
    		save `sex_restrict', replace
    		
    		// measure
    		get_restrictions, type(measure) cause_id(`cause_id') measure_id(`measure_id') gbd_round(`gbd_round') clear
    		tempfile measure_restrict
    		save `measure_restrict', replace
    		
    		get_restrictions, type(age) cause_id(`cause_id') measure_id(`measure_id') gbd_round(`gbd_round') clear
    		tempfile age_restrict
    		save `age_restrict', replace
    	}
    	
        /*
        The 2015 outputs database is comprised of many small tables created by
        different generating processes (ie como or dalynator).  The
        compare_version_output table is the guide that says which table to look in
        depending on measure, template (ie single or multi year or rank) and
        compare_context. Compare_context is a viz tool construct and can be cause,
        etiology, risk, or impairment. The viz tool only reports results for one
        context at a time, but get_outputs could possibly given parameters that
        span multiple contexts. So this will be a bit more complicated.
        
        Here's the algorithm:
        
        If topic area is cause, context is cause.  If topic area is rei, context is
        one of the other 3. Need to look at all rei_ids and determine which context
        each belongs to.  If year ranges are requested, template is multi-year.
        Otherwise, if ranks are specified, template is ranks.  Otherwise, template is
        single-year.
        
        Using the above info + measures, we can create a template containing only the
        tables we need to query. Then we can just loop through each row and query each
        table and concatenate the results.
        
        */
    
        
        *** *************************************************
        *** create mappings between cause/rei_ids and contexts
        *** *************************************************
        if "`topic'" == "cause" {
            local cause_id_str = subinstr(`"`cause_id'"', " ", ",",.)
        }
        else if "`topic'" == "rei" {
            // topic is rei -- need to assign each rei_id to risk/eti/imp/inj
            
            // first, define which rei_set_id belongs to which context
            local Risk_set_id = 2
            local Etiology_set_id = 3
            local Impairment_set_id = 4
            local Injury_set_id = 7
        
            // now, for each set, create a local containing the comma sepparated rei ids we care about
            // (so it may be an empty local. The emptiness will be checked later while filtering compare_version_output table)
            local reis_to_keep_str = subinstr(`"`rei_id'"', " ", ",",.)
            foreach context in Risk Etiology Impairment Injury {
                /* there's no sproc for view_rei_hierarchy_history yet, so we'll write a custom query
                until that sproc is created
                */
                #delim ;
        	    odbc load, exec("
        	        select rei_id from shared.rei_hierarchy_history 
                    where rei_set_version_id = (select shared.active_rei_set_version(``context'_set_id',`gbd_round_id')) 
        	    ") `shared_string' clear ; 
                #delim cr
                // no gbd2013 rei set for injuries, so only try levelsof if >0 rows
                count
                if `r(N)' > 0 {
                    levelsof rei_id if inlist(rei_id,`reis_to_keep_str'), local(`context'_id_str) sep(,)
                }
                if !mi("`debug'") {
                    noi di `"`context'_id_str: ``context'_id_str'"'
                    }
            }
        }
        
        *** *************************************************
        *** determine "template" (aka ranks, multi-year, or single year) and create sql filter
        *** *************************************************
        if !mi("`rank'") {
            local ranks_filter = "template_name like '%rank'"  
            }
        else if !mi("`year_id'") {
            local single_filter = "template_name like '%single_year'" 
            }
        else if !mi("`year_start_id'") {
            local multi_filter = "template_name like '%multi_year'" 
            }
        else {
            noisily di as error "Template could not be determined. Ranks, year_id, and year_start not specified"
            error (198)
            }
        
        *** *************************************************
        *** make filters for compare_version_output and output queries
        *** *************************************************
        
        // create demographic filter (except year, that's later for performance reasons)
        local demo_filters = `""'
        foreach filter in location_id age_group_id sex_id {
        	if "``filter''" != "all" {
        		local filter_list = subinstr("``filter''"," ",",",.)
        		local `filter'_filter = "and o.`filter' in (`filter_list')"
        		local demo_filters = `"`demo_filters'"' ///
        			+ `" and "' + `"o.`filter' in (`filter_list')"' //"
        	}
        }

    
        // create metric filter
        local filter_list = subinstr("`metric_id'"," ",",",.)
        local metric_filter = `" and "' + `"o.metric_id in (`filter_list')"' //"
    
        // create measure filter
        // note: this should be used first in output query so it's missing "and"
        local filter_list = subinstr("`measure_id'"," ",",",.)
        local measure_filter = `"measure_id in (`filter_list')"' //"
        
        // create filter on cause_id
        if !mi("`cause_id'") & "`topic'" != "sequela" {
        	local filter_list = subinstr("`cause_id'"," ",",",.)
        	local cause_filter = `" and "' + `"o.cause_id in (`filter_list')"' //"
        }
        
        // create risk filter
        if !mi("`rei_id'") {
            local filter_list = subinstr("`rei_id'"," ",",",.)
            local risk_filter = `" and "' + `"o.rei_id in (`filter_list')"' //"
        } 
    
        // create sequela filter
        if !mi("`sequela_id'") {
        	local filter_list = subinstr("`sequela_id'"," ",",",.)
        	local sequela_filter = `" and "' + `"o.sequela_id in (`filter_list')"' //"
        }
        
        // create rank filter
        if !mi("`rank_level'") {
            local filter_list = subinstr("`rank_level'"," ",",",.)
            local rank_level_filter = `" and "' + `"o.rank_level_id in (`filter_list')"' //"
        } 
    

        *** *************************************************
        *** create list of tables to query
        *** *************************************************
        if !mi("`table'") {
            if !mi("`debug'") noi di `"tables explicitly specified: `table'"'
            local tables_to_query `"`table'"'
        }
        else {
            if !mi("`debug'") noi di `"tables_to_query args: `"`ranks_filter'"'| `"`multi_filter'"'| `"`single_filter'"'| `"`measure_filter'"'| `"`version'"'| `"`gbd_string'"'| `"`rei_id'"'| `"`Risk_id_str'"'| `"`Etiology_id_str'"'| `"`Impairment_id_str'"'| `"`Injury_id_str'"'| `"`debug'"'| `"`gbd_round_id'"'| `"`sequela_id'"' "'
            tables_to_query `"`ranks_filter'"' `"`multi_filter'"' `"`single_filter'"' `"`measure_filter'"' `"`version'"' `"`gbd_string'"' `"`rei_id'"' `"`Risk_id_str'"' `"`Etiology_id_str'"' `"`Impairment_id_str'"' `"`Injury_id_str'"' `"`debug'"' `"`gbd_round_id'"' `"`sequela_id'"' 
            local tables_to_query = "`r(tables)'"
        }

        ** *************************************************
        *** Build cartesian product of demographic variables + measure (to join on results to show missingness)
        *** *************************************************
    
    	// build cartesian template
        clear
        if !mi("`rank'") {
    	    gen rank_level_id = .
    	    foreach rlevel of local rank_level {
    	    	set obs `=_N + 1'
    	    	replace rank_level_id = `rlevel' in `=_N'
    	    }
    	    gen cartesian = 1
            joinby cartesian using `location'
            }
        else {
    	    use `location', clear
            }
    	joinby cartesian using `age_group'
    	joinby cartesian using `sex'
    	joinby cartesian using `cause'
    	joinby cartesian using `measure'
    	joinby cartesian using `metric'
        if !mi(`"`year_id'"') {
    	    joinby cartesian using `year' 
        }
        else {
    	    joinby cartesian using `year_ranges' 
            }
    	if "`topic'" == "rei" joinby cause_id using `rei' 
        //if "`topic'" == "sequela" joinby cause_id using `sequela'
    	drop cartesian
    	compress
        if !mi("`debug'") {
            noi {
                di "cartesian template values:"
                foreach var of varlist * {
                    di "`var':"
                    levelsof `var', clean
                    }
                }
            }
    	tempfile cartesian_template
    	save `cartesian_template', replace
        
        
        *** *************************************************
        *** Query each relevant table
        *** *************************************************
        clear
        tempfile results
        save `results', emptyok

        // Instead of having year_id (or year start/end) inside the demographic filter, we're
        // going to query each table once for each year argument. This is to prevent a problem
        // that arises where the query opimizer decides to ignore the index if the number of 
        // rows requested is too large. Querying by year should help reduce the odds of that 
        // happening.
        if !mi("`year_id'") local num_year_args : list sizeof year_id
        if !mi("`year_start_id'") local num_year_args : list sizeof year_start_id
        
        forvalues i = 1/`num_year_args' {

                // get specific year arguments from the general list of year args
                if !mi("`year_id'") local this_year : word `i' of `year_id'
                if !mi("`year_start_id'") {
                    local this_year_start : word `i' of `year_start_id'
                    local this_year_end : word `i' of `year_end_id'
                }

                // create year filter for this time through the loop
                if !mi("`year_id'") local this_year_filter "and o.year_id = `this_year'"
                if !mi("`year_start_id'") {
                    mata: make_multi_year_clause("this_year_start", "this_year_end", "this_year_filter")
                    local this_year_filter "and `this_year_filter'"
                }

                foreach tbl of local tables_to_query {

            
                    // right now, we query every table for all rei_id arguments, even if table is a risk table and some rei arguments
                    // are eti or impairments. TODO: use `context'_rei_id_str local to only query each table using appropriate
                    // rei ids. Not a big deal, but more efficient
                    if !mi("`risk_filter'") {
                        local maybe_rei_id_filter = `"`risk_filter'"'
                        }
                    
                    // create list of columns to select
                    // (split into 2 just to avoid really long line)
                    local constant_cols1  "o.measure_id,measure,o.location_id,location_name"
                    local constant_cols2  ",o.age_group_id,age_group_name,o.sex_id,sex,val,upper,lower"
                    local constant_cols   "`constant_cols1'`constant_cols2'"

                    // output tables will either have cause, or sequela
                    if !mi("`sequela_id'") {
                        local gbd_id_cols ",o.sequela_id" // sequela name is joined after the fact (diff server)
                        local maybe_sequela_filter = `"`sequela_filter'"'
                    }
                    else {
                        local gbd_id_cols ",o.cause_id,cause_name"
                        local maybe_cause_table "STRAIGHT_JOIN shared.cause c ON o.cause_id = c.cause_id"
                    }
                     
                    // rank tables don't have metric_id because they're always only metric = rank
                    // so if we're not querying ranks, we'll need to join on metric table
                    if !mi("`rank'") {
                        local maybe_rank_cols = ",o.rank_level_id"
                        }
                    else {
                        // if not ranks, add metric_id specific bits to query
                        local metric_cols = ",o.metric_id,metric_name"
                        local maybe_metric_table = "STRAIGHT_JOIN gbd.metric mt ON o.metric_id = mt.metric_id"
                        local maybe_metric_filter = `"`metric_filter'"'
                        }

                    if  "`topic'" == "rei" {
                        local maybe_rei_cols = ",o.rei_id,rei_name" 
                        local maybe_rei_table = "STRAIGHT_JOIN shared.rei r ON o.rei_id = r.rei_id"
                        }
                    if !mi("`year_start_id'") {
                        local year_cols = ",o.year_start_id,o.year_end_id"
                        }
                    else {
                        local year_cols = ",o.year_id"
                        }
            
                    // query the table and append to results
                    clear
                    #delim ;
                    local query = "
                    SELECT 
                        `constant_cols'
                        `gbd_id_cols'
                        `metric_cols'
                        `year_cols'
                        `maybe_rank_cols'
                        `maybe_rei_cols'
                        `maybe_burden_cols'
                    FROM 
                        gbd.`tbl' o
                        STRAIGHT_JOIN shared.measure m ON o.measure_id = m.measure_id
                        `maybe_cause_table'
                        STRAIGHT_JOIN  shared.location l ON o.location_id = l.location_id 
                        `maybe_rei_table'
                        STRAIGHT_JOIN shared.age_group ag ON o.age_group_id = ag.age_group_id
                        STRAIGHT_JOIN shared.sex s ON o.sex_id = s.sex_id 
                        `maybe_metric_table'
                    WHERE 
                        o.`measure_filter'
                        `demo_filters'
                        `this_year_filter'
                        `maybe_sequela_filter'
                        `cause_filter' 
                        `maybe_rei_id_filter' 
                        `maybe_metric_filter'
                        `rank_level_filter'";
                    if !mi("`debug'") noi di `"`query'"' ;
                    odbc load, exec("`query'") `gbd_string' ;
                    #delim cr 
                
                    // if querying rank tables, add on metric id and metric name 
                    if !mi("`rank'") {
                        gen metric_id = 4
                        gen metric_name = "Rank"
                        }

                    desc
                    append using `results' // appending on to an ever growing result set is slow. May need to change algorithm
                    save `results', replace
                }
        } 
        use `results', clear
    
    	// confirm results
    	count
    	if `r(N)' < 1 {
    		di as error "no results found"
    		error(1)
    	}

        // for sequelae queries, add in sequela name (in different server) and cause name/id
        /*
        if !mi("`sequela_id'") {
            di in red "grabbing sequela_id info"
            add_sequela_info `"`epi_2015_string'"'	
        }
        */

    	// merge on template
        if !mi("`year_start_id'") {
            local year_id_cols  = "year_start_id year_end_id"
            }
        else {
            local year_id_cols = "year_id"
            }

        foreach arg in rei_id sequela_id {
            if !mi("``arg''") local maybe_`arg' = "`arg'"
        }

        if !mi("`rank'") {
            local maybe_rank_col = "rank_level_id"
            }

        if !mi("`debug'") {
            noi di "Columns before template merge:"
            ds *
            noi di `"`r(varlist)'"' 
            }
        /*
    	merge 1:1 location_id `year_id_cols' age_group_id sex_id measure_id metric_id `maybe_rank_col' `maybe_rei_id' ///
              using `cartesian_template' , nogen
        if mi("`sequela_id'") gen sequela_id = 0

        // if we requested ranks, the cartesian template has another metric that we need to drop
        if !mi("`rank'") keep if metric_id == 4
        */
    
    	*** **************************************************
    	*** merge to make final dataset
    	*** **************************************************
    	
    	if "`drop_restrictions'" == "drop_restrictions" {
    		merge m:1 cause_id sex_id using `sex_restrict', keep(1) nogen
    		merge m:1 cause_id measure_id using `measure_restrict', keep(1) nogen
    		merge m:1 cause_id measure_id age_group_id using `age_restrict', keep(1) nogen
    	}
    	
    	// format
        if "`topic'" == "rei" {
            local maybe_rei_vars = "rei*"
            }

        if "`topic'" == "rank" {
            local maybe_rank_vars = "rank*"
            }
    
    	order measure* sequela* `maybe_rei_vars' `maybe_rank_vars' location* year* age* sex* metric* 
    	sort measure* sequela* `maybe_rei_vars' `maybe_rank_vars' location* year* age* sex* metric*
    	
    	// change back directory
    	cd "`old_dir'"
    }	
end


