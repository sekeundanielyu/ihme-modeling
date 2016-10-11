################################################################################
## Description: Run the first stage of the prediction model for adult mortality
##              and calculate inputs to GPR 
################################################################################

rm(list=ls())
library(foreign); library(zoo); library(nlme); library(plyr); library(data.table)

if (Sys.info()[1] == "Linux"){
 root <- ""
 rnum <- commandArgs()[3]
 hivsims <- as.integer(commandArgs()[4])
 user <- commandArgs()[5] 
 code_dir <- paste0("",user,"")
 source("/get_locations.r")
}else{
 root <- "J:"
 hivsims <- F
 user <- ""
 code_dir <- paste0("",user,"")
 source("get_locations.r")
}

setwd(paste(root, "", sep=""))
source(paste(code_dir, "/space_time.r", sep=""))

data <- read.csv(ifelse(!hivsims,
                         "/prediction_input_data.txt",
                         paste("/prediction_input_data_",rnum,".txt", sep="")), stringsAsFactors=F)

# set the space-time parameters
#lambda <- .8   # note: some exceptions in space-time
#zeta <- .99 

  
## format data
data$method[grepl("indirect", data$type)] <- "SBH"
data$method[data$type == "direct"] <- "CBH"
data$method[grepl("VR|SRS|DSP", data$source)] <- "VR/SRS/DSP"
data$method[data$type == "hh" | (is.na(data$method) & grepl("census|survey", tolower(data$source)))] <- "HH"
data$method[data$source == "hsrc" & data$ihme_loc_id == "ZAF"] <- "CBH"
data$method[data$source == "icsi" & data$ihme_loc_id == "ZWE"] <- "SBH"
data$method[data$source == "indirect" & data$ihme_loc_id == "DZA"] <- "SBH"
data$method[is.na(data$method) & data$data == 1] <- "HH"

data$graphing.source[grepl("vr|vital registration", tolower(data$source))] <- "VR"
data$graphing.source[grepl("srs", tolower(data$source))] <- "SRS"
data$graphing.source[grepl("dsp", tolower(data$source))] <- "DSP"
data$graphing.source[grepl("census", tolower(data$source)) & !grepl("Intra-Census Survey",data$source)] <- "Census"
data$graphing.source[grepl("_IPUMS_", data$source) & !grepl("Survey",data$source)] <- "Census"
data$graphing.source[data$source == "DHS" | data$source == "dhs" | data$source == "DHS IN" | grepl("_DHS", data$source)] <- "Standard_DHS"
data$graphing.source[grepl("^DHS .*direct", data$source1)&!grepl("SP", data$source1)] <- "Standard_DHS"
data$graphing.source[tolower(data$source) %in% c("dhs itr", "dhs sp","dhs statcompiler") | grepl("DHS SP", data$source)] <- "Other_DHS"  
data$graphing.source[grepl("mics|multiple indicator cluster", tolower(data$source))] <- "MICS"
data$graphing.source[tolower(data$source) %in% c("cdc", "cdc-rhs", "cdc rhs", "rhs-cdc", "reproductive health survey") | grepl("CDC-RHS|CDC RHS", data$source)] <- "RHS"
data$graphing.source[grepl("world fertility survey|wfs|world fertitlity survey", tolower(data$source))] <- "WFS"
data$graphing.source[tolower(data$source) == "papfam" | grepl("PAPFAM", data$source)] <- "PAPFAM"
data$graphing.source[tolower(data$source) == "papchild" | grepl("PAPCHILD", data$source)] <- "PAPCHILD"
data$graphing.source[tolower(data$source) == "lsms" | grepl("LSMS", data$source)] <- "LSMS"
data$graphing.source[tolower(data$source) == "mis" | tolower(data$source) == "mis final report" | grepl("MIS", data$source)] <- "MIS"
data$graphing.source[tolower(data$source) == "ais" | grepl("AIS", data$source)] <- "AIS"
data$graphing.source[is.na(data$graphing.source) & data$data == 1] <- "Other"


#Combining certain types and graphing sources for survey fixed effects 
data$graphing.source[data$graphing.source %in% c("Other_DHS","PAPCHILD","PAPFAM","LSMS","RHS")] <- "Other"
data$graphing.source[data$graphing.source == "Census" & data$type == "CBH"] <- "Other"
data$graphing.source[data$graphing.source %in% c("AIS","MIS")] <- "AIS_MIS"

#VR is split in 02 (data prep) into biased and unbiased. Use that here for the source and source.type
data$graphing.source[data$vr == 1 & data$data == 1] <- data$category[data$vr == 1 & data$data == 1]

#Get combo source/type
data$source.type <- paste(data$graphing.source, data$method, sep="_")
data$source.type[data$data == 0] <- NA


