

# For testing purposes, set argument values manually if in windows
	if (Sys.info()["sysname"] == "Windows") {
	  root <- "J:/"
		arg <- c(1995, 20, 2, "chronic", "C:/Users//Documents/repos/drugs_alcohol", "J:/WORK/05_risk/risks/drugs_alcohol/data/exp/summary_inputs", "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/temp", 1, TRUE, 10, 10)
	} else {
	  root <- "/home/j/"
	  print(paste(commandArgs(),sep=" "))
		arg <- commandArgs()[-(1:3)]                  # First args are for unix use only
	}
	
## Read in arguments passed in by shell script.
	yyy <- as.numeric(arg[1])                     # Year for current analysis
	aaa <- as.numeric(arg[2])                     # age_group_id
	sss <- as.numeric(arg[3])                     # Sex for current analysis (1=male, 2=female)
	ccc <- arg[4]                                 # cause group for current analysis
	code.dir <- arg[5]                            # Code directory
	data.dir <- arg[6]                            # Data directory
	out.dir <- arg[7]                             # Directory to put temporary draws in
	mycores <- as.numeric(arg[8])                 # Number of cores (which can be used to parallelize)
	myverbose <- as.logical(arg[9])               # Whether to print messages to console showing progress
	myB <- as.numeric(arg[10])            # Number of draws to run (higher than save to match EG methods) 
	mysavedraws <- as.numeric(arg[11])            # Number of draws to save 
	
## get age from age_group_id
agemap <- read.csv(paste0(root,"/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/agemap.csv"))
age <- agemap$age[agemap$age_group_id == aaa]
	
## Prepare
	## Read in exposure data
		data.file <- paste0(data.dir, "/alc_data_", yyy, ".csv")
		drkData <- read.csv(data.file)
		
	##Change column 'location_id' to match Jurgen's
		names(drkData)[names(drkData) == "location_id"] <- "REGION"
		drkData <- drkData[,!names(drkData) %in% c("X","Unnamed..0")]
			
  ## Read in draws of age splitting
    age.file <- paste0(out.dir,"/alc_age_frac_",yyy,"_",aaa,"_",sss,".csv")
    agefrac <- read.csv(age.file)
    names(agefrac)[names(agefrac)=="year_id"] <- "year"
    names(agefrac)[names(agefrac)=="sex_id"] <- "sex"
    agefrac$age <- age
    
    

	## Read in RR functions
		source(paste0(code.dir, "/rr/03_1_", ccc, "RR.R"))
		if(sss == 1) {
			relativerisk <- relativeriskmale 
		} else {
			relativerisk <- relativeriskfemale
		}
		
#   ## change some relative risks based on instruction file
#   if (ccc == "chronic") {
#     swap.file <- paste0(data.dir, "/RR-Changes.csv")
#     swaps <- read.csv(swap.file,stringsAsFactors=F)
#     ## get directory of RRs
#     direct <- lapply(as.list(1:length(relativerisk)), FUN= function(x) {relativerisk[[x]]$disease})
#     vdirect <- data.frame(disease = do.call("rbind",direct))
#     ## subset only swaps to be made
#     swaps <- swaps[swaps$disease %in% vdirect$disease,]
#     if (length(swaps$disease > 0)) {
#       for (i in 1:length(swaps$disease)) {
#         outnum <- as.numeric(row.names(vdirect)[vdirect$disease == swaps$disease[i]])
#         outfem <- grep("WOMEN",swaps$disease[i])
#         infem <- grep("WOMEN",swaps$r1[i])
#         if (length(infem) == 0) { infem <- 0}
#         if (infem == 1) {
#           print(paste(swaps$disease[i],"infem1",sep=" "))
#           d <- lapply(as.list(1:length(relativeriskfemale)), FUN= function(x) {relativeriskfemale[[x]]$disease})
#           v <- data.frame(disease = do.call("rbind",d))
#           innum <- as.numeric(row.names(v)[v$disease == swaps$r1[i]])
#           relativerisk[[outnum]] <- relativeriskfemale[[innum]]
#           relativerisk[[outnum]]$disease <- swaps$disease[i]
#         } else {
#         print(paste(swaps$disease[i],"infem0",sep=" "))
#           d <- lapply(as.list(1:length(relativeriskmale)), FUN= function(x) {relativeriskmale[[x]]$disease})
#           v <- data.frame(disease = do.call("rbind",d))
#           innum <- as.numeric(row.names(v)[v$disease == swaps$r1[i]])
#           relativerisk[[outnum]] <- relativeriskmale[[innum]]
#           relativerisk[[outnum]]$disease <- swaps$disease[i]
#         }
#       }
#     }
#   }
  
  ## if it's russia, we should just keep the countries we want...no point in doing too much analysis
  if (ccc == "russia") {
    ##drkData <- drkData[drkData$ihme_loc_id %in% c("RUS","BLR","UKR","LTU","EST","LVA","MDA"),]
    drkData <- drkData[drkData$REGION %in% c(57,58,59,60,61,62,63),]
  }

		
	## Read in AAF calculation functions
		# Russia uses chronic AAF code, because the chronic code is the base-case and the russian RRs are not complicated.
		aaf.code <- ifelse(ccc != "russia", 
					paste0(code.dir, "/03_2_", ccc, "AAF.R"), 
					paste0(code.dir, "/03_2_chronicAAF.R"))
		source(aaf.code)
		

## Run PAF code for this group and save
	set.seed(10 * sss + aaa) # Set unique seed for each age/sex group.
	system.time(
		AAFConfint <- confintAAF(data = drkData, agefrac=agefrac, disease = relativerisk, B = myB, gender = sss, age = age, adjustPCA = 0.8, mc.cores = mycores, verbose = myverbose, saveDraws = mysavedraws)
	)
	AAFConfint$age <- age
	write.csv(AAFConfint, file = paste0(out.dir, "/AAF_", yyy, "_a", aaa, "_s", sss, "_", ccc, ".csv"))
	