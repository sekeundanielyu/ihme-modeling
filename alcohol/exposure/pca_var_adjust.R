

rm(list=ls())

if (Sys.info()[1] == "Linux") root <- "/home/j" else root <- "J:"

data <- read.csv(paste0(root,"/WORK/01_covariates/02_inputs/fao/code/gpr_results_Nov3_scale5.csv"),stringsAsFactors=F)
narrowdat <- data[,c("iso3","year","gpr_var","gpr_mean")]
narrowdat$unlog_gpr_mean <- exp(as.numeric(narrowdat$gpr_mean))
narrowdat$gpr_var <- as.numeric(narrowdat$gpr_var)

narrowdat$minimum <- NA

## Here're the codes for solving for sigma:
## -  Mu should be anti-log of log mean
## -	LogV is the variance from GPR
## -	out$minimum give you the final sigma

for (i in 1:length(narrowdat$gpr_var)) {
  mu <- narrowdat$unlog_gpr_mean[i]
  logV <- narrowdat$gpr_var[i]
  
  dslnex <- function(x) {
    y<-numeric(2)
    y[1]<-logV
    y[2]<-(exp(x[1]^2)-1)*(exp(2*mu+x[1]^2))
    dist(y)
  }
  #xstart <- c(0.1)
  out<-optimize(dslnex, interval=c(0.01, 5))
  narrowdat$minimum[i] <- out$minimum
  
}

write.csv(narrowdat,paste0(root,"/WORK/05_risk/01_database/02_data/drugs_alcohol/01_exp/04_models/intermediate/pca_var_adj.csv"),row.names=F)