######################
#Choose reference categories
######################
  data$reference <- 0

  # load iso3s from GBD 2013 to make this easier- some china ones outliered using those
  isos <- read.csv(paste(root, "GBD_2013_locations.txt", sep = ""), stringsAsFactors=F)
  isos <- isos[isos$level_all != 0,]
  isos <- isos[,c("ihme_loc_id","local_id_2013")]
  names(isos) <- c("ihme_loc_id","iso3")
  isos$iso3[isos$iso3 == ""] <- "CHN"
  data <- merge(data,isos,by="ihme_loc_id",all.x=T)
  data <- data[!is.na(data$iso3),]
  all_loc_len <- length(unique(data$ihme_loc_id))

  data$reference[data$ihme_loc_id %in% c("GTM","PRY","BHR","ECU") & grepl("DHS .*direct|CDC-RHS .*direct|CDC RHS .*direct",data$source1) &! grepl("SP", data$source1) &! grepl("indirect", data$type)] <- 1    
  data$reference[data$ihme_loc_id == "YEM" & grepl("PAPFAM|DHS .*direct", data$source1) &! grepl("SP", data$source1) &! grepl("indirect", data$type)] <- 1
  data$reference[data$ihme_loc_id == "FSM" & grepl("VR|Census_2000", data$source1)] <- 1
  data$reference[data$ihme_loc_id == "ZAF" & grepl("SURVEY|DHS .*direct|RapidMortality", data$source1) &! grepl("SP", data$source1) &! grepl("indirect", data$type)] <- 1
  data$reference[data$ihme_loc_id == "CHN_44533" & (grepl("Maternal and Child Health Surveillance System", data$source1)) & data$data == 1] <- 1
  # VR is biased, so not reference source per GBD 2013
  data$reference[data$ihme_loc_id == "GUY" & grepl("DHS .*direct", data$source1) &! grepl("SP", data$source1) &! grepl("indirect", data$type)] <- 1
  data$reference[data$ihme_loc_id == "IRQ" & grepl("MICS", data$source)] <- 1
  data$reference[data$ihme_loc_id == "KAZ" & (data$source == "VR1" | grepl("MICS",data$source))] <- 1
  #Make biased VR the reference in CaribbeanI countries with no other surveys
  data$reference[data$region_name == "CaribbeanI" & data$category == "vr_biased" & !data$to_correct] <- 1
  # CRI reference to RHS direct/indirect or Indirect census
  data$reference[data$ihme_loc_id == "CRI" & grepl("CDC-RHS|Census|CDC RHS", data$source1)] <- 1 
  
  ## GBD 2015 changes
  # COD reference changed to Standard DHS
  data$reference[data$ihme_loc_id == "COD" & data$source.type == "Standard_DHS_CBH"] <- 1 
  
  #Assign reference groups to China provinces
  mchs.provs <- c("CHN_491", "CHN_492", "CHN_493", "CHN_496", "CHN_497", "CHN_498", "CHN_500", "CHN_501", "CHN_503", "CHN_507", "CHN_508", "CHN_512", "CHN_513", "CHN_514", "CHN_515", "CHN_516", "CHN_499", "CHN_506", "CHN_510", "CHN_511", "CHN_517")
  moh.provs <- c("CHN_504", "CHN_494", "CHN_509", "CHN_505", "CHN_520")
  data$reference[(data$ihme_loc_id %in% moh.provs) & grepl("MOH", data$source1, ignore.case = T)] <- 1
  data$reference[(data$ihme_loc_id %in% mchs.provs) & grepl("MCHS", data$source1)] <- 1
  data$reference[data$ihme_loc_id == "CHN_521" & grepl("MOH|MCHS", data$source1)] <- 1
  data$reference[data$ihme_loc_id == "CHN_502" & grepl("MCHS", data$source1)] <- 1
  data$reference[data$ihme_loc_id == "CHN_495" & data$source1 == "DSP_0"] <- 1
  data$reference[data$ihme_loc_id == "CHN_518" & grepl("Census 2000|MOH Routine Report",data$source1)] <- 1
  data$reference[data$ihme_loc_id == "CHN_519" & grepl("MCHS|Census 1990",data$source1)] <- 1
  #data$reference[data$iso3 == "XCC" & grepl("MCHS|DSP_0", data$source1)] <- 1
  
  # Assign reference sources to Brazil States
  pnad.states <- c("BRA_4750","BRA_4754","BRA_4757","BRA_4758","BRA_4759","BRA_4760","BRA_4761","BRA_4762","BRA_4763","BRA_4766","BRA_4773","BRA_4774","BRA_4776")
  census.states <- c("BRA_4767","BRA_4770")
  dhs.states <- c("BRA_4752")
  data$reference[data$ihme_loc_id == "BRA_4753" & data$source.yr == 2008 & data$source1 == "PNAD_subnat 2008 indirect"] <- 1
  data$reference[data$ihme_loc_id == "BRA_4751" & data$source.yr == 2005 & data$source1 == "PNAD_subnat 2005 indirect"] <- 1
  data$reference[data$ihme_loc_id == "BRA_4771" & data$source.yr == 2006 & data$source1 == "PNAD_subnat 2006 indirect"] <- 1
  data$reference[data$ihme_loc_id == "BRA_4769" & data$source.yr %in% c(2001,2002) & data$source1 %in% c("BRA_PNAD_1992_2013 2001 indirect, MAC only", "BRA_PNAD_1992_2013 2002 indirect, MAC only")] <- 1
  data$reference[(data$ihme_loc_id %in% pnad.states) & grepl("PNAD", data$source1)] <- 1
  data$reference[(data$ihme_loc_id %in% census.states) & grepl("CENSUS", data$source1)] <- 1
  data$reference[(data$ihme_loc_id %in% dhs.states) & data$source.type == "Standard_DHS_CBH"] <- 1

  # assign reference source to Mozambique DHS CBH average
  data$reference[(data$ihme_loc_id == "MOZ") & data$source.type == "Standard_DHS_CBH"] <- 1
  
  # south sudan use the census as the reference
  data$reference[(data$ihme_loc_id == "SSD") & data$source == "Census, IPUMS"] <- 1  
  
  # Sudan make the reference MICS SBH
  data$reference[(data$ihme_loc_id == "SDN") & data$source1 == "MICS direct"] <- 1 
  
  # new make india states reference sources the acerage of DHS summary birth history except where it's not available. Otherwise use DLHS SBH
  dlhs.states <- c("IND_43902", "IND_43938")
  data$reference[(data$ihme_loc_id %in% dlhs.states) & grepl("DLHS", data$source1) & data$type == "indirect"] <- 1
  data$reference[grepl("IND_", data$ihme_loc_id) & !(data$ihme_loc_id %in% dlhs.states) & grepl("DHS", data$source1) & data$type == "indirect"] <- 1
    
  # Laos use the MICS CBH as reference
  data$reference[data$ihme_loc_id == "LAO" & grepl("MICS", data$source1) & data$type == "direct"] <- 1 
  
  # TLS use the newer DHS as reference
  data$reference[data$ihme_loc_id == "TLS" & data$source1 == "DHS 2009-2010 direct"] <- 1
  
  # BWA use the census as reference
  data$reference[(data$ihme_loc_id == "BWA") & grepl("census", data$source1) & data$type == "indirect"] <- 1
  
  # Benin use the DHS CBH as reference
  data$reference[(data$ihme_loc_id == "BEN") & data$category == "dhs direct" & data$source != "DHS 2011-2012"] <- 1
    
  # Gambia use DHS CBH as reference
  data$reference[(data$ihme_loc_id == "GMB") & data$source.type == "Standard_DHS_CBH"] <- 1
  
  # Kyrgyzstan (KGZ)  use DHS CBH as reference
  data$reference[(data$ihme_loc_id == "KGZ") & data$source.type == "Standard_DHS_CBH"] <- 1
  
  # MLI use the higher DHS as reference
  data$reference[(data$ihme_loc_id == "MLI") & data$source.type == "Standard_DHS_CBH"] <- 1
  
  # SLE use the higher DHS CBH as reference
  data$reference[(data$ihme_loc_id == "SLE") & data$source.type == "Standard_DHS_CBH"] <- 1
  
  # Comoros use DHS 1996 direct as reference because the later survey has a flat trend
  data$reference[data$ihme_loc_id == "COM" & data$source.type == "Standard_DHS_CBH" & data$source != "DHS 2012-2013"] <- 1
  
  # PER use DHS CBH as reference, but not the highest source (DHS 2004-2008 direct)
  data$reference[(data$ihme_loc_id == "PER") & data$source.type == "Standard_DHS_CBH" & !(data$source1 == "DHS direct")] <- 1
  
  #GHA with CBH source name updates the DHS SP is no longer marked as reference, updated this (9/2015)
  data$reference[(data$ihme_loc_id == "GHA") & data$category == "dhs direct"] <- 1

  # add census HH to the reference
  data$reference[grepl("ZAF", data$ihme_loc_id) & data$source.type=="Census_HH"] <- 1
  
  # add ZAF VR after 2008 to the reference
  data$reference[grepl("ZAF", data$ihme_loc_id) & data$source=="VR1"] <- 1

  ## SAU - use household points for the states in reference (11/30/15)
  data$reference[grepl("SAU_", data$ihme_loc_id) & data$source.type %in% c("Census_HH", "Other_HH")] <- 1
  
  # add SAU VR after 2008 to the reference
  data$reference[grepl("SAU_", data$ihme_loc_id) & data$source=="VR"] <- 1

  # Kenya subnational
  dhs.2003 <- c("KEN_35618", "KEN_35626", "KEN_35628", "KEN_35632", "KEN_35633", "KEN_35656", "KEN_35657")
  dhs.2008 <- c("KEN_35619", "KEN_35629", "KEN_35645", "KEN_35658", "KEN_35660")
  dhs.1988 <- c("KEN_35621")
  dhs.1993 <- c("KEN_35617", "KEN_35631", "KEN_35636")
  dhs.1998 <- c("KEN_35655")
  data$reference[(data$ihme_loc_id %in% dhs.2003) & data$source.type == "Standard_DHS_CBH" & !(data$source1 == "DHS 2003 direct")] <- 1
  data$reference[(data$ihme_loc_id %in% dhs.2008) & data$source.type == "Standard_DHS_CBH" & !(data$source1 == "DHS 2008 direct")] <- 1
  data$reference[(data$ihme_loc_id == dhs.1988) & data$source.type == "Standard_DHS_CBH" & !(data$source1 == "DHS 1988 direct")] <- 1
  data$reference[(data$ihme_loc_id %in% dhs.1993) & data$source.type == "Standard_DHS_CBH" & !(data$source1 == "DHS 1993 direct")] <- 1
  data$reference[(data$ihme_loc_id == dhs.1998) & data$source.type == "Standard_DHS_CBH" & !(data$source == "DHS 1998")] <- 1
  data$reference[(data$ihme_loc_id == "KEN_35622") & data$source.type == "Standard_DHS_CBH" & !(data$source %in% c("DHS 1998", "DHS 2003"))] <- 1  
  data$reference[(data$ihme_loc_id == "KEN_35648") & data$source.type == "Standard_DHS_CBH" & !(data$source %in% c("DHS 2003", "DHS 2008"))] <- 1 
  data$reference[data$ihme_loc_id=="KEN_35663" & data$source1=="KEN_DHS_subnat 2009 indirect"] <- 1
 
  # South Africa provinces switch to census 1996 as reference (9.2015)
  census.1996 <- c("ZAF_482", "ZAF_483", "ZAF_484", "ZAF_485", "ZAF_486", "ZAF_487", "ZAF_489", "ZAF_490")
  dhs <- c("ZAF_488")
  data$reference[(data$ihme_loc_id %in% census.1996) & grepl("CENSUS|census", data$source) & data$type == "indirect" & data$source.yr == 1996] <- 1
  data$reference[(data$ihme_loc_id %in% dhs)  & grepl("DHS|dhs", data$source) & data$type == "direct"] <- 1
     
  #if no reference group assigned, use unbiased VR (except for TON and MWI)
  ref.ct <- unique(data$ihme_loc_id[data$reference == 1])
  data$reference[!(data$ihme_loc_id %in% ref.ct) & data$source.type == "vr_unbiased_VR/SRS/DSP" & data$vr == 1 & !(data$ihme_loc_id %in% c("TON","MWI"))] <- 1
  ref.ct <- unique(data$ihme_loc_id[data$reference == 1])
  #ref = 1 for DHS completes in countries w/ no unbiased VR and not already assigned ref. cats
  data$reference[!(data$ihme_loc_id %in% ref.ct) & data$source.type == "Standard_DHS_CBH"] <- 1

  #For countries w/o reference source or that already have a ref but we want to use the mean
  #, assign ref as mean of all sources since 1980 except biased VR
  ref.ct <- unique(data$ihme_loc_id[data$reference == 1])
  data$reference[data$source.type != "vr_biased_VR/SRS/DSP" & (data$ihme_loc_id %in% c("AFG","CAF","STP","LSO","SWZ","GNQ","MHL","SLB","PNG","TJK","MMR") | !(data$ihme_loc_id %in% ref.ct)) & data$data == 1 & data$year>1980] <- 1

  ## Mexico states
  data$reference[grepl("MEX_", data$ihme_loc_id) & data$source == "105806#MEX_NNS_subnat_1988"] <- 0
  data$reference[data$ihme_loc_id == "MEX_4668" & data$source == "93321#MEX_ENIGH_2010_subnat"] <- 0
  
  data$reference[data$ihme_loc_id=="SDN" & data$source.type=="Standard_DHS_CBH"] <- 0
  data$reference[data$ihme_loc_id=="SDN" & data$source.type=="MICS_CBH"] <- 1
 
  
  # South Africa subnationals
  # Eastern Cape
  data$reference[data$ihme_loc_id=="ZAF_482"] <- 0 # reset eastern cape reference 12/29/15
  data$reference[data$ihme_loc_id=="ZAF_482" & data$source1=="43146#ZAF_IPUMS_CENSUS_1996 1996 indirect"] <- 1 # in Eastern cape, set 1996 census as reference 12/29/15
  
  # Free State - get rid of HH points as reference 12/29/15
  data$reference[data$ihme_loc_id=="ZAF_483" & data$source.type=="Census_HH"] <- 0 
  
  # KwaZulu- Natal - get rid of census points as reference 12/29/15

  data$reference[data$ihme_loc_id=="ZAF_485"] <- 0 
  data$reference[data$ihme_loc_id=="ZAF_485" & data$source.type=="Census_HH"] <- 1

  
  # Limpopo - get rid of everything but 1996 census as reference
  data$reference[data$ihme_loc_id=="ZAF_486"] <- 0 # reset reference 12/29/15
  data$reference[data$ihme_loc_id=="ZAF_486" & data$source1=="43146#ZAF_IPUMS_CENSUS_1996 1996 indirect"] <- 1 #  set 1996 census as reference 12/29/15
  
  
  # Mpumalanga - get rid of everything but 1996 census as reference
  data$reference[data$ihme_loc_id=="ZAF_487"] <- 0 # resetreference 12/29/15
  data$reference[data$ihme_loc_id=="ZAF_487" & data$source1=="43146#ZAF_IPUMS_CENSUS_1996 1996 indirect"] <- 1 # set 1996 census as reference 12/29/15
  
  # Northern Cape
  data$reference[data$ihme_loc_id=="ZAF_489"] <- 0 # resetreference 12/29/15
  # set CBH DHS as the reference source
  data$reference[data$ihme_loc_id=="ZAF_489" & data$source.type=="Standard_DHS_CBH"] <- 1 # 12/29/15
  


