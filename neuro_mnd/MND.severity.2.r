#############
#Severity datatset created in MND.severity.R
#7/5/15
#load(first.dat, file="fist.dat.RData")  #scores of just the minimum time point
#load(last.dat, file="last.dat.RData")  #scores of just the maximum time point
#load(dat, file="all.dat.Rdata")     #all scores, subjects without scores omitted.
#load(sumout.first, file = "sumout.first.Rdata")  #min, max, mean of all variables.

load(file="/Volumes/strUser/GBD/MND/f.first.dat.Rdata")  #cleaned out score of just the minimum time point
##Alogirthm to categorize severity into mild, moderate, severe, none
dat <- f.first.dat
#  1. (motor function: walking stairs):
#      create first motor impairment severity rating based on 8 and 9 of ALSFRS 
#     for motor functioning  of lower part  body
# Q8:walking, Q9: climing stairs

#- if sum(Q8+Q9) =8 --> none
#- else if sum(Q8+Q9) =7-5 --> mild
#- else if sum(Q8+Q9) =4-2 --> moderate
#- else if sum(Q8+Q9) =1-0 --> severe
#
  dat$motorlow = dat$X8..Walking + dat$X9..Climbing.Stairs
  dat$motorlow.c[dat$motorlow == 8 ] <- "none"
  dat$motorlow.c[5 <= dat$motorlow & dat$motorlow <= 7 ] <- "mild"
  dat$motorlow.c[2 <= dat$motorlow & dat$motorlow <= 4 ] <- "moderate"
  dat$motorlow.c[0 <= dat$motorlow & dat$motorlow <= 1 ] <- "severe"  
#2. (Motor function:other):
#  create second motor impairment severity rating based on 4-6 of ALSFRS 
#   for motor functioning  of upper part  body
# Q4:handwriting, Q5:cutting food and handling utensils, Q6: dressing and hygiene
#
#- if sum(Q4+Q5+Q6) =12 --> none
#- else if sum(Q4+Q5+Q6) =11-9 --> mild
#- else if sum(Q4+Q5+Q6) =8-3 --> moderate
#- else if sum(Q4+Q5+Q6) =2-0 --> severe
#
  Q5 = ifelse(is.na(dat$X5a..Cutting.without.Gastrostomy)==TRUE, dat$X5b..Cutting.with.Gastrostomy, 
               dat$X5a..Cutting.without.Gastrostomy)
  dat$motorup = dat$X4..Handwriting + Q5 + dat$X6..Dressing.and.Hygiene
  dat$motorup.c[dat$motorup == 12 ] <- "none"
  dat$motorup.c[9 <= dat$motorup & dat$motorup <= 11 ] <- "mild"
  dat$motorup.c[3 <= dat$motorup & dat$motorup <= 8 ] <- "moderate"
  dat$motorup.c[0 <= dat$motorup & dat$motorup <= 2 ] <- "severe"  

#3. (motor:combined):
#   make composite of two motor impairment categories assuming :
#
#  - if any one is severe --> severe
# -  else if anyone is moderate but none severe: --> moderate
# - else if anyone is mild but none severe or moderate --> mild
# - else rest --> none
#
  dat$motor.c = ifelse(dat$motorlow.c == "severe" |dat$motorup.c =="severe", "severe", 
                      ifelse(dat$motorlow.c == "moderate" | dat$motorup.c =="moderate", "moderate", 
                      ifelse(dat$motorlow.c == "mild" | dat$motorup.c =="mild", "mild", "none"))) 
  
#4. (COPD):
#  classify respiratory symptoms based on Q10 or, if missing, Q R-1  if ALSFRS-R was used
# Q10:breathing
#
#- 4(normal) = none
#- 3(shortness of breath with min. exertion) = mild
#- 2(shortness of breat at rest) = moderate
#- 1-0(intermitte ventilatory assistance required/ventiliator dependent) = severe
#
# QR-1:Dyspnea
#- 4(normal) = none
#- 3(shortness of breath with min. exertion) = mild
#- 2(shortness of breat at rest) = moderate
#- 1-0(intermitte ventilatory assistance required/ventiliator dependent) = severe
#
  Q10.R1 = ifelse(is.na(dat$X10..Respiratory)==TRUE, dat$R.1..Dyspnea, dat$X10..Respiratory)
  dat$resp = Q10.R1
  dat$resp.c[dat$resp == 4 ] <- "none"
  dat$resp.c[dat$resp == 3 ] <- "mild"
  dat$resp.c[dat$resp == 2 ] <- "moderate"
  dat$resp.c[dat$resp == 1 ] <- "severe"  
  
#5. (speech):
# Classify speech problems
#Q1:Speech
#
#- 4(normal) --> No/none
#- 3-0(detectable speech distrubance/intelligible with repeating) --> yes
#
  dat$spchprob.c = ifelse(dat$X1..Speech==4, "none", "yes")
  
#6. Cases with none of the above get the DW for generic disease with worry; 
#   apply that DW also to those with  mild motor impairment only as the DW for 
#   that is a bit lower than that for generic disease with worry

###obtaing disability weights  
dw <-  read.csv("/Volumes/IHME/snfs/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw_full.csv", 
               header=T, stringsAsFactors=F)
            #above data needs to be replaces with GBD 2015 run.
