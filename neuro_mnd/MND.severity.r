#
# MND.severity.R
#
#-- set up working directories

#jpath <- ifelse(Sys.info()[["sysname"]] == "Windows", "J:/", "/home/j/")
#hpath <- ifelse(Sys.info()[["sysname"]] == "Windows", "H:/", "/homes/strUser/")
hpath <-"/Volumes/IHME/HOME/strUser/"
jpath <-"/Volumes/IHME/snfs/"
raw_dir <- paste0(jpath, "DATA/Incoming Data/PRO-ACT/")
dir.create(file.path(raw_dir), showWarnings = FALSE)
data_dir <- paste0(hpath, "GBD/MND/")
dir.create(file.path(data_dir), showWarnings = FALSE)

zipfiles <- list.files(raw_dir, pattern = c("zip"))
datafiles <- list.files(data_dir)
##unzip to data_dir
for (i in zipfiles)
unzip(paste0(raw_dir, i))

###
#create function to calculate age of onset and age of dx(in years) from age of trial
###
est.age <-function(age, days){
  new.age <- round((age*365.24 - days)/365.24, digit = 3)
}

a.onset <- est.age(36, -234)

###collorate all datasets
#
infiles <- datafiles[grep("Data.csv", datafiles)]

dtypes = c(
  alsfrs = paste0(data_dir, infiles[1]),
  death  = paste0(data_dir, infiles[2]),
  demo  = paste0(data_dir, infiles[3]),
  #famhx  = paste0(data_dir, infiles[4]),
  fvc  = paste0(data_dir, infiles[5]),
  subjhx  = paste0(data_dir, infiles[6]),
  svc  = paste0(data_dir, infiles[7]),
  trt  = paste0(data_dir, infiles[8])
)

library(Hmisc)
##like &macro assignment in SAS
sink("datasummary.txt")
for (type in names(dtypes)) {
  
  assign(paste0("dat_", type),
         read.csv(dtypes[type]))
  
  cat(paste0("\n", type))
  print(str(get(paste0("dat_", type))))
  print(describe(get(paste0("dat_", type))))
}
sink()
###clean dat_death
  dat_death <- subset(dat_death, dat_death$Subject.Died!="")  #eliminate rows with missing subject ids
  dat_death$SubjectID <-as.integer(as.character(dat_death$SubjectID))

###clean dat_alsfrs
  dat_alsfrs <- dat_alsfrs[,-c(20:21)]  #delete two columns with all missing data

##clean subjhx
  dat_subjhx <- dat_subjhx[,-c(5:8, 10, 14)] 

###clean svc
  dat_svc <- dat_svc[,-c(11)]

###combine all "type" by Subject ID
  all.dat <- paste0("dat_", names(dtypes))

###drop FORMID
  dat_alsfrs$FormID <- NULL
  dat_death$FormID <- NULL
  dat_demo$FormID <- NULL 
  dat_fvc$FormID <- NULL   
  dat_subjhx$FormID <- NULL
  dat_svc$FormID <-NULL  
  dat_trt$FormID <-NULL 

##combine data
  f.df <-Reduce(function(x, y) merge(x, y, by = "SubjectID", all = TRUE), 
                list(dat_alsfrs, dat_death, dat_demo, dat_subjhx, dat_trt)) 
                                                    #takeout fvc and svc data for now

  f.df$SubjectID <- as.integer(as.character(f.df$SubjectID))
  f.df <- f.df[order(f.df$SubjectID, f.df$ALSFRS.Delta),]
  save(f.df, file="f.df.RData")

length(unique(f.df$SubjectID))  #8635 enrolled in the database.
#with ALFSR data
 dat <- subset(f.df, f.df$SubjectID!='NA' & f.df$ALSFRS.Delta!='NA')
 length(unique(dat$SubjectID))  #4838 with ALSFRS.Delta
#with ALFSR data and age at enrollment
 dat <- subset(f.df, f.df$SubjectID!='NA' & f.df$ALSFRS.Delta!='NA' & f.df$Age !='NA')
 length(unique(dat$SubjectID))  #4838 with ALSFRS.Delta and age now
###saved data with complete severity score
save(data, file="f.ALSFRS.RData")
###check how the 4838 assessed fall in the treatment arms
library(doBy)
sumout<-summaryBy(ALSFRS.Delta + ALSFRS.R.Total + ALSFRS.Total~ SubjectID + Study.Arm + Subject.Died, data=f.df,
              FUN=function(x){c(min=min(x),max=max(x), mean=mean(x))})
    #among all subjects