########## Debugging
  #for double-checking which countries have reference surveys.
  #unique(data[,c("ihme_loc_id","source1","reference")])
  #unique(data$ihme_loc_id)[!(unique(data$ihme_loc_id) %in% unique(data$ihme_loc_id[data$reference == 1]))]

## make sure every reference survey entry has reference == 1
for (ihme_loc_id in unique(data$ihme_loc_id)){
  ref_s <- unique(data$source1[data$reference == 1 & data$ihme_loc_id == ihme_loc_id])
  data$reference[data$ihme_loc_id == ihme_loc_id & data$source1 %in%  ref_s] <- 1
}
data$iso3 <- NULL

#################################################################################
#################################################################################
#######################
# Fit first stage model
#######################

#solve for mx
data$mx <- log(1-data$mort)/-5

data$tLDI <- log(data$LDI)
data$ihme_loc_id <- as.factor(data$ihme_loc_id)

#grouped data object
data$dummy <- 1
data$source.type <- as.factor(data$source.type)

#sets dhs cbh as the first (and therefore reference) category for source.types
data$source.type <- relevel(data$source.type,"Standard_DHS_CBH")

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)

mod.data <- groupedData(mx~ 1 | ihme_loc_id/source1, data = data[!is.na(data$mort),])

#Model 2: fixed intercept, survey.type, random ihme_loc_id/survey
###########################################################
#have tested - model not sensitive to start values
fm1start <- c(rep(0, length(unique(data$source.type[data$data == 1]))+3))

