## Life-table related functions

library(data.table)
library(reshape2)



###############################################################################
## LIFETABLE FUNCTION THAT MAKES FULL LIFETABLE FROM MX, AX, AND QX (UNDER-5)
###############################################################################
## make sure id represents geography or draw or the combination, whatever uniquely defines
## make sure id, sex, year, and age uniquely identify observations


lifetable <- function(data,  preserve_u5 = 0, cap_qx=0) {
  
  ## order data just in case
  data <- data[order(data$id,data$sex,data$year,data$age),]
  data$qx <- as.numeric(data$qx)
  data$mx <- as.numeric(data$mx)
  data$ax <- as.numeric(data$ax)
  if (class(data$sex) == "factor") data$sex <- as.character(data$sex)
  
  ## can set up more assurances here (certain things uniquely identify, etc.)
  
  ## get length of intervals
  data$n <- unlist(tapply(data$age, list(data$id,data$sex,data$year), function(x) c(x[-1],max(x)) - x ))
  
  ## qx
  if (preserve_u5 == 1) data$qx[data$age > 1] <- (data$n[data$age > 1]*data$mx[data$age > 1])/(1+(data$n[data$age > 1]-data$ax[data$age > 1])*data$mx[data$age > 1])
  if (preserve_u5 == 0) data$qx <- (data$n*data$mx)/(1+(data$n-data$ax)*data$mx)
  data$qx[data$age==max(data$age)] <- 1
  
  if (cap_qx == 1) {
    data$qx[data$qx > 1] <- .9999
  } else {
    if (length(data$qx[data$qx > 1]) > 0) stop("Probabilities of death over 1, re-examine data, or use cap option")
  }
  
  ## px
  data$px <- 1- data$qx
  
  ## lx
  data$lx <- 0
  data$lx[data$age==0] <- 100000
  for (i in 1:length(unique(data$age))) {
    temp <- NULL
    temp <- data$lx*data$px
    temp <- c(0,temp[-length(temp)])
    data$lx <- 0
    data$lx <- data$lx + temp
    data$lx[data$age==0] <- 100000
  }
  
  ## dx
  dx <- data.table(data)
  setkey(dx,id,sex,year)
  dx <- as.data.frame(dx[,c(diff(lx),-1*lx[length(lx)]),by=key(dx)])
  dx <- dx$V1*-1
  data <- cbind(data,dx)
  
  ## nLx
  lx_shift <- data.table(data)
  setkey(lx_shift,id,sex,year)
  lx_shift <- as.data.frame(lx_shift[,c(lx[-1],0),by=key(lx_shift)])
  lx_shift <- lx_shift$V1
  data <- cbind(data,lx_shift)
  data$nLx <- (data$n * data$lx_shift) + (data$ax * data$dx)
  data$nLx[data$age == max(data$age)] <- data$lx[data$age == max(data$age)]/data$mx[data$age == max(data$age)]
  data$lx_shift <- NULL
  
  ## Tx
  Tx <- data.table(data)
  setkey(Tx,id,sex,year)
  Tx <- as.data.frame(Tx[,list(Tx=rev(cumsum(rev(nLx)))),key(Tx)])
  data$Tx <- Tx$Tx
  
  
  ## ex
  data$ex <- data$Tx/data$lx
  
  return(data)
}



## get right populations for life tables
lt_get_pops <- function(data,agg_var="sex_id",draws=T,idvars=c("location_id","year")) {
  ## just feed this populations in the lifetable format
  ## goal: get highest age group population for which pops aren't missing among all children
  ## replicate those pops from that age group up to 110
  ## to get the highest age across sexes, you want agg_var = "sex_id" and idvars = c("location_id","year)
  ## if you have draws in your data set draws=T so that they stay throughout
  ## data are required to have age, sex, year, location_id, pop and have the full lifetable format (0 through 110)
  if (is.null(data$location_id)) stop("missing required vars: location_id")
  if (is.null(data$age) & is.null(data$age_group_id)) stop("missing required vars: either age or age_group_id")
  if (is.null(data$sex_id) & is.character(data$sex)) {
    data$sex_id[data$sex == "male"] <- "1"
    data$sex_id[data$sex == "female"] <- "2"
    data$sex_id[data$sex == "both"] <- "3"
    data$sex_id <- as.numeric(data$sex)
  } else if (is.null(data$sex_id) & is.numeric(data$sex)) {
    data$sex_id <- data$sex
  }
  if ("year" %in% names(data)) yr <- T
  names(data)[names(data)=="year"] <- "year_id"
  data$sex_id <- as.numeric(data$sex_id)
  data$year_id <- as.numeric(data$year_id)
  if ("none" %in% idvars) stop("you should have idvars, see explanation above")
  if (agg_var == "sex_id") {
    collvar <- "sex_agg"
    data$sex_agg <- 3
    if (length(data$sex_id[data$sex_id == 3]) > 0) stop("trying to aggregate sex, but it's already present")
  }
  
  if (nrow(data[data$age == 80 & is.na(data$pop),]) > 0) stop("missing pops at age 80, shouldn't be possible")
  
  idvars <- gsub("year","year_id",idvars)
  ## now, are you aggregating over sex or over geography? the agg_var option will say
  ## use that variable to check highest age in subaggregate-year for which all subaggregates have values
  check_ages <- data.table(data)
  check_ages <- as.data.frame(check_ages[,list(len=length(pop[!is.na(pop)])),by=c(idvars,collvar,"age")])
  ## find max observations length by id variables
  agemax <- data.table(check_ages)
  agemax <- as.data.frame(agemax[,list(age=max(age[len==max(len)])),by=c(idvars,collvar)])
  agemax$sex_agg <- NULL
  names(agemax)[names(agemax)=="age"] <- "age_max"
  data <- merge(data,agemax,by=c("year_id","location_id"),all.x=T)
  dimtest <- nrow(data)
  if (nrow(data[is.na(data$age_max),])>0) stop("missing agemax calculation")
  data <- data[data$age_max >= data$age,]
  
  expand_age <- expand.grid(age_max=seq(from=80,to=110,by=5),age_new=seq(from=80,to=110,by=5) )
  expand_age <- expand_age[expand_age$age_new >= expand_age$age_max,]
  
  add <- merge(data[data$age== data$age_max,],expand_age,by="age_max",all.x=T)
  data <- data[data$age_max > data$age,]
  add$age <- add$age_new
  add$age_new <- NULL
  data <- rbind(data,add)
  if (nrow(data)!=dimtest) stop("didn't replace right dimensions")
  if (draws==T) {
    data <- data[,c("year_id","location_id","sex_id","age","pop","draw")]
  } else {
    data <- data[,c("year_id","location_id","sex_id","age","pop")]
  }
  if (yr) names(data)[names(data)=="year"] <- "year_id"
  return(data)
}