head(sumout)

sumout.1<-summaryBy(ALSFRS.Delta + ALSFRS.R.Total + ALSFRS.Total~ SubjectID + Study.Arm + Subject.Died + Age +age.delta, data=dat,
                              FUN=function(x){c(min=min(x),max=max(x), mean=mean(x))})
  ##among only ALSFRS data

#take the first or last id check first
myid.uni <- unique(dat$SubjectID)
a<-length(myid.uni)

last.dat <- c()
for (i in 1:a) {
  temp<-subset(dat, dat$SubjectID==myid.uni[i])
  if (dim(temp)[1] > 1) {
    last.temp<-temp[dim(temp)[1],]
  }
  else {
    last.temp<-temp
  }
  last.dat<-rbind(last.dat, last.temp)
}
head(last.dat)    ###dataset taking the last last accessment of ALSFRS


#take the first or last id check first
myid.uni <- unique(dat$SubjectID)
a<-length(myid.uni)

first.dat <- c()
for (i in 1:a) {
  temp<-subset(dat, dat$SubjectID==myid.uni[i])
  if (dim(temp)[1] > 1) {
    first.temp<-temp[1,]
  }
  else {
    first.temp<-temp
  }
  first.dat<-rbind(first.dat, first.temp)
}
head(first.dat)    ###dataset taking the first accessment of ALSFRS

sink("sumoffirst.last.txt")
summary(first.dat)
summary(last.dat)
sink()
sumout.first<-summaryBy(.~ SubjectID + Study.Arm + Subject.Died + Age +age.delta, data=dat,
                    FUN=function(x){c(min=min(x),max=max(x), mean=mean(x))})


first.dat$dtyp <- 'first'
last.dat$dtyp <- 'last'
dat$dtyp      <- 'all'
sumout.first$dtyp <-'sumstat'
#and combine into your new data frame vegLengths

library(ggplot2)
ggplot(com.dat[,c(14,45)], aes(length, fill = dtyp)) + geom_density(alpha = 0.2)

#find why imputed ie non-integer numbers are imputed  "dat" has data with ALSFRS

nonint.dat <- subset(dat, dat$ALSFRS.Total %% floor(dat$ALSFRS.Total) !=0|
                       dat$ALSFRS.Total %% floor(dat$ALSFRS.Total) !=0)

#ifelse(<condition>,<yes>,ifelse(<condition>,<yes>,<no>))
#ifelse(<condition>,ifelse(<condition>,<yes>,<no>),<no>)
#ifelse(<condition>,ifelse(<condition>,<yes>,<no>),ifelse(<condition>,<yes>,<no>))
#ifelse(<condition>,<yes>,ifelse(<condition>,<yes>,ifelse(<condition>,<yes>,<no>)))

#change to one colum of Total
#nonint.dat$Total <- ifelse(!is.na(nonint.dat$ALSFRS.Total), nonint.dat$Total <- nonint.dat$ALSFRS.Total, 
       #ifelse(!is.na(nonint.dat$ALSFRS.R.Total), nonint.dat$Total <-nonint.dat$ALSFRS.R.Total,
              #nonint.dat$Total <- NA))


describe(nonint.dat)

#pairs(nonint.dat[, 2:4])
library(GGally)
pdf("pairplots_imp_scores.pdf")
ggpairs(nonint.dat[,c(14, 19, 23, 30, 42)],
        columns=1:5, 
        title="Imputed ALSFRS scores",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        colour="Study.Arm",
        axisLabels='show')
dev.off()

pdf("pairplots.pdf")
ggpairs(dat[,c(14, 19, 23, 30, 42)],
        columns=1:5, 
        title="ALSFRS scores",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        colour="Study.Arm",
        axisLabels='show')
dev.off()
lower=list(continuous="smooth", combo="box", params=c(colour="gray20", fill="gray20", alpha=1/4)),
# lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
# colour="gender",  


#plot by summary measure to access the repeated data baseline vs end of fu and age.
pdf("checkingage_rpeated.2.pdf", onefile = TRUE, w=20, h=20)
ggpairs(sumout.1[,2:13],
        columns=1:11, 
        title="Age and Repeated measures",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        colour="Study.Arm",
        axisLabels='show')