mnd = unlist(c("copd_mild", "copd_mod", "copd_sev", "generic_anxiety", 
               "motor_mild", "motor_mod", "motor_sev", "speech_problems"),use.names=F)
  
dw = dw[which(dw$healthstate %in% mnd),]
#dw$mean.dw = rowMeans(dw[,4:length(dw)], 1)
write.csv(dw, file="/Volumes/strUser/GBD/MND/mnd_dw.csv",quote=F, row.names=F) 
save(dw, file="/Volumes/strUser/GBD/MND/mdn_dw.Rdata")
temp = dw[,-(1:3)]
rownames(temp) = dw$healthstate
tdw = as.data.frame(t(temp))

dw.eq = function(copd, spch, motor){
  dw = 1-(1-copd)*(1-spch)*(1-motor)
  return(dw)
}
  
  
###assigning dw for motor, speech, COGD and generic worry for MND scoring
alg.mnd.dw = function(j){
  speech.dw = ifelse(dat$spchprob.c[j] =="none", 0, tdw$speech_problems)

  if (dat$motor.c[j] =="none"){
    if(dat$resp.c[j]=="none"){
      mnd.dw = tdw$generic_anxiety}
    else if(dat$resp.c[j] == "mild"){
      mnd.dw = dw.eq(tdw$copd_mild, speech.dw, 0)}
    else if(dat$resp.c[j] == "moderate"){
      mnd.dw = dw.eq(tdw$copd_mod, speech.dw, 0)}
    if(dat$resp.c[j] == "severe"){
      mnd.dw = dw.eq(tdw$copd_sev, speech.dw, 0)}}
  else if(dat$motor.c[j] =="mild"){
     if(dat$resp.c[j]=="none"){
       mnd.dw = min(tdw$generic_anxiety, dw.eq(0, speech.dw, tdw$motor_mild))}  
                          #either generic worry or motor mild whichever is less for DW
     else if(dat$resp.c[j] == "mild"){
       mnd.dw = dw.eq(tdw$copd_mild, speech.dw, tdw$motor_mild)}
     else if(dat$resp.c[j] == "moderate"){
       mnd.dw = dw.eq(tdw$copd_mod, speech.dw, tdw$motor_mild)} 
    else if(dat$resp.c[j] == "severe"){
      mnd.dw = dw.eq(tdw$copd_sev, 0, tdw$motor_mild)}}
  else if(dat$motor.c[j] =="moderate"){
    if(dat$resp.c[j]=="none"){
      mnd.dw = dw.eq(0, speech.dw, tdw$motor_mod)}
    else if(dat$resp.c[j] == "mild"){
      mnd.dw = dw.eq(tdw$copd_mild, speech.dw, tdw$motor_mod)}
    else if(dat$resp.c[j] == "moderate"){
      mnd.dw = dw.eq(tdw$copd_mod, speech.dw, tdw$motor_mod)} 
    else if(dat$resp.c[j] == "severe"){
      mnd.dw = dw.eq(tdw$copd_sev, speech.dw, tdw$motor_mod)}}
  else if(dat$motor.c[j] =="severe"){
    if(dat$resp.c[j]=="none"){
      mnd.dw = dw.eq(0, speech.dw, tdw$motor_sev)}
    else if(dat$resp.c[j] == "mild"){
      mnd.dw = dw.eq(tdw$copd_mild, speech.dw, tdw$motor_sev)}
    else if(dat$resp.c[j] == "moderate"){
      mnd.dw = dw.eq(tdw$copd_mod, speech.dw, tdw$motor_sev)} 
    else if(dat$resp.c[j] == "severe"){
      mnd.dw = dw.eq(tdw$copd_sev, speech.dw, tdw$motor_sev)}}
    return(mnd.dw)
}

###create the disability weights for Motor neurone disease
temp = NULL
mnd.dw.dat = NULL
t.mnd.dw.dat = NULL
temp <- vector("list", nrow(tdw))
for(i in 1:nrow(dat)){
    temp[[i]]= alg.mnd.dw(i)
}
mnd.dw.dat = as.data.frame(rbind(mnd.dw.dat, do.call(rbind, temp)))
#t.mnd.dat = as.data.frame(t(mnd.dw.dat))
rownames(mnd.dw.dat) = dat$SubjectID
colnames(mnd.dw.dat) =  paste("MND.dw.",seq(1, 1000, 1), sep="")
sum.stat = sapply(1:4838, function(i){
          c(mean(as.numeric(mnd.dw.dat[i,1:1000])),
                  quantile(as.numeric(mnd.dw.dat[i,1:1000]), probs = c(0.05, 0.95)))})
sum.dat = as.data.frame(t(sum.stat))
colnames(sum.dat) = c("MND.dw.mean", "MND.dw.lo95", "MND.dw.hi95")

f.mnd.dat = cbind(mnd.dw.dat, sum.dat)
write.csv(f.mnd.dat , file="/Volumes/strUser/GBD/MND/sumstat_mnd_dw.csv",quote=F, row.names=F)
save(f.mnd.dat, file="/Volumes/strUser/GBD/MND/sumstat_mnd_dw.Rda")