#Model 2 formula: fixed effect on source.type
fm1form <- as.formula("mx ~ exp(beta1*tLDI + beta2*maternal_educ + beta5*dummy + beta4) + beta3*hiv")

#nlme with nested RE on ihme_loc_id/survey, FE on source.type
model <- nlme(fm1form, 
  data = mod.data, 
  fixed = list(beta1 + beta2 + beta3 ~1, beta5 ~ source.type),
  random = list(ihme_loc_id = beta1 + beta2 + beta4 ~ 1, source1 = beta4 ~ 1),
  start = fm1start,
  verbose = F)

# save first stage model
if(!hivsims){
  save(model, file="first_stage_regressions_GBD2013.rdata")
  save(model, file=paste("first_stage_regression_GBD2013_", Sys.Date() ,".rdata", sep=""))
}
  
##########################
#Merge residuals, fixed effects, random effects into data
#########################

###########################################################
##Merge residuals into data
data$resid1 <- rep("NA", length(data$data))
data$resid1[!is.na(data$mort)] <- model$residuals[,"source1"]
data$resid1 <- as.numeric(data$resid1)

##Merge ihme_loc_id:survey (nested) Random Effects into data
data$src.ihme_loc_id <- paste(data$ihme_loc_id, "/",data$source1, sep="")