##################################################################################################################
## Collapsing function ###########################################################################################
##################################################################################################################

lt_agg_geog <- function(data,preserve_u5=T,u5_data=NULL,do_lt=F,keys=c("parent_id","year_id","age","sex_id")) {
  ## this function will create a lifetable aggregate, required inputs:
  ## data : a data frame with several required variables (see below):
  ## preserve_u5 : logical, indicates whether aggregating u5 age groups using qx or mx, will also return under-5 qx values aggregated if T
  ## u5_data : required if inlc_u5, need to get age-sex data in order to properly aggregate u5 data using qx (since )
  ## do_lt : logical, default F, if T, will run the lifetable funciton to generate full lifetable for aggregates
  ##    
  ##    important variables to have in data:
  ##    ihme_loc_id : identifies disaggregate locations
  ##    parent_id : identifies the level to aggregate to
  ##    pop : required to do weighting and aggregation
  ##    mx : should be weighting mx using pop
  ##    qx : weight qx using pop as well, option to keep qx for u5 ages, recalculate based on mx for others
  ##    ax : weighted up using death numbers
  ##
  ##    important variables to have in u5_data:
  ##    age: enn, lnn, pnn, ch
  ##    sex, parent_id, year, pop
  ##    NOTE: NEED TO HAVE SAME KEYS AS IN REST OF AGE DATA
  
  ## keys : character vector of variable names to set as keys
  
  ## NOTE: when aggregating regions to higher levels, make sure pops are scaled pops
  
  ## WARNINGS AND CHECKS
    ## Check under-5 preference
    if (preserve_u5 == T) stopifnot(exists("u5_data"))
    if (preserve_u5 == F) cat(paste0("WARNING WARNING WARNING WARNING WARNING WARNING \n 
                                     BE SURE YOU WANT TO WEIGHT U5 AGE GROUPS WITH MX INSTEAD OF QX!!!"))  
    ## make sure data usable format
    data$pop <- as.numeric(data$pop)
    data$mx <- as.numeric(data$mx)
    data$qx <- as.numeric(data$qx)
    data$ax <- as.numeric(data$ax)
    data$age <- as.numeric(data$age)
    data$n <- unlist(tapply(data$age, list(data$ihme_loc_id,data$sex,data$year), function(x) c(x[-1],max(x)) - x ))
    
    ## make sure keys plus age uniquely id observations
    stopifnot(dim(data[duplicated(data[,c(keys,"age")])])[2] < 1)
    if (preserve_u5 == T) stopifnot(dim(u5_data[duplicated(u5_data[,c(keys,"age")])])[2] < 1)
    
  
  ## DO OPERATIONS ON DATA
    ## collapse table, recalculate qx
    data <- data.table(data)
    data[dx:=pop*mx]
    aggs <- as.data.frame(data[,list(pop = sum(pop),mx = weighted.mean(mx,w=pop), ax=weighted.mean(ax,w=dx), 
                                     qx=weighted.mean(qx,w=pop)),by=keys])
    
    ## calculate qx for above-5 agegroups
    if (preserve_u5 == 1) aggs$qx[aggs$age > 1] <- (aggs$n[aggs$age > 1]*aggs$mx[aggs$age > 1])/(1+(aggs$n[aggs$age > 1]-aggs$ax[aggs$age > 1])*aggs$mx[aggs$age > 1])
    ## calculate mx from the weighted-up qx for under-5 age groups
    if (preserve_u5 == 1) aggs$mx[aggs$age < 5] <- -aggs$qx[aggs$age < 5]/(aggs$n[aggs$age < 5]*aggs$qx[aggs$age < 5] - aggs$ax[aggs$age < 5]*aggs$qx[aggs$age < 5] - aggs$n[aggs$age < 5])
    if (preserve_u5 == 0) aggs$qx <- (aggs$n*aggs$mx)/(1+(aggs$n-aggs$ax)*aggs$mx)
    aggs$qx[aggs$age==max(aggs$age)] <- 1
    
    ## now we have mx, ax, qx for all aggregates. But, if we're doing the under-5 aggregates with qx, we should be bringing in the age-sex results
    ## in order to remake enn, lnn, pnn, 1-4
    
    u5_data <- data.table(u5_data)
    u5_aggs <- as.data.frame(u5_data[,list(pop = sum(pop), qx=weighted.mean(qx,w=pop)),by=keys])
    ## 
    
    
  
  u5 <- dcast(setDT(u5),parent_id+sex+year+sex_id~age_group_id,value.var=c("qx","ax","pop"))
  
  ## then, we need to back-calculate mx for under-5 age groups, these will admittedly conflict with deaths/pop
  
  
  return(data)
}