dev.off()
####didn't differ by age, arm, subject id
pdf("checkingage_rpeated.3.pdf", onefile = TRUE, w=20, h=20)
ggpairs(sumout.1[,c(5, 7, 6, 8, 10, 9, 11, 13, 12)],
        columns=1:9, 
        title="Age and Repeated measures",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        axisLabels='show')
dev.off()

###
###check if age is associated with ALS scores.
###no strong association to age 8/19/15
dat$age.delta <- round((dat$Age*365.24 + dat$ALSFRS.Delta)/365.24, digit=3)
#plot out age related to ALS scores
pdf("age_scores.2.pdf", w=15, h=15)
ggpairs(dat[,c(13, 14, 23, 30, 42, 44)],
        columns=1:6, 
        title="ALSFRS scores",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        colour="Study.Arm",
        axisLabels='show')
dev.off()

pdf("age_scores.3.pdf", w=15, h=15)
ggpairs(dat[,c(13, 14, 15, 30, 44)],  #futime, Scores, Age, Age+fu
        columns=1:5, 
        title="ALSFRS scores",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        axisLabels='show')
dev.off()  

#com.dat combined first.dat and last.dat by dtyp
pdf("comparefrt.last.3.pdf", w=15, h=15)
png("comparefrt.last.3.png", width = 880, height =880)
ggpairs(com.dat[,c(13, 14, 15, 30, 43, 44, 45)],  #futime, Scores, Age, Age+fu
        columns=1:7, 
        title="ALSFRS scores",
        lower=list(continuous="smooth", combo="box", params=c(alpha=1/4)),  # if use group
        colour="dtyp",
        axisLabels='show')
dev.off()  


##distribution between first.dat and all.dat similar#######################################
save(first.dat, file=paste0(data_dir, "fist.dat.RData"))  #scores of just the minimum time point
save(last.dat, file=paste0(data_dir, "last.dat.RData"))  #scores of just the maximum time point
save(dat, file=paste0(data_dir,"all.dat.Rdata"))     #all scores, subjects without scores omitted.
save(sumout.first, file =paste0(data_dir, "sumout.first.Rdata"))  #min, max, mean of all variables.
#####################################################################################

ggplot(data=com.dat, aes(x=ALSFRS.Total, colour=dtyp)) +
  geom_density( )
####7/3/2015
library(Hmisc)
describe(dat)
###
#[1] "SubjectID"                            "X1..Speech"                          
#[3] "X10..Respiratory"                     "X2..Salivation"                      
#[5] "X3..Swallowing"                       "X4..Handwriting"                     
#[7] "X5a..Cutting.without.Gastrostomy"     "X5b..Cutting.with.Gastrostomy"       
#[9] "X6..Dressing.and.Hygiene"             "X7..Turning.in.Bed"                  
#[11] "X8..Walking"                          "X9..Climbing.Stairs" 
library(gmodels)
CrossTable(first.dat$Study.Arm, missing.include=TRUE)

CrossTable(first.dat$ALSFRS.Total, missing.include=TRUE)
CrossTable(first.dat$ALSFRS.R.Total, missing.include=TRUE)
CrossTable(first.dat$R.1..Dyspnea, missing.include=TRUE)
CrossTable(first.dat$R.2..Orthopnea, missing.include=TRUE)
CrossTable(first.dat$R.3..Respiratory.Insufficiency, missing.include=TRUE)

###
#subjectID 862885 have X4 missing imputed with from total which 33.33 and X4=3.33 so X4 assigned 3.5
#newdat
motor2 <- first.dat$X4 + first.dat
hist(first.dat$X4..Handwriting)
hist(first.dat$X5a..Cutting.without.Gastrostomy, add=T)
hist(first.dat$X5b..Cutting.with.Gastrostomy, add=T)
hist(first.dat$X6..Dressing.and.Hygiene, add=T)

ggplot(dat, aes(x=rating)) + geom_histogram(binwidth=.5, colour="black", fill="white") + 
  facet_grid(cond ~ .)

CrossTable(is.na(first.dat$X5b..Cutting.with.Gastrostomy),is.na(first.dat$X5a..Cutting.without.Gastrostomy), missing.include=TRUE)
test <-subset(first.dat, is.na(first.dat$X5b..Cutting.with.Gastrostomy)&is.na(first.dat$X5a..Cutting.without.Gastrostomy))

#original data with first observation that is NA
miss.x5 <-subset(dat, dat$SubjectID %in% c(test$SubjectID))

