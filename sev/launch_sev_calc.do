/*
Launch one job for each risk.
There's a preprocessing step involving transforming PAF files.
*/
set more off
set rmsg on

local risk_version_id = `1'
local convert_pafs = 0 // if 1, launch qsub jobs to convert pafs to a better format
local run_calc = 1 // if 1, launch qsub jobs to run sev_calc.do
local upload = 0 // if 1, upload to db
local envr = "prod" // prod/test. Determines db to upload to
local compare_version_id = 135 // if upload = 1, this will assign the results to a particular compare_version_id
local username = c(username)
if "`username'" == "strUser" {
    local code_dir = "/ihme/code/strUser/under_development/sev_calculator"
}
else if "`username'" == "strUser" {
    local code_dir = "/homes/strUser/sev_calculator"
    }
else {
    di as error "code_dir not found for user `username'"
    error(1)
}

if `convert_pafs' {
    // launch parallel jobs (1 for each country) to take paf dtas and make hdf
    // so we can read them in faster (due to random access)
    // (This step takes about 10 minutes, and only needs to be ran if a new 
    // version of PAFs is created)

    local base_dir = "/ihme/centralcomp/pafs/`risk_version_id'"
    local hdf_dir = "`base_dir'/tmp_sev"

    // if hdf dir doesn't exists, make it (and one for YLDs).
    // (stata doesn't have "capture confirm dir", so use mata)
    mata: st_local("dir_exists", strofreal(direxists(st_local("hdf_dir"))))
    if !`dir_exists' {
        mkdir "`hdf_dir'"
        mkdir "`hdf_dir'/yld"
    }
    
    // Launch one job per country. Get all valid country ids by parsing
    // PAF dta file names in base_dir
    mata:
        file_list = dir(st_local("base_dir"), "files", "*.dta")
        location_ids = J(length(file_list), 1, "") // initialize list for results
        t = tokeninit("_") // mata's token parsing object. Means parse on underscore
        for (i=1; i<=length(file_list); i++) {
            file_name = file_list[i]
            tokenset(t, file_name)
            split_tokens = tokengetall(t)
            location_id = split_tokens[1] // location_id is first element of each file name
            location_ids[i] = location_id
        }

        // since files are stored by country_year, deduplicate list of location_ids
        location_ids = uniqrows(location_ids)

        // now turn list of location ids into string to feed back to stata
        result = ""
        for (i=1; i<=length(location_ids); i++) {
            result = location_ids[i] + " " + result  
        }

        st_local("location_ids", result)
   end

   // submit jobs
   local py_shell = "/home/j/WORK/10_gbd/00_library/functions/utils/python_shell.sh"
   local slots = 20 
   local mem = `=2*`slots''
   foreach loc_id of local location_ids {
       !qsub -P proj_rfprep -N "hdf_`loc_id'" ///
       -o /share/temp/sgeoutput/`username'/output -e /dev/null ///
       -l mem_free=`mem'G -pe multi_slot `slots' ///
       "`py_shell'" ///
       "`code_dir'/core/pafs_to_hdf.py" ///
       `risk_version_id' `loc_id'
   }
}

import delimited "`code_dir'/risk_cont.csv", clear
keep if continuous != .
keep risk_id continuous
levelsof risk_id, local(risk_ids)
local paf_version_id `risk_version_id'

if `run_calc' {

  // submit jobs
  local stata_shell = "/home/j/WORK/10_gbd/00_library/functions/utils/stata_shell.sh"
  local slots = 60 
  local mem = `=2*`slots''
  foreach risk_id of local risk_ids {
          preserve
            keep if risk_id == `risk_id'
            levelsof continuous, local(continuous) 
            !qsub -P proj_rfprep -N "sev_`risk_id'" ///
              -o /share/temp/sgeoutput/`username'/output -e /dev/null ///
              -l mem_free=`mem'G -pe multi_slot `slots' ///
              "`stata_shell'" ///
              "`code_dir'/sev_calc.do" ///
              "`risk_id' `paf_version_id' `continuous'"
         restore
  }

}

if `upload' {
        // Periodically check if all output files exist. Once they do, upload
        local upload_dir = "/ihme/centralcomp/sev/`paf_version_id'/summary/to_upload"
        local expected_finished: list sizeof risk_ids
        while 1 {
           local finished_files: dir "`upload_dir'" files "*.csv"
           local num_finished: word count "`finished_files'"
           if `num_finished' >= `expected_finished' {
               run "`code_dir'/core/upload/begin_upload.ado"
               di "beginning upload at `c(current_time)'"
               begin_upload, paf_version(`paf_version_id') file_list(`"`finished_files'"') upload_dir("`upload_dir'") code_dir("`code_dir'") envr("`envr'") compare_version_id(`compare_version_id')
               continue, break
           }
           else {
               sleep 60000
           }
        }

        di "finished upload at `c(current_time)'"
}
//END
