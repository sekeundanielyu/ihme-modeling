##Filename: pm2.5_lmer.r
##PURPOSE: RUN MIXED EFFECT MODEL IN R

#Housekeeping
rm(list = ls())
library(lme4)
library(MASS)
set.seed=32523523

#READ IN the DATASET
data <-read.csv("J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/lmer_input_2Jun2016.csv")

##SAVE A LOG FILE 
sink(file="J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/R_log_2Jun2016.txt")

# Run mixed effect regression 
# THE MODEL WASN'T STABLE TO BEGIN WITH AND THIS HAD A BIG EFFECT ON THE MODEL
#lm.re <- lmer(logpm ~ maternal_educ + (1 | gbd_analytical_superregion_id) + (1 | gbd_analytical_region_id) + (1 | iso3), data = data)

#MATERNAL EDUCATION WAS DROPPED AND THIS MODEL WAS USED BECAUSE WE LATER FOUND MATERNAL EDUCATION TO BE NO LONGER SIGNIFCANT
lm.re <- lmer(logpm ~ (1 | super_region_id) + (1 | region_id) + (1 | ihme_loc_id), data = data)

# Extract draws of coefficients and intercept--there is no fixed effect since no covariate is significantly associated with PM2.5 level
#fe_sims <- matrix(rnorm(1000, fixef(lm.re)[2], sqrt(vcov(lm.re)[2,2])), nr=1, nc=1000, byrow=F)
constant_sims <- matrix(rnorm(1000, fixef(lm.re)[1], sqrt(vcov(lm.re)[1,1])), nr=1, nc=1000, byrow=F)

#write.csv(fe_sims,"J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/fe_sims.csv")
write.csv(constant_sims, "J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/const_sims.csv")

#Extract random effect by iso3(ihme_loc_id)
iso3_re <- ranef(lm.re, condVar=T) [[1]]
iso3_var <- as.vector(attr(iso3_re, "postVar"))
iso3_sims <- cbind(data.frame(ihme_loc_id = rownames(iso3_re)), matrix(NA, nr = length(rownames(iso3_re)), nc = 1000))

for (x in 1:length(rownames(iso3_re))){
  iso3_sims[x,2:1001]<-rnorm(1000, as.vector(unlist(iso3_re))[x], sqrt(iso3_var[x]))
}

write.csv(iso3_sims, "J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/iso3_re_sims.csv")

#Extract RE by analytical region
region_re <- ranef(lm.re, condVar=T) [[2]]
region_var <- as.vector(attr(region_re, "postVar"))
region_sims <- cbind(data.frame(region_id = rownames(region_re)), matrix(NA, nr = length(rownames(region_re)), nc = 1000))

for (r in 1:length(rownames(region_re))) {
  region_sims[r, 2:1001]<-rnorm(1000, as.vector(unlist(region_re))[r], sqrt(region_var[r]))
}

write.csv(region_sims, "J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/region_re_sims.csv")

#Extract RE by analytical superregion
superregion_re <- ranef(lm.re, condVar=T) [[3]]
superregion_var <- as.vector(attr(superregion_re, "postVar"))
superregion_sims <- cbind(data.frame(super_region_id = rownames(superregion_re)), matrix(NA, nr=length(rownames(superregion_re)), nc = 1000))

 # as.data.frame(matrix(NA, nr=nrow(data), nc=1000))
for (s in 1:length(rownames(superregion_re))) {
  superregion_sims[s, 2:1001] <- rnorm(1000, as.vector(unlist(superregion_re))[s], sqrt(superregion_var[s]))
}

write.csv(superregion_sims, "J:/WORK/05_risk/risks/air_hap/02_rr/02_output/PM2.5 mapping/lit_db/superregion_re_sims.csv")

##POPULATE LOG FILE 

print("MODEL")
summary(lm.re)

print("COUNTRY")
ranef(lm.re, condVar=T) [[1]]
as.vector(attr(iso3_re, "postVar"))

print("REGION")
ranef(lm.re, condVar=T) [[2]]
as.vector(attr(region_re, "postVar"))

print("SUPERREGION") 
ranef(lm.re, condVar=T) [[3]]
as.vector(attr(superregion_re, "postVar"))

sink()

## Predict 1,000 draws for all country years
##assign(paste0("pred"), as.data.frame(matrix(NA, nrow = nrow(data), ncol = 1000)))
##tmp_df <- get(paste0("pred"))
##for (j in 1:1000) { 
##  tmp_df[,j] <- fe_sims[,j]*data$maternal_educ + iso3_sims[,j] + region_sims[,j] + superregion_sims[,j] + constant_sims[,j]
##}

##write.csv(tmp_df,"J:/WORK/05_risk/01_database/02_data/air_hap/02_rr/04_models/output/pm_mapping/pm_pred_15July2015.csv")

#######################################################################

