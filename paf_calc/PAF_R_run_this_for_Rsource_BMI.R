rm(list = ls())

trailargs <- commandArgs(trailingOnly=TRUE);
trailargs;

L <- as.numeric(trailargs[1])
U <- as.numeric(trailargs[2])
F <- (trailargs[3])

calc_paf_beta_bmi_cap <- function(lower, upper, shape1, shape2, rr, tmrel, mm, scale, cap) {
  denom <- integrate(function(x) dbeta(x, shape1, shape2) * rr^((((x*(scale)+mm-tmrel + abs(x*(scale)+mm-tmrel))/2) - ((x*(scale)+mm-cap)+abs(x*(scale)+mm-cap))/2)), lower, upper, stop.on.error=FALSE)$value
  paf <- integrate(function(x) dbeta(x, shape1, shape2) * (rr^((((x*(scale)+mm-tmrel + abs(x*(scale)+mm-tmrel))/2) - ((x*(scale)+mm-cap)+abs(x*(scale)+mm-cap))/2)) - 1)/denom, lower, upper, stop.on.error=FALSE)$value
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
      calc_paf_beta_bmi_cap( lower    =  L,
                upper    =  U,
                shape1     =  file[j,paste0('shape1_',i)],
                shape2       =  file[j,paste0('shape2_',i)],
                rr       =  file[j,paste0('rr_',i)],
                tmrel    =  file[j,paste0('tmred_mean_',i)],
                mm    =  file[j,paste0('mm_',i)],
                scale    =  file[j,paste0('scale_',i)],
                cap = 45)
      }, error=function(e){cat("ERROR :",conditionMessage(e), "\n")})
  setTxtProgressBar(pb, i)

}
close(pb)

write.csv(file, paste0(F,"_OUT.csv"), row.names=T)

## END_OF_R