###take the first non missing rows of data
library(data.table)                                                                                                                                                                                 DT[, head(.SD, 4), by = Species] ## first four rows of each group
DT <- data.table(miss.x5, key="SubjectID")
DT.2 <-DT[!is.na(X5a..Cutting.without.Gastrostomy)]
DT.3<-DT.2[J(unique(SubjectID)), mult = "first"]  ##add this to final first.dat

DF <-data.table(first.dat, key="SubjectID")
DF.2 <-DF[!(SubjectID %in% c(test$SubjectID))]

f.first.dat<-rbind(DT.3, DF.2)  ###updated with non-NA [1] 138093 204799 226657 330811 913848 had NA in Q5a
CrossTable(is.na(f.first.dat$X5b..Cutting.with.Gastrostomy),is.na(f.first.dat$X5a..Cutting.without.Gastrostomy), missing.include=TRUE)

DA <-data.table(f.first.dat, key="SubjectID")
DA[is.na(X4..Handwriting)]  ##862885 X4 place 3 from total 33.33
DA[is.na(X2..Salivation)]   ##914025

ALL <-data.table(dat, key="SubjectID")
ALL.2 <-ALL[SubjectID==914025&!is.na(X2..Salivation)]
ALL.3 <-ALL.2[J(unique(SubjectID)), mult = "first"]   #914025 with first NA of Q2

TEMP<-DA[SubjectID!=914025]
TEMP.2 <-TEMP[SubjectID==862885, X4..Handwriting:=3]
f.first.dat <-rbind(TEMP.2, ALL.3)
save(f.first.dat, file=paste0(data_dir, "f.first.dat.Rdata"))

####just looking at the first observation
##look at distribution of sum of Q8 and Q9
library(data.table)
TEMP <- data.table(f.first.dat, key="SubjectID")
TEMP <-TEMP[,Motor.lower:= sum(X8..Walking, X9..Climbing.Stairs), by=SubjectID]  #Motor.lower

##look at distribution of sum of Q4, Q5, Q6
TEMP <-TEMP[,Motor.upper:= sum(X4..Handwriting, X5a..Cutting.without.Gastrostomy, X5b..Cutting.with.Gastrostomy
                               ,X6..Dressing.and.Hygiene, na.rm = TRUE), by=SubjectID]   #Motor.upper
TEMP[,{hist(Motor.upper,col="red") 
          hist(Motor.lower,col="blue", add=T)
          NULL}]


load(file="/Volumes/IHME/HOME/strUser/GBD/MND/last.dat.RData")
TEMP.2 <- data.table(last.dat, key="SubjectID")
library(Hmisc)
describe(TEMP.2)
  #missing 5a, 5b, 7, 8, 9
TEMP.2[,{CrossTable(is.na(X5b..Cutting.with.Gastrostomy),
                    is.na(X5a..Cutting.without.Gastrostomy), missing.include=TRUE)
                  NULL}]  #n=5 where both X5a and X5b are missing
test <-subset(last.dat, is.na(last.dat$X5b..Cutting.with.Gastrostomy)&is.na(last.dat$X5a..Cutting.without.Gastrostomy))

#original data with last observation that is NA
miss.x5 <-subset(dat, dat$SubjectID %in% c(test$SubjectID))

###take the first non missing rows of data
library(data.table)                                                                                                                                                                                 DT[, head(.SD, 4), by = Species] ## first four rows of each group
DT <- data.table(miss.x5, key="SubjectID")
DT.2 <-DT[!is.na(X5a..Cutting.without.Gastrostomy)]
DT.3<-DT.2[J(unique(SubjectID)), mult = "last"]  ##add this to final last.dat

DF <-data.table(last.dat, key="SubjectID")
DF.2 <-DF[!(SubjectID %in% c(test$SubjectID))]

f.first.dat<-rbind(DT.3, DF.2)  ###updated with non-NA [1] 138093 204799 226657 330811 913848 had NA in Q5a
CrossTable(is.na(f.first.dat$X5b..Cutting.with.Gastrostomy),is.na(f.first.dat$X5a..Cutting.without.Gastrostomy), 
           missing.include=TRUE)

TEMP.2 <-TEMP.2[,Motor.lower:= sum(X8..Walking, X9..Climbing.Stairs), by=SubjectID]  #Motor.lower