src.re <- as.data.frame(model$coefficients$random$source1[,1])
colnames(src.re) <- "re2"
src.re$src.ihme_loc_id <- row.names(src.re)

data <- merge(data, src.re, by="src.ihme_loc_id", all.x = T)

##Merge ihme_loc_id random effects into data
data$b1.re <- data$b2.re <- data$ctr_re <- NA
for (ii in rownames(model$coefficients$random$ihme_loc_id)){
 data$b1.re[data$ihme_loc_id == ii] <- model$coefficients$random$ihme_loc_id[ii,1]
 data$b2.re[data$ihme_loc_id == ii] <- model$coefficients$random$ihme_loc_id[ii,2]
 data$ctr_re[data$ihme_loc_id == ii] <- model$coefficients$random$ihme_loc_id[ii,3]
}

##Merge source.type fixed effects into data
#Intercept/reference category is assigned to be Standard_DHS_CBH right now
st.fe <- fixef(model)[grep("(Intercept)",names(fixef(model))):length(fixef(model))] 

names(st.fe) <- levels(data$source.type)
st.fe[1] <- 0

st.fe <- as.data.frame(st.fe)
st.fe$source.type <- row.names(st.fe)
data <- merge(data, st.fe, by="source.type",all.x = T)

write.csv(st.fe, paste0(root,"source_type_fe_GBD2013_", Sys.Date(), ".csv"), row.names = T)

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)

#Get data back in order
data <- data[order(data$ihme_loc_id, data$year),]

########################
#Get reference value of FE+RE and adjust data
########################

dat3 <- ddply(data[!duplicated(data[,c("ihme_loc_id","source1")]),],
              .(ihme_loc_id),
              function(x){
              data.frame(ihme_loc_id = x$ihme_loc_id[1],
                         mre2 = mean(x$re2[x$reference == 1]),
                         mfe = mean(x$st.fe[x$reference ==1]))
                         })

dat3$summe <- dat3$mre2+dat3$mfe

#merge ref sum re/fe into data
data <- merge(data,dat3,all=T)

data <- data[,names(data) != "src.ihme_loc_id"]

#get adjusted re + fe into data
data$adjre_fe <- data$re2+data$st.fe-data$summe

#####################
#Get predictions 
####################

#predictions w/o any random or fixed effects
pred.mx <- exp(model$coefficients$fixed[1]*data$tLDI + model$coefficients$fixed[2]*data$maternal_educ + model$coefficients$fixed[4]) + model$coefficients$fixed[3]*data$hiv

data$pred.1b <- 1-exp(-5*pred.mx)

######################################
   
#####################
#Get adjusted data points - only for non-incomplete-VR sources  
####################
#Calculate mort w/ survey random effects removed for residual calculation (2nd Stage Model) - not biased VR
#The nbs.ind determines which points should be bias (mixed-effects) adjusted
#to_correct means that a point will be corrected in the vr step (some "biased" points aren't actually corrected there)
  nbs.ind <- (data$data == 1 & !data$to_correct)
  data$mx2[nbs.ind] <- exp((model$coefficients$fixed[1]+data$b1.re[nbs.ind])*data$tLDI[nbs.ind] + (model$coefficients$fixed[2] + data$b2.re[nbs.ind])*data$maternal_educ[nbs.ind]  + model$coefficients$fixed[4] + data$ctr_re[nbs.ind] + data$summe[nbs.ind]) + model$coefficients$fixed[3]*data$hiv[nbs.ind] + data$resid1[nbs.ind]

  #don't let complete VR go down (don't believe there are fewer deaths than counted)
  data$mx2[data$data==1 & data$category == "vr_unbiased" & data$mx2<data$mx] <- data$mx[data$data==1 & data$category == "vr_unbiased" & data$mx2<data$mx]
  #AFG
  #find mean adjustment for category other sources in afghanistan, and use it to adjust the 'national demographic and family guidance survey' points
  afg.oth.m <- mean(data$adjre_fe[data$data == 1 & data$ihme_loc_id == "AFG" & grepl("other", data$source.type, ignore.case =T) & data$source != "national demographic and family guidance survey"])
  afg.ind <- (data$data == 1 & data$ihme_loc_id == "AFG" & data$source == "national demographic and family guidance survey")
  data$mx2[afg.ind] <-  exp((model$coefficients$fixed[1]+data$b1.re[afg.ind])*data$tLDI[afg.ind] + (model$coefficients$fixed[2] + data$b2.re[afg.ind])*data$maternal_educ[afg.ind]  + model$coefficients$fixed[4] + data$ctr_re[afg.ind] + data$re2[afg.ind] + data$st.fe[afg.ind] - afg.oth.m) + model$coefficients$fixed[3]*data$hiv[afg.ind] + data$resid1[afg.ind]

  # only need to do this when outliers are included in the dataset - here impute negative mx2's as 0.0001
  data$mx2[data$mx2 <= 0] <- 0.0001

