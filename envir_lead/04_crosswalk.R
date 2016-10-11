#----HEADER----------------------------------------------------------------------------------------------------------------------
# Purpose: Run a linear model to inform the prior of ST-GPR for blood lead
#********************************************************************************************************************************

#----CONFIG----------------------------------------------------------------------------------------------------------------------

# set control flow arguments
run.interactively <- FALSE

# load packages
library(plyr)
library(foreign)
library(splines)
library(boot)
library(reshape2)
library(data.table)
library(stats)
library(lme4)
library(ggplot2)
#********************************************************************************************************************************
 
#----PREP------------------------------------------------------------------------------------------------------------------------
# Read in your model data if you are working interactively
# If running from the central st-gpr, the data will already be read in from the database
if (Sys.info()["sysname"] == "Windows") {
}
#********************************************************************************************************************************
 
#----MODEL------------------------------------------------------------------------------------------------------------------------
## Linear model

# without RFX
mod <- lm(data ~ as.factor(age_group_id) + lt_urban:as.factor(super_region_id) + geometric_mean + outphase_smooth + ln_LDI_pc, 
            data=df, 
            na.action=na.omit)

## Crosswalk your non-gold standard datapoints
# First store the relevant coefficients
coefficients <- as.data.table(coef(summary(mod)), keep.rownames = T)
#********************************************************************************************************************************
 
#----CROSSWALKING DATA-------------------------------------------------------------------------------------------------------------
# Save your raw data/variance for reference
df[, "raw_data" := copy(data)]
df[, "raw_variance" := copy(variance)]

# We will first crosswalk our data based on the results of the regression
# Then, adjust the variance of datapoints, given that our adjusted data is less certain subject to the variance of the regression 

# To do this you will use the formula: Var(Ax + By) = a^2 * Var(x) + b^2 * Var(y) + 2ab * covariance(x,y) 
# (https://en.wikipedia.org/wiki/Variance)
# In our case, the variables are as follows:
# A: geometric_mean
# x: beta for geometric_mean
# B: lt_urban (logit of data urbanicity) - lt_prop_urban (logit of country urbanicity)
# y: beta for urbanicity in a given super_region

# Adjust datapoints to geometric mean
# note that if the variable = 1, that means data is arithmetic (non standard)
# therefore, we want to crosswalk these points down to the geometric mean values
gm_coeff <- as.numeric(coefficients[rn == "geometric_mean", 'Estimate', with=F])
df[, "data" := data - (geometric_mean * gm_coeff)]

# Now adjust the variance for points crosswalked to geometric mean
gm_se <- as.numeric(coefficients[rn == "geometric_mean", 'Std. Error', with=F])
df[, variance := variance + (geometric_mean^2 * gm_se^2)]

# Adjust data urbanicity to the national average
# here, the variable lt_urban represents the urbanicity of the datapoint (in logit)
# whereas the variable lt_prop_urban represents the national average urbanicity (inlogit)
# we want to crosswalk these points as if they are nationally representative
# in order to do this we multiply the beta on urbanicity in that super region by the difference in percent urbanicity between study and national
# ex, if study is 0 (rural) and country is 50% urban, we are multiplying the coefficent by -0.5

# Finally, we will use the above formula to adjust the variance using regression uncertainty

for (this.super.region in unique(df$super_region_id)) {
  
  cat("Adjusting points in super region #", this.super.region, "\n"); flush.console()
  
  # First, we will adjust the data based on urbanicity
  urban_coeff <- as.numeric(coefficients[rn == paste0("lt_urban:as.factor(super_region_id)",this.super.region), "Estimate", with=F])
  
  df[super_region_id == this.super.region, 
     "data" := data - ((lt_urban-lt_prop_urban) * urban_coeff)]
  
  # Now adjust the variance for points crosswalked to urbanicity in a given superregion
  # here we will also take into account the covariance between urbanicity and geometric mean
  urban_se <- as.numeric(coefficients[rn == paste0("lt_urban:as.factor(super_region_id)",this.super.region), "Std. Error", with=F])
  covariance <- vcov(mod)[paste0("lt_urban:as.factor(super_region_id)",this.super.region),"geometric_mean"]
  
  df[super_region_id == this.super.region, 
     variance := variance + ((lt_urban-lt_prop_urban)^2 * urban_se^2) + (2*(geometric_mean*(lt_urban-lt_prop_urban)) * covariance)]
  
}
# First reset all study level covariates to predict as the gold standard
# Also save the originals for comparison
df[, geometric_mean_og := geometric_mean]
df[, geometric_mean := 0]

df[, lt_urban_og := lt_urban]
df[, lt_urban := lt_prop_urban] # decided to use logit transform on this cov

# Save df with all crosswalk result variables for examination
write.csv(df, paste0(run_root, "/crosswalk_results.csv"), row.names=FALSE, na="")

# Clean up dataset for input to ST-GPR
df <- df[, c("ihme_loc_id",
             "location_id",
             "year_id",
             "age_group_id",
             "sex_id",
             "data",
             "standard_deviation",
             "variance",
             "sample_size",
             "ln_LDI_pc",
             "lt_urban",
             "outphase_smooth",
             "super_region_id",
             "region_id",
             "me_name",
             "nid",
             "age_start",
             "train"),
         with=F]

