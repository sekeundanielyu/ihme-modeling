############################################################
# Estimate Beta Distribution for BMI 
# Inputs: outputs from mean BMI, prevalence of overweight and obesity by age, sex, country
# Outputs: shape1, shape2, MM (shifting parameter), scale
################# SET UP ####################################

# Set path to j drive
os <- .Platform$OS.type
if (os=="windows") {
  lib_path <- "J:/WORK/01_covariates/common/lib/"
  jpath_01 <- "J:/"
} else {
  lib_path <- "/home/j/WORK/01_covariates/common/lib/"
  jpath_01 <- "/home/j/"
}

# define args and i_iso3, when submitting job to cluster, these will be defined in submit_run_gpr script
args <- commandArgs(trailingOnly = TRUE)
i_iso3 <- ifelse(!is.na(args[1]),args[1], 160) # take location_id
i_sex<-ifelse(!is.na(args[2]), args[2], 1) # take sex_id
i_year<-ifelse(!is.na(args[3]), args[3], 1990) # take year_id
bmi_path <- args[4] # take bmi path
ow_path <- args[5] # take ow path
ob_path <- args[6] # take ob path
beta_version <- args[7]

############################################## OPTIMIZATION FUNCTIONS ##################################################################################
# function to be optimized
  M_fn<-function(m, para){ #m refers to the observed estimates, para are the parameters. parameters 1 and 2 are shape 1 and 2, parameter 3 is shifting parameter, and parameter 4 is scaling
    ow.prev<-m[1]
    ob.prev<-m[2]
    bmi.mean<-m[3]
    shape1<-(1+exp(para[1])) # forcing shape parameter to be > 1 to ensure distribution is either symmetric or positively skewed, to avoid weird shape
    shape2<-(1+exp(para[2]))
    mm<-10+para[3]
    scale<-para[4]

    bmean<-(shape1/(shape1+shape2))*scale+mm #anayltical mean from the empirical beta distribution, this should compare against the mean bmi
    qow<-qbeta(ow.prev, shape1=shape1, shape2=shape2, lower.tail=FALSE)*scale+mm #empirical quantile corresponding to the prevalence of overweight, should be comparable to 25
    qob<-qbeta(ob.prev, shape1=shape1, shape2=shape2, lower.tail=FALSE)*scale+mm #empirical quantile corresponding to the prevalence of overweight, should be comparable to 30
  
    est<-c(25, 30, bmi.mean) # gold standard to compare with
    dist(rbind(est, c(qow, qob, bmean)), method = "euclidean")^2 #criteria: copmuting the distance between gold standard and the results derived from distribution using euclidean distance
  }

# actual optimization function
  boptim<-function( m=c(NA, NA, NA, NA), fun=M_fn, para=c(0, 0.01, 0.1, 0), lower=c(-500, -500, 0, -500), upper=c(500, 500, 7, 53),  method="L-BFGS-B"){
    oo<-optim(par=para, fn=fun, m=m, lower=lower, upper=upper, method=method)
    oo$par
  }


################################################### END OF FUNCTIONS CODES ##############################################################################


# set output matrix
  obs<-13 # number of age groups per draw file
  Bshape1<-matrix(, nrow=obs, ncol=1000) # shape1 matrix
  Bshape2<-matrix(, nrow=obs, ncol=1000) # shape2 matrix
  MM<-matrix(, nrow=obs, ncol=1000) # shifting parameter
  Scale<-matrix(, nrow=obs, ncol=1000) # scaling parameter


# import prevalence of overweight for men and women
  library(data.table)
  OW<-fread(paste0(ow_path, "/", i_iso3, ".csv"), data.table = FALSE)
  OW<-OW[OW$year_id == i_year & OW$sex_id == i_sex,]

# import prevalence of obesity for men and women
  OB<-fread(paste0(ob_path, "/", i_iso3, ".csv"), data.table = FALSE)
  OB<-OB[OB$year_id == i_year & OB$sex_id == i_sex,]
  