#Transform back to qx space  
  data$mort2 <- 1-exp(-5*(data$mx2))
  data$log10_mort2 <- log(data$mort2, base=10)

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)


#######################
#Biased VR adjustment 
#######################

# run a loess regression to determine the bias correction for biased countries
  data <- data[order(data$ihme_loc_id, data$year),]
  for(ihme_loc_id in unique(data$ihme_loc_id[data$corr_code_bias & (data$data == 1)])) {
  
        # loess non-vr data in these countries
        # changed span from 1.5 to 0.8 on 1/10/14 to try and make vr adjustment more responsive for HIV bumps
        #WARNING: Don't use span < 0.9 or countries with < 7 points (Russia right now) will break. Loess predicts unreasonable values. 1/30/14
        model <- loess(log(mort2,base=10) ~ year, span=.9, data=data[data$vr==0 & data$ihme_loc_id==ihme_loc_id,], control=loess.control(surface="direct"))
  
        # predict based on the loess
        preds <- predict(model, newdata=data.frame(year=data$year[data$ihme_loc_id==ihme_loc_id]))
  
        # add the predictions to the main dataset
        data$non.vr.loess[data$ihme_loc_id==ihme_loc_id] <- preds

        # find the min and max year where non-vr data is available at the country level
        data$min[data$ihme_loc_id==ihme_loc_id] <- min(data$year[data$vr==0 & data$ihme_loc_id==ihme_loc_id], na.rm=T)
        data$max[data$ihme_loc_id==ihme_loc_id] <- max(data$year[data$vr==0 & data$ihme_loc_id==ihme_loc_id], na.rm=T)
  
        # find the difference for each individual vr point in the dataset
        data$index <- 0
        data$index[data$corr_code_bias & data$year >= data$min & data$year <= data$max & data$ihme_loc_id==ihme_loc_id] <- 1   # vr where non-vr is available
        data$index[data$corr_code_bias & data$year < data$min & data$ihme_loc_id==ihme_loc_id] <- 2                            # vr where non-vr is not available (early)
        data$index[data$corr_code_bias & data$year > data$max & data$ihme_loc_id==ihme_loc_id] <- 3                            # vr where non-vr is not available (late)
  
        # find the difference between the loess of non-vr and the vr estimates (in the loess sample)
        data$diff[data$index==1] <- data$non.vr.loess[data$index==1] - log(data$mort[data$index==1],base=10)
        data$abs.diff[data$index==1] <- abs(data$diff[data$index==1])
  
        # convert this difference (in log10 space) to a bias correction factor (5q0 space)
        data$bias[data$index==1] <- 10^data$diff[data$index==1]
      
      #####  
      #Countries for which we want to estimate different VR bias for multiple different VR systems    
          vr.systems <- unique(data$source[data$ihme_loc_id == ihme_loc_id & data$corr_code_bias])
          vr.systems <- vr.systems[!is.na(vr.systems)]
          for (sys in vr.systems){
              if(length(data$vr[data$ihme_loc_id==ihme_loc_id & data$index==1 & data$source == sys]) >= 5) {
                # find the 5 year rolling mean of the bias correction (for index 1 only)
                data$mean.bias[data$index==1 & data$source == sys] <- rollmean(data$bias[data$index==1 & data$source == sys],5,na.pad=T, align=c("center"))
                # find the 5 year rolling MAD of the bias correction (for index 1 only)
                data$mad[data$index==1 & data$source == sys] <- rollmedian(data$abs.diff[data$index==1 & data$source == sys],5,na.pad=T, align=c("center"))
        
                # fill in missing bias estimates on the two tails of our data series
                early <- data$bias[data$index==1 & data$source == sys][1:5]
                end <- length(data$bias[data$index==1 & data$source == sys])
                end.min5 <- end - 4
                late <- data$bias[data$index==1 & data$source == sys][end.min5:end]
                mean.early <- mean(early)
                mean.late <- mean(late)
                data$mean.bias[is.na(data$mean.bias) & data$index==2 & data$source == sys] <- mean.early
                data$mean.bias[is.na(data$mean.bias) & data$index==3 & data$source == sys] <- mean.late
        
                # still need to fill in missingings on the tails of the in-sample vr data
                max <- max(data$year[!is.na(data$mean.bias) & data$index==1 & data$source == sys])
                min <- min(data$year[!is.na(data$mean.bias) & data$index==1 & data$source == sys])
                data$mean.bias[is.na(data$mean.bias) & data$year<min & data$vr==1 & data$ihme_loc_id==ihme_loc_id & data$source == sys] <- mean.early
                data$mean.bias[is.na(data$mean.bias) & data$year>max & data$vr==1 & data$ihme_loc_id==ihme_loc_id & data$source == sys] <- mean.late
        
                # same as above for the mad estimator
                early <- data$abs.diff[data$index==1 & data$source == sys][1:5]
                end <- length(data$abs.diff[data$index==1 & data$source == sys])
                end.min5 <- end - 4
                late <- data$abs.diff[data$index==1 & data$source == sys][end.min5:end]
                mean.early <- mean(early)
                mean.late <- mean(late)
                data$mad[is.na(data$mad) & data$index == 2 & data$source == sys] <- mean.early
                data$mad[is.na(data$mad) & data$index == 3 & data$source == sys] <- mean.late
        
                # again, filling in missingingness in-sample, this time for the mad
                data$mad[is.na(data$mad) & data$year<min & data$vr==1 & data$ihme_loc_id==ihme_loc_id & data$source == sys] <- mean.early
                data$mad[is.na(data$mad) & data$year>max & data$vr==1 & data$ihme_loc_id==ihme_loc_id & data$source == sys] <- mean.late
            } else {
                # find the mean bias across all points
                mean.bias <- mean(data$bias[data$ihme_loc_id==ihme_loc_id & data$vr==1 & data$source == sys],na.rm=T)
                # find the mad across all points
                mad <- median(data$abs.diff[data$ihme_loc_id==ihme_loc_id & data$vr==1 & data$source == sys], na.rm=T)
        
                # fill in the mean bias and mad in the dataset
                data$mean.bias[data$ihme_loc_id==ihme_loc_id & data$vr==1 & data$source == sys] <- mean.bias
                data$mad[data$ihme_loc_id==ihme_loc_id & data$vr==1 & data$source == sys] <- mad

            }
          }
        
        # convert the MAD estimate to a data variance
        data$bias.var[data$ihme_loc_id==ihme_loc_id & data$vr==1 & !is.na(data$vr)] <- (1.4826*data$mad[data$ihme_loc_id==ihme_loc_id & data$vr==1 & !is.na(data$vr)])^2
  
        # do not want to adjust cy's where the vr is biased upwards (except IND, PAK, and BGD where we want to add data variance)
        data$bias.var[data$ihme_loc_id==ihme_loc_id & data$mean.bias <= 1 & data$to_correct] <- 0
        data$mean.bias[data$ihme_loc_id==ihme_loc_id & data$mean.bias <= 1] <- 1
  }

