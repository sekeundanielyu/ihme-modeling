rm(list = ls())

trailargs <- commandArgs(trailingOnly=TRUE);
trailargs;

L <- as.numeric(trailargs[1])
U <- as.numeric(trailargs[2])
rr_scalar <- as.numeric(trailargs[3])
DIST <- (trailargs[4])
F <- (trailargs[5])
inv_exp <- as.numeric(trailargs[6])
c <- as.numeric(trailargs[7])

print(L)
print(U)
print(rr_scalar)
print(DIST)
print(F)
print(inv_exp)
print(c)

########################################################################################## 
## DEFINE FUNCTIONS
########################################################################################## 
calc_paf_cap <- function(lower, upper, mean, sd, rr, tmrel, rr_scalar, dist, inv_exp, cap) {
  ## risky
  if (dist == "normal" & inv_exp == 0) {
    
    denom <- integrate(function(x) dnorm(x, mean, sd) * rr^((((x-tmrel + abs(x-tmrel))/2) - ((x-cap)+abs(x-cap))/2)/rr_scalar), lower, upper, stop.on.error=FALSE)$value
    paf <- integrate(function(x) dnorm(x, mean, sd) * (rr^((((x-tmrel + abs(x-tmrel))/2) - ((x-cap)+abs(x-cap))/2)/rr_scalar) - 1)/denom, lower, upper, stop.on.error=FALSE)$value
  }
  if (dist == "lognormal" & inv_exp == 0) {
    mu <- log(mean/sqrt(1+(sd^2/(mean^2))))
    sd <- sqrt(log(1+(sd^2/mean^2)))
    mean <- mu

    denom <- integrate(function(x) dlnorm(x, mean, sd) * rr^((((x-tmrel + abs(x-tmrel))/2) - ((x-cap)+abs(x-cap))/2)/rr_scalar), lower, upper, stop.on.error=FALSE)$value
    paf <- integrate(function(x) dlnorm(x, mean, sd) * (rr^((((x-tmrel + abs(x-tmrel))/2) - ((x-cap)+abs(x-cap))/2)/rr_scalar) - 1)/denom, lower, upper, stop.on.error=FALSE)$value
  }
  
  ## protective then substract exposure from TMREL
  if (dist == "normal" & inv_exp == 1) {
    denom <- integrate(function(x) dnorm(x, mean, sd) * rr^((((tmrel-x + abs(tmrel-x))/2) - ((cap-x) + abs(cap-x))/2)/rr_scalar), lower, upper, stop.on.error=FALSE)$value
    paf <- integrate(function(x) dnorm(x, mean, sd) * (rr^((((tmrel-x + abs(tmrel-x))/2) - ((cap-x) + abs(cap-x))/2)/rr_scalar) - 1)/denom, lower, upper, stop.on.error=FALSE)$value
  }
  if (dist == "lognormal" & inv_exp == 1) {
    mu <- log(mean/sqrt(1+(sd^2/(mean^2))))
    sd <- sqrt(log(1+(sd^2/mean^2)))
    mean <- mu

    denom <- integrate(function(x) dlnorm(x, mean, sd) * rr^((((tmrel-x + abs(tmrel-x))/2) - ((cap-x) + abs(cap-x))/2)/rr_scalar), lower, upper, stop.on.error=FALSE)$value
    paf <- integrate(function(x) dlnorm(x, mean, sd) * (rr^((((tmrel-x + abs(tmrel-x))/2) - ((cap-x) + abs(cap-x))/2)/rr_scalar) - 1)/denom, lower, upper, stop.on.error=FALSE)$value
  }
  
  return(paf)
}

########################################################################################## 
## LOOP THROUGH FILE AND CALC PAF
########################################################################################## 
file<-read.csv(paste0(F,".csv"), header=T)


require(utils)
tot=999
pb <- txtProgressBar(min = 0, max = tot, style = 3)

FOR<-Sys.time()

for (i in 0:999) {
  file[,paste0('paf_',i)]=NA
  for(j in 1:nrow(file))
    ## tryCatch loop - some draws have a non-finite function error
    tryCatch({
    file[j,paste0('paf_',i)]=
      calc_paf_cap( lower    =  L,
                upper    =  U,
                mean     =  file[j,paste0('exp_mean_',i)],
                sd       =  file[j,paste0('exp_sd_',i)],
                rr       =  file[j,paste0('rr_',i)],
                tmrel    =  file[j,paste0('tmred_mean_',i)],
                rr_scalar=  rr_scalar,
                dist     =  DIST,
                inv_exp  =  inv_exp,
                cap      =  cap <- file[j,paste0('cap_',i)])
    }, error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
  setTxtProgressBar(pb, i)
}
close(pb)

write.csv(file, paste0(F,"_OUT.csv"), row.names=T)

## END_OF_R