##look at distribution of sum of Q4, Q5, Q6
TEMP.2 <-TEMP.2[,Motor.upper:= sum(X4..Handwriting, X5a..Cutting.without.Gastrostomy, X5b..Cutting.with.Gastrostomy
                               ,X6..Dressing.and.Hygiene, na.rm = TRUE), by=SubjectID]   #Motor.upper
TEMP.2[,{hist(Motor.upper,col="red",main = "Last obs:Red-Motor.upper, Blue-Motor.lower" )
       hist(Motor.lower,col="blue", add=T)
       NULL}]
f.last.dat <-TEMP.2
save(f.last.dat, file=paste0(data_dir, "f.last.dat.Rdata"))

#####looking at the all##############################################################
##Include the repeated data as independent data points.
load(file=paste0(data_dir,"all.dat.Rdata"))     #all scores, subjects without scores omitted.
library(Hmisc)
describe(dat)
###
#[1] "SubjectID"                            "X1..Speech"                          
#[3] "X10..Respiratory"                     "X2..Salivation"                      
#[5] "X3..Swallowing"                       "X4..Handwriting"                     
#[7] "X5a..Cutting.without.Gastrostomy"     "X5b..Cutting.with.Gastrostomy"       
#[9] "X6..Dressing.and.Hygiene"             "X7..Turning.in.Bed"                  
#[11] "X8..Walking"                          "X9..Climbing.Stairs" 

whymiss <-subset(dat, is.na(dat$ALSFRS.R.Total)&is.na(dat$ALSFRS.Total)) #those data with missing total scores deleted from the final data
describe(whymiss)
whymiss2 <-subset(dat, is.na(dat$Study.Arm))$SubjectID   #subjects those not placed in study arms.
  #538, alot more subjects not placed in study arms

datcheck <-subset(dat, dat$SubjectID %in% c(whymiss$SubjectID))
 #Subject ID-7468 168510 204799 408104 528824 658228 736120  have missing total score, 
#they will just be omitted from the final analysis
  #just one data line would be missing where both R.total and total are missing

library(gmodels)
CrossTable(dat$Study.Arm, missing.include=TRUE)

CrossTable(dat$ALSFRS.Total, missing.include=TRUE)
CrossTable(dat$ALSFRS.R.Total, missing.include=TRUE)
CrossTable(is.na(dat$ALSFRS.R.Total), is.na(dat$ALSFRS.Total))  #seven id's where both NA's same as line #463

CrossTable(dat$R.1..Dyspnea, missing.include=TRUE)
CrossTable(dat$R.2..Orthopnea, missing.include=TRUE)
CrossTable(dat$R.3..Respiratory.Insufficiency, missing.include=TRUE)

#ggplot(dat, aes(x=rating)) + geom_histogram(binwidth=.5, colour="black", fill="white") + 
  #facet_grid(cond ~ .)

CrossTable(is.na(dat$X5b..Cutting.with.Gastrostomy),is.na(dat$X5a..Cutting.without.Gastrostomy), missing.include=TRUE)  #n=39 missing where X5b and X5a missing
test <-subset(dat, is.na(dat$X5b..Cutting.with.Gastrostomy)&is.na(dat$X5a..Cutting.without.Gastrostomy))

  #will treat use all data points if any of them missing will just be dropped from the final analyses
library(data.table)  
dat.2<-subset(dat, !(is.na(dat$ALSFRS.R.Total)&is.na(dat$ALSFRS.Total)))  
        #only include data with either total scores available
TEMP.3 <- data.table(dat.2, key="SubjectID")  #for all data we can just take the original data.

TEMP.3 <-TEMP[,Motor.lower:= sum(X8..Walking, X9..Climbing.Stairs), by=SubjectID]  #Motor.lower
##look at distribution of sum of Q4, Q5, Q6
TEMP.3 <-TEMP[,Motor.upper:= sum(X4..Handwriting, X5a..Cutting.without.Gastrostomy, X5b..Cutting.with.Gastrostomy
                               ,X6..Dressing.and.Hygiene, na.rm = TRUE), by=SubjectID]   #Motor.upper
TEMP.3[,{hist(Motor.upper,col="red") 
  hist(Motor.lower,col="blue", add=T)
  NULL}]

test<-subset(TEMP.3, is.na(TEMP.3$ALSFRS.R.Total)&is.na(TEMP.3$ALSFRS.Total))  #0 case so good
f.dat <-test
save(f.dat, file=paste0(data_dir, "f.all.dat.Rdata"))