# MANUAL EXCEPTIONS TO THE ABOVE CORRECTIONS
  #IRN
#  data$mean.bias[data$ihme_loc_id=="IRN" & data$year==1991.5 & data$vr==1] <- 1
#  data$bias.var[data$ihme_loc_id=="IRN" & data$year==1991.5 & data$vr==1] <- 0

  #hack for partial complete vr in KOR, ZAF
  #data$bias.var[data$ihme_loc_id %in% c("KOR","ZAF") & data$vr == 1 & is.na(data$bias.var)] <- 0

######
# also adjust VR-only countries with known biases using regional average bias
  # This is applicable to CaribbeanI -- want to average bias over countries in the region that have both vr and non-vr sources
  # as of 6/2/2013 this was BLZ GUY JAM and TTO (biased) and PRI (unbiased), 3/14/14, also BMU (unbiased)

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)

  # first fill in bias variables
  data$mean.bias[data$region_name=="CaribbeanI" & data$category=="vr_unbiased"] <- 1
  data$bias.var[data$region_name=="CaribbeanI" & data$category=="vr_unbiased"] <- 0

  #mark data from countries with surveys in addition to VR ["surveys" T/F]
  cardat <- data.table(data[data$region_name == "CaribbeanI",])
  cardat <- cardat[,surveys := (sum(data, na.rm = T) > sum(vr, na.rm = T)), by = ihme_loc_id]

  #find mean bias by year from countries with surveys in addtion to VR
  cardat <- cardat[,':='(rr.var = mean(bias.var[surveys == T], na.rm = T), rr.bias = mean(mean.bias[surveys == T], na.rm = T)), by = c("year")]

  # fill in years post 2008 with bias from 2008, as the more recent years appear too complete or don't have data
  cardat$rr.bias[cardat$year %in% c(2009.5,2010.5,2011.5,2012.5,2013.5,2014.5,2015.5)] <- cardat$rr.bias[cardat$year==2008.5][1]
  cardat$rr.var[cardat$year %in% c(2009.5,2010.5,2011.5,2012.5,2013.5,2014.5,2015.5)] <- cardat$rr.var[cardat$year==2008.5][1]

  #replace bias adjustment in vr-only CaribbeanI countries with the mean from every year for those CarI countries with surveys and vr
  cardat$mean.bias[cardat$surveys == F & cardat$data  == 1] <- cardat$rr.bias[cardat$surveys == F & cardat$data  == 1]
  cardat$bias.var[cardat$surveys == F & cardat$data  == 1] <- cardat$rr.var[cardat$surveys == F & cardat$data  == 1]

  #change status of no-survey CarI country points so they get corrected
  cardat$to_correct[cardat$surveys == F & cardat$data  == 1] <- T
  cardat$corr_code_bias[cardat$surveys == F & cardat$data  == 1] <- T

  #replace entries in 'data' with 'cardat' for CaribbeanI countries
  #first get rid of excess variables
  cardat$surveys <- cardat$rr.bias <- cardat$rr.var <- NULL

  data <- data[data$region_name != "CaribbeanI",]
  data <- as.data.frame(rbind(data,cardat))