# import mean BMI for men and women
  BMI<-fread(paste0(bmi_path, "/", i_iso3, ".csv"), data.table = FALSE)
  BMI<-BMI[BMI$year_id == i_year & BMI$sex_id == i_sex,]

# performing optimization looping through each draw --> could you apply this function as opposed to loop?
  cc<-1
  for(k in 0:999){
    ow<-OW[,c('year_id', 'sex_id', 'location_id', 'age_group_id', paste0('draw_',k))] # extract overweight prevalence for draw k
    colnames(ow)[5]<-'ow.prev'
    ob<-OB[,c('year_id', 'sex_id', 'location_id', 'age_group_id', paste0('draw_',k))] # extract obesity prevalence for draw k
    colnames(ob)[5]<-'ob.prev'
    bmi<-BMI[,c('year_id', 'sex_id', 'location_id', 'age_group_id', paste0('draw_',k))] # extract mean bmi for draw k
    colnames(bmi)[5]<-'mean_bmi'
    data<-merge(ow, ob, by=c('sex_id', 'year_id', 'location_id', 'age_group_id')) # combine all into a single data file
    data<-merge(data, bmi, by=c('sex_id', 'year_id', 'location_id', 'age_group_id'))

    # Back calculate obesity prevalence using the modeled ratio
    data$ob.prev <- data$ob.prev * data$ow.prev 
    
    # gitter data if overweight is exactly equal to obesity
    kp1<-data$ow.prev==data$ob.prev
    data$ow.prev[kp1]<-data$ob.prev[kp1]+0.001

    # apply optimization function to each row of overweight, obesity and bmi
    out<-apply(cbind(data$ow.prev, data$ob.prev, data$mean_bmi), 1, boptim)
    
    # saving inputs
    Bshape1[,cc]<-1+exp(out[1,])
    Bshape2[,cc]<-1+exp(out[2,])
    MM[,cc]<-out[3,]+10
    Scale[,cc]<-out[4,]
  
    cc<-cc+1
  }

# relabel colums
  colnames(Bshape1)<-paste0('draw_', c(0:999))
  colnames(Bshape2)<-paste0('draw_', c(0:999))
  colnames(MM)<-paste0('draw_', c(0:999))
  colnames(Scale)<-paste0('draw_', c(0:999))

# formatting data to data.frame
  Bshape1<-data.frame(sex_id=data$sex_id, year_id=data$year_id, age_group_id=data$age_group_id, location_id=i_iso3,Bshape1) 
  Bshape2<-data.frame(sex_id=data$sex_id, year_id=data$year_id, age_group_id=data$age_group_id, location_id=i_iso3,Bshape2) 
  MM<-data.frame(sex_id=data$sex_id, year_id=data$year_id, age_group_id=data$age_group_id, location_id=i_iso3,MM) 
  Scale<-data.frame(sex_id=data$sex_id, year_id=data$year_id, age_group_id=data$age_group_id, location_id=i_iso3,Scale) 

# saving outputs
out_dir <- "/ihme/covariates/ubcov/04_model/beta_parameters"

write.csv(Bshape1, paste0(out_dir, "/", beta_version, "/bshape1/19_", i_iso3, "_", i_year, "_", i_sex, ".csv" ), na = "", row.names = FALSE)
write.csv(Bshape2, paste0(out_dir, "/", beta_version, "/bshape2/19_", i_iso3, "_", i_year, "_", i_sex, ".csv"), na = "", row.names = FALSE)
write.csv(MM, paste0(out_dir, "/", beta_version, "/mm/19_", i_iso3, "_", i_year, "_", i_sex, ".csv"), na = "", row.names = FALSE)
write.csv(Scale, paste0(out_dir, "/", beta_version, "/scale/19_", i_iso3, "_", i_year, "_", i_sex, ".csv"), na = "", row.names = FALSE)

