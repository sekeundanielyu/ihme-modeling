
rm(list=ls())
if (Sys.info()[1] == 'Windows') {
  username <- ""
  root <- "J:/"
  workdir <-  paste("/ihme/code/risk/",username,"/drugs_alcohol/",sep="")
  source("J:/Project/Mortality/shared/functions/get_locations.r")
} else {
  username <- Sys.getenv("USER")
  root <- "/home/j/"
  workdir <-  paste("/ihme/code/risk/",username,"/drugs_alcohol/",sep="")
  source("/home/j/Project/Mortality/shared/functions/get_locations.r")
}

#################
## set up options
#################
mycores <- 6
injcores <- 4 # Injuries code is not well parallelized within each job using mclapply like others, so don't bother grabbing as many cores
myB <- 1000      ## change to 10 for test runs
myverbose <- TRUE
share <- T      ## directs to get exposure from share or J drive- but should always be share, J drive just for troubleshooting options
mysavedraws <- myB     ## change to 10 with the other one
errout_paths <- paste0("-o /share/temp/sgeoutput/",username,
                       "/output -e /share/temp/sgeoutput/",username,"/errors ")
proj <- "-P proj_custom_models "
vvv <- 5 # Version to save

###############################
## set up directories both to pass to jobs and to use in this script for deletions
###############################
prescale_dir <- paste0(ifelse(share,"/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                              paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"prescale")
postscale_dir <- paste0(ifelse(share,"/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/exp/",
                               paste0(root,"WORK/05_risk/risks/drugs_alcohol/data/exp/")),"postscale")
code.dir <- workdir
data.dir <- paste0(postscale_dir)
temp.dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp"
out.dir <- "/ihme/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output"

# graph.dir <- "/home/j/WORK/"
rshell <- paste0(code.dir,"rshell.sh") ## should switch to using the new shell below and test when possible
rshell_new <- paste0(code.dir,"rshell_new.sh") ## Uses an updated version of R to get updated version of the uniroot function
statashell <- paste0(code.dir,"stata_shell.sh")
statashell_mp <- paste0(code.dir,"stata_shell_mp.sh")
pythonshell <- paste0(code.dir,"python_shell.sh")


cause.cw.file <- paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/meta/cause_crosswalk.csv")
sexes <- c(1, 2)
ages <- c(15,20,25,30,35,40,45,50,55,60,65,70,75,80)
age_group_ids <- c(8,9,10,11,12,13,14,15,16,17,18,19,20,21)
## write agemap file from gbd age group ids to age until we recode all steps to use age_group_id
agemap <- data.frame(age=ages,age_group_id=age_group_ids)
if (!file.exists("/home/j/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv")) write.csv(agemap,"/home/j/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv",row.names=F)
years <- c(1990, 1995, 2000, 2005, 2010, 2015)
causes <- c("chronic", "russia")


## Grab locations for parallelizing d06
## Query using central function get_location_metadata
# system(paste("qsub -N get_locations ", mycores, " -l mem_free= ", 2*mycores, "G stata_shell.sh ", code.dir,"/get_locations_for_paf.do"))
# ## wait until file presentf
# while (!file.exists("/home/j/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/paf_locations.csv")) {
#   print(paste0("Waiting for locations file"))
#   Sys.sleep(30)
# }
location_list <- read.csv("/home/j/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/paf_locations.csv", stringsAsFactors = FALSE)
locations <- unique(location_list$location_id)

## allow for running certain steps but not others
do03_analysis <- 1
do_ihdisanalysis <- 1
do_russiaihdis <- 1
do04_inj <- 0
do04_assault <- 0
do04_mvaoth <- 0
do05_gather <- 0
do06_rescale <- 0
do07_save_results <- 0
errout <- TRUE
test <- FALSE
onlycompile <- FALSE
onlyrescale <- FALSE


jlist1 <- c()
# Launch the main set of analysis code..
if (do03_analysis == 1) {
  rscript <-  paste0(code.dir, "/03_0_analysis.R")
  for (yyy in years) {
    for (sss in sexes) {
      for (aaa in age_group_ids) {
        for (ccc in causes) {
          file.remove(paste0(temp.dir,"/AAF_",yyy,"_a",aaa,"_s",sss,"_",ccc,".csv"))
          
          jname <- paste("alc_paf_", yyy, "_s", sss, "_a", aaa, "_", ccc, sep="")
          sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", mycores, " ", "-l mem_free=", 2 * mycores, "G ",ifelse((errout & yyy == 1990 & sss == 2),paste0(errout_paths," "),""))
          args <- paste(yyy, aaa, sss, ccc, code.dir, data.dir, temp.dir, mycores, myverbose, myB, mysavedraws, sep=" ")
          
          system(paste(sys.sub, rshell_new, rscript, args))
          #print(paste(sys.sub,rshell,rscript,args))
          jlist1 <- c(jlist1, jname)
        }
      }
    }
  }
}

# Launch the ihd and ischemic stroke code
if (do_ihdisanalysis == 1) {
  rscript <- paste0(code.dir,"/ihdisAnalysis.R")
  for (ccc in c("ihd","ischemicstroke")) {
    for (yyy in years) {
      for (sss in sexes) {
        for (aaa in age_group_ids) {
          file.remove(paste0(temp.dir,"/AAF_",yyy,"_a",aaa,"_s",sss,"_",ccc,".csv"))
          
          jname <- paste("alc_paf_", yyy, "_s", sss, "_a", aaa, "_", ccc, sep="")
          sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", mycores/2, " ", "-l mem_free=", 2 * mycores/2, "G ",ifelse((errout),paste0(errout_paths," "),""))
          args <- paste(yyy, aaa, sss, ccc, code.dir, data.dir, temp.dir, mycores, myverbose, myB, mysavedraws, sep=" ")
          
          system(paste(sys.sub, rshell_new, rscript, args))
          jlist1 <- c(jlist1, jname)
        }
      }
    }
  }
}


# Years and ages for testing
# years <- c(1995,2010)
# ages <- c(20)
# sexes <- c(2)


# Launch new Russia IHD/Ischemic stroke analysis code
if (do_russiaihdis == 1) {
  rscript <- paste0(code.dir,"/russ_ihd_is_Analysis.R")
  ccc <- "russ_ihd_is"
  for (yyy in years) {
    for (sss in sexes) {
      for (aaa in age_group_ids) {
        file.remove(paste0(temp.dir,"/AAF_",yyy,"_a",aaa,"_s",sss,"_",ccc,".csv"))
        
        jname <- paste("alc_paf_", yyy, "_s", sss, "_a", aaa, "_rihdis", sep="")
        sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", mycores/4, " ", "-l mem_free=", 2 * mycores/4, "G ",ifelse((errout & yyy == 1990 & sss == 2),paste0(errout_paths," "),""))
        args <- paste(yyy, aaa, sss, ccc, code.dir, data.dir, temp.dir, mycores, myverbose, myB, mysavedraws, sep=" ")
        
        system(paste(sys.sub, rshell_new, rscript, args))
        jlist1 <- c(jlist1, jname)
      }
    }
  }
}


# Launch the injuries to self code
if (do04_inj == 1) {
  jlist2 <- c()
  ccc <- "inj_self"
  rscript <- paste0(code.dir, "/04_1_injuriesself.R")
  for (yyy in years) {
    for (aaa in age_group_ids) {
      file.remove(paste0(temp.dir,"/AAF_",yyy,"_a",aaa,"_s",sss,"_",ccc,".csv"))
      
      jname <- paste("alc_paf_", yyy, "_a", aaa, "_injslf", sep="")
      sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", injcores, " ", "-l mem_free=", 2 * injcores, "G ",ifelse((errout & yyy == 1990),paste0(errout_paths," "),""))
      args <- paste(yyy, aaa, data.dir, temp.dir, myB, mysavedraws, sep=" ")
      
      system(paste(sys.sub, rshell_new, rscript, args))
      jlist2 <- c(jlist2, jname)
    }
  }
}

# Launch the assault and MVA injuries to others code
jlist3 <- c()
rscript.assault <- paste0(code.dir, "/04_2_assault.R")
rscript.mvaoth <- paste0(code.dir, "/04_2_mva_others.R")
for (yyy in years) {
  # Assault
  if (do04_assault == 1) {
    if (do04_inj == 0) {
      jlist2 <- "fake0000"
    }
    ccc <- "inj_aslt"
    file.remove(paste0(temp.dir,"/AAF_",yyy,"_",ccc,".csv"))
    
    jname <- paste("alc_paf_", yyy, "_injaslt", sep="")
    sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", injcores, " ", "-l mem_free=", 2 * injcores, "G ",ifelse((errout & yyy == 1990),paste0(errout_paths," "),""),"-hold_jid ", paste(jlist2, collapse=","))
    args <- paste(yyy, data.dir, temp.dir, mysavedraws, sep=" ")
    
    system(paste(sys.sub, rshell_new, rscript.assault, args))
    jlist3 <- c(jlist3, jname)
  }
  
  # Injuries to others
  if (do04_mvaoth == 1) {
    if (do04_inj == 0) {
      jlist2 <- "fake0000"
    }
    ccc <- "inj_mvaoth"
    file.remove(paste0(temp.dir,"/AAF_",yyy,"_",ccc,".csv"))
    
    jname <- paste("alc_paf_", yyy, "_inj_mvaoth", sep="")
    sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", injcores, " ", "-l mem_free=", 2 * injcores, "G ",ifelse((errout & yyy == 1990),paste0(errout_paths," "),"")," -hold_jid ", paste(jlist2, collapse=","))
    args <- paste(yyy, data.dir, temp.dir, mysavedraws, sep=" ")
    
    
    system(paste(sys.sub, rshell_new, rscript.mvaoth, args))
    jlist3 <- c(jlist3, jname)
  }
}


if (do05_gather == 1) {
  ## Delete step 5 results if already existing
  ## This ensures that we don't accidentally miss one set of draws
  dir.create(paste0(out.dir,"/",vvv,"_prescale"))
  dir.create(paste0(out.dir,"/",vvv,"_prescale/ylds"))
  dir.create(paste0(out.dir,"/",vvv,"_prescale/ylls"))
  file.remove(dir(paste0(out.dir,"/",vvv,"_prescale/"),pattern="*.csv",full.names=TRUE))
  file.remove(dir(paste0(out.dir,"/",vvv,"_prescale/ylds"),pattern="*.csv",full.names=TRUE))
  file.remove(dir(paste0(out.dir,"/",vvv,"_prescale/ylls"),pattern="*.csv",full.names=TRUE))
  
  jlist4 <- c()
  ## Launch gather code
  statascript <- paste0(code.dir, "/05_gather_r_version.R")
   for (yyy in years) {
    if (onlycompile) {
      jlist1 <- jlist3 <- "fake0000"
    }
     jname <- paste0("alc_gather_", yyy)
      args <- paste(temp.dir, yyy, cause.cw.file, vvv, out.dir, sep=" ")
      hold <- paste("-hold_jid ", paste(jlist1, collapse=","), " ", paste(jlist3, collapse=","),sep="")
      if (onlycompile) {
        hold <- NULL
      }
      sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", 20, " ", "-l mem_free=", 40, "G ",paste0(errout_paths," "),hold)
      
      print(paste(sys.sub, rshell_new, statascript, "\"", args, "\""))
      if (test) print(paste(sys.sub, rshell_new, statascript, "\"", args, "\"")) else system(paste(sys.sub, rshell_new, statascript, "\"", args, "\""))
      jlist4 <- c(jlist4, jname)
     jnameyear <- jname
#     
    
    ## WITHIN THE YEAR LOOP, SUBMIT SAVING JOBS
    ## resave these large files in location-sex-year in parallel so it's faster
    chunks <- 10
    jlist5 <- c()
    save_script <- paste0(code.dir,"/05b_resave_gather.R")
    for (chunk in 1:chunks) {
      for (mort in c("yll","yld")) {
        args <- paste(temp.dir, yyy, cause.cw.file, vvv, out.dir,chunks,chunk,mort, sep=" ")
        hold <- paste("-hold_jid ", paste(jnameyear,collapse=","),sep="")
        jname <- paste0("alc_locsave_", yyy,"_",chunk,"_",mort)
        sys.sub <- paste0("qsub -N ", jname, " ",proj, "-pe multi_slot ", 6, " ", "-l mem_free=", 12, "G ",paste0(errout_paths," "),hold)
        
        if (test) print(paste(sys.sub, rshell_new, save_script, "\"", args, "\"")) else system(paste(sys.sub, rshell_new, save_script, "\"", args, "\""))
        jlist5 <- c(jlist5, jname)
      }
    }
    print(jlist5)
  }
  
}


if (do06_rescale == 1 ) {
  ## Delete final-stage results if already existing
  ## This ensures that we don't accidentally miss one set of draws
  dir.create(paste0(out.dir,"/",vvv))
  dir.create(paste0(out.dir,"/",vvv,"/ylds"))
  dir.create(paste0(out.dir,"/",vvv,"/ylls"))
  file.remove(dir(paste0(out.dir,"/",vvv),pattern="*.csv",full.names=TRUE))
  file.remove(dir(paste0(out.dir,"/",vvv,"/ylds"),pattern="*.csv",full.names=TRUE))
  file.remove(dir(paste0(out.dir,"/",vvv,"/ylls"),pattern="*.csv",full.names=TRUE))
  
  ## Launch cirrhosis_rescale code
  statascript <- paste0(code.dir, "06_cirrhosis_rescale.do")
  jlist6 <- c()
  for (lll in locations) {
    for (yyy in years) {
      if (onlyrescale) {
        jlist5 <- "fake0000"
      }
      jname <- paste0("alc_rescale", lll, yyy)
      args <- paste(temp.dir, yyy, cause.cw.file, vvv, out.dir, lll, sep=" ")
      hold <- paste("-hold_jid ", paste(jlist5, collapse=","),sep="")
      if (onlyrescale) {
        hold <- NULL
      }
      sys.sub <- paste0("qsub -N ", jname, " ",proj, " -pe multi_slot ", 2, " ", " -l mem_free=", 2 * 2, "G ",ifelse((errout & yyy == 1990),paste0(errout_paths," "),"")," ",hold)
      jlist6 <- c(jlist6, jname)
      #system(paste(sys.sub, statashell, statascript, "\"", args, "\""))
      if (test) print(paste(sys.sub, statashell, statascript, "\"", args, "\"")) else system(paste(sys.sub, statashell, statascript, "\"", args, "\""))
    }
  }
  
  ## Check for the last file in the 05_gather step before checking for 06 done
  ## Checks every ten minutes, since all steps will take a while to go
  if (do05_gather == 1) {
    postfix <- "paf_yll_ZWE_2013_female"
    check <- TRUE
    while(check == FALSE) {
      time <- Sys.time()
      print(paste0("10-min check of 05: ", postfix, " at ", time))
      # check <- dir(paste0(out.dir,"/",vvv,"/",postfix,".csv"))
      check <- file.exists(paste0(out.dir,"/",vvv,"_prescale/",postfix,".csv"))
      if(check == FALSE) {
        Sys.sleep(600) # Pauses for 10 minutes
      }
    }
  }
  
  morts <- c("yll","yld")
  
  for(location in locations) {
    for(sex in sexes) {
      for(year in years) {
        for(mort in morts) {
          check <- TRUE
          postfix <- paste("paf",mort,location,year,sex, sep = "_")
          while(check == FALSE) {
            time <- Sys.time()
            print(paste0("Checking 06: ",postfix, ".csv at ", time))
            check <- file.exists(paste0(out.dir,"/",vvv,"/",postfix,".csv"))
            if(check == FALSE) {
              Sys.sleep(60) # Pauses for 60 seconds if not found
            }
          }  
        }
      }
     }
   }
  print("Success!")
}
morts <- c("yll","yld")

if (do07_save_results == 1) {
  script <- paste0(code.dir, "07_save_results.do")
  holds <- paste("-hold_jid ", paste(jlist6, collapse=","), " ",sep="")
  sys.sub <- paste0("qsub -N saver ",proj, " -pe multi_slot ", mycores, " ", "-l mem_free=", 2*mycores, "G ", holds)
  system(paste(sys.sub, statashell_mp, script))
}