# adjust all biased VR and VR in CaribbeanI
#####
# adjusting only vr data
  #first, get the indices of the data we actually want to correct, as there are some exceptions (see 02_adjust_biased_vr...)
  vr.cor.inds <- data$to_correct & (data$data  == 1)
  data$mort2[vr.cor.inds] <- data$mort[vr.cor.inds]*data$mean.bias[vr.cor.inds]

#get mx for variance calculations later on
data$mx2[vr.cor.inds] <- log(1-data$mort2[vr.cor.inds])/-5


data <- data[order(data$ihme_loc_id, data$year),]

#DEBUG HERE
#unique(data[is.na(data$mx2) & data$data == 1,c("ihme_loc_id","source")])

########################
# Fit second stage model - space time loess of residuals
########################  
# calculate residuals from final first stage regression
data$resid <- logit(data$mort2) - logit(data$pred.1b)
  
# try just having one residual for each country-year with data for space-time, so as not to give years with more data more weight
stdata <- ddply(data, .(ihme_loc_id,year), 
  function(x){
      data.frame(region_name = x$region_name[1],
      ihme_loc_id = x$ihme_loc_id[1],
      year = x$year[1],
      vr = max(x$vr),    
      resid = mean(x$resid))
    })

locs <- read.csv(paste(root, "/WORK/02_mortality/03_models/2_5q0/diagnostics/5q0_GBD2013_countries/diagnostics/GBD_2013_locations.txt", sep = ""), stringsAsFactors=F)
locs <- locs[,c("ihme_loc_id","level","parent_id","location_id","level_1","level_3")]

## get subnats (we don't treat Hong Kong and Macau as subnats)
subnats <- locs[locs$level_3 == 1 & !(locs$ihme_loc_id %in% c("CHN_354","CHN_361")),]
parents <- locs[locs$level_1 == 1,]

## determine which locations to keep after each level of space time
keep_subnats <- unique(locs$ihme_loc_id[locs$level_1 == 0 & locs$level_3 == 1])
keep_parents <- unique(locs$ihme_loc_id[!(locs$ihme_loc_id %in% keep_subnats)])

# fit space-time for both national and subnational
  reg.sub <- unique(data$region_name[data$ihme_loc_id %in% unique(subnats$ihme_loc_id)])
  preds.sub <- resid_space_time(stdata[stdata$region_name %in% reg.sub & (stdata$ihme_loc_id %in% unique(subnats$ihme_loc_id)),])
  preds.sub <- preds.sub[preds.sub$ihme_loc_id %in% keep_subnats,]
  
  preds.nat <- resid_space_time(stdata[stdata$ihme_loc_id %in% unique(parents$ihme_loc_id),],lambda=lambda, zeta=zeta)
  preds.nat <- preds.nat[preds.nat$ihme_loc_id %in% keep_parents,]
  preds <- rbind(preds.sub,preds.nat)

  data <- merge(data, preds, by=c("ihme_loc_id", "year"))
  data$pred.2.resid <- inv.logit(data$pred.2.resid)
  
  data$pred.2.final <- inv.logit(logit(data$pred.2.resid) + logit(data$pred.1b))  

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)

######################
#causes mort to be adjusted, mort2 unadjusted, mort3 is intermediate step
  data$mort3 <- data$mort2 
  data$mort2 <- data$mort
  data$mort <- data$mort3

# Mean squared error
  se <- (logit(data$mort) - logit(data$pred.2.final))^2
  mse <- tapply(se, data$region_name, function(x) mean(x, na.rm=T)) 
  for (ii in names(mse)) data$mse[data$region_name == ii] <- mse[ii]

###########################
#Get estimate of variance to add on in 03 from taking
#standard deviation of RE for all surveys of a given source-type
#also, try doing this over region
###########################
data$source.type[data$data == 0] <- NA
data$adj.re2 <- data$re2-data$mre2
source.dat <- data[!duplicated(data[,c("ihme_loc_id","source1")]) & data$data == 1,]
sds <- tapply(source.dat$adj.re2, source.dat[,c("source.type")], function(x) sd(x))
sds[is.na(sds)] <- 0
#,"region_name"
var <- sds^2

#merge var into data
for (st in names(sds)){
    data$var.st[data$source.type == st] <- var[names(var) == st]
}

#delta method, log(mx) space to qx space
data$var.st.qx <- data$var.st * (exp(-5*data$mx2) *5* data$mx2)^2
  
# write results files
datas <- data[,c("super_region_name", "region_name", "ihme_loc_id", "year", "LDI_id", "maternal_educ", "hiv", 
                  "data", "category", "corr_code_bias","to_correct","vr", "mort", "mort2", "mse",
                  "pred.1b", "resid", "pred.2.resid", "pred.2.final","ptid","source1","re2", "adjre_fe",
                  "reference", "log10.sd.q5","bias.var", "var.st.qx",
                  "source.yr","source", "type","location_name","ctr_re")]

datas <- datas[order(datas$ihme_loc_id, datas$year, datas$data),]

## add check to see if all the locations are still here
stopifnot(length(unique(data$ihme_loc_id))==all_loc_len)
  
write.csv(data, ifelse(!hivsims,
                         "prediction_model_results_all_stages_GBD2013.txt",
                         paste("prediction_model_results_all_stages_",rnum,".txt",sep = "")),row.names=F)

if(!hivsims) write.csv(data, paste("prediction_model_results_all_stages_GBD2013_", Sys.Date(), ".txt", sep=""),row.names=F)