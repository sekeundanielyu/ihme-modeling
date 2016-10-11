library(data.table)
library(reshape2)

if (Sys.info()[1] == "Linux") {
  root <- "/home/j"
  tmp_root <- '/ihme/gbd'
} else {
  root <- "J:"
}


fnCreateEPPSubpops <- function(epp.input, epp.subpops, epp.data){

  ## Raise a warning if sum of subpops is more than 1% different from total population
  if(any(abs(1-rowSums(sapply(epp.subpops$subpops, "[[", "pop15to49")) / epp.input$epp.pop$pop15to49) > 0.01))
    warning("Sum of subpopulations does not equal total population")

  ## If national survey data are available, apportion ART according to relative average HH survey prevalence in each subpopulation,
  ## If no HH survey, apportion based on relative mean ANC prevalence
  subpop.dist <- prop.table(sapply(epp.subpops$subpops, "[[", "pop15to49")[epp.subpops$total$year == 2010,])  # population distribution in 2010
  if(nrow(subset(epp.data[[1]]$hhs, used)) != 0){ # HH survey data available
    hhsprev.means <- sapply(lapply(epp.data, function(dat) na.omit(dat$hhs$prev[dat$hhs$used])), mean)
    art.dist <- prop.table(subpop.dist * hhsprev.means)
  } else {  ## no HH survey data
    ## Apportion ART according to relative average ANC prevalence in each subpopulation
    ancprev.means <- sapply(lapply(epp.data, "[[", "anc.prev"), mean, na.rm=TRUE)
    art.dist <- prop.table(subpop.dist * ancprev.means)
  }

  epp.subpop.input <- list()

  for(subpop in names(epp.subpops$subpops)){

    epp.subpop.input[[subpop]] <- epp.input
    epp.subpop.input[[subpop]]$epp.pop <- epp.subpops$subpops[[subpop]]

    epp.art <- epp.input$epp.art
    epp.art$m.val[epp.art$m.isperc == "N"] <- epp.art$m.val[epp.art$m.isperc == "N"] * art.dist[subpop]
    epp.art$f.val[epp.art$f.isperc == "N"] <- epp.art$f.val[epp.art$f.isperc == "N"] * art.dist[subpop]

    epp.subpop.input[[subpop]]$epp.art <- epp.art
  }

  return(epp.subpop.input)
}


fnCreateEPPFixPar <- function(epp.input,
                              dt = 0.1,
                              proj.start = epp.input$start.year+dt*ceiling(1/(2*dt)),
                              proj.end = epp.input$stop.year+dt*ceiling(1/(2*dt)),
                              tsEpidemicStart = proj.start,
                              cd4stage.weights=c(1.3, 0.6, 0.1, 0.1, 0.0, 0.0, 0.0),
                              art1yr.weight = 0.1){

  #########################
  ##  Population inputs  ##
  #########################

  epp.pop <- epp.input$epp.pop
  proj.steps <- seq(proj.start, proj.end, dt)
  epp.pop.ts <- data.frame(pop15to49 = approx(epp.pop$year+0.5, epp.pop$pop15to49, proj.steps)$y,
                           age15enter = approx(epp.pop$year+0.5, dt*epp.pop$pop15, proj.steps)$y,
                           age50exit = approx(epp.pop$year+0.5, dt*epp.pop$pop50, proj.steps)$y,
                           netmigr = approx(epp.pop$year+0.5, dt*epp.pop$netmigr, proj.steps)$y)

  proj.years <- floor(proj.steps)

  epp.pop.ts$netmigr <- epp.pop.ts$netmigr * with(subset(epp.pop, epp.pop$year %in% proj.years), rep(ifelse(netmigr != 0, netmigr * table(proj.years) * dt / tapply(epp.pop.ts$netmigr, floor(proj.steps), sum), 0), times=table(proj.years)))
  epp.pop.ts$age50rate <- (epp.pop.ts$age50exit/epp.pop.ts$pop15to49)/dt
  epp.pop.ts$mx <- c(1.0 - (epp.pop.ts$pop15to49[-1] - (epp.pop.ts$age15enter - epp.pop.ts$age50exit + epp.pop.ts$netmigr)[-length(proj.steps)]) / epp.pop.ts$pop15to49[-length(proj.steps)], NA) / dt
  epp.pop.ts[length(proj.steps), "mx"] <- epp.pop.ts[length(proj.steps)-1, "mx"]


  ##################
  ##  ART inputs  ##
  ##################

  epp.art <- epp.input$epp.art

  ## number of persons who should be on ART at end of timestep
  artnum.ts <- with(subset(epp.art, m.isperc=="N"), approx(year+1-dt, (m.val+f.val)*(1.0-perc50plus/100), proj.steps, rule=2))$y  # offset by 1 year because number on ART are Dec 31
  epp.art$artelig.idx <- match(epp.art$cd4thresh, c(1, 2, 500, 350, 250, 200, 100, 50))
  artelig.idx.ts <- approx(epp.art$year, epp.art$artelig.idx, proj.steps, "constant", rule=2)$y
  cd4init <- rep(0, 7)
  cd4init[1] <- 1

  cd4prog <- epp.input$cd4stage.dur

  mu <- as.vector(t(epp.input$cd4mort))
  alpha1 <- as.vector(t(epp.input$artmort.less6mos))
  alpha2 <- as.vector(t(epp.input$artmort.6to12mos))
  alpha3 <- as.vector(t(epp.input$artmort.after1yr))
  cd4artmort <- cbind(mu, alpha1, alpha2, alpha3)
  relinfectART <- 1.0 - epp.input$infectreduc


  ###########################
  ##  r-spline parameters  ##
  ###########################
  if (grepl('IND_', iso3))
    tsEpidemicStart <- tsEpidemicStart + 3

  numKnots <- 7
  proj.dur <- diff(range(proj.steps))
  rvec.knots <- seq(min(proj.steps) - 3*proj.dur/(numKnots-3), max(proj.steps) + 3*proj.dur/(numKnots-3), proj.dur/(numKnots-3))
  rvec.spldes <- splineDesign(rvec.knots, proj.steps)

  val <- list(proj.steps      = proj.steps,
              tsEpidemicStart = tsEpidemicStart,
              dt              = dt,
              epp.pop.ts      = epp.pop.ts,
              artnum.ts       = artnum.ts,
              artelig.idx.ts  = artelig.idx.ts,
              cd4prog         = cd4prog,
              cd4init         = cd4init,
              cd4artmort      = cd4artmort,
              relinfectART    = relinfectART,
              numKnots        = numKnots,
              rvec.spldes     = rvec.spldes,
              iota            = 0.0025)
  class(val) <- "eppfp"
  return(val)
}



prepare.epp.fit <- function(filepath, proj.end=2015.5){

  ## epp
  eppd <- read.epp.data(paste(filepath, ".xml", sep=""))
  epp.subp <- read.epp.subpops(paste(filepath, ".xml", sep=""))
  epp.input <- read.epp.input(filepath)

  epp.subp.input <- fnCreateEPPSubpops(epp.input, epp.subp, eppd)

  ## output
  val <- setNames(vector("list", length(eppd)), names(eppd))

  set.list.attr <- function(obj, attrib, value.lst)
    mapply(function(set, value){ attributes(set)[[attrib]] <- value; set}, obj, value.lst)
  val <- set.list.attr(val, "eppd", eppd)
  val <- set.list.attr(val, "likdat", lapply(eppd, fnCreateLikDat, anchor.year=epp.input$start.year))
  val <- set.list.attr(val, "eppfp", lapply(epp.subp.input, fnCreateEPPFixPar, proj.end = proj.end))
  val <- set.list.attr(val, "country", attr(eppd, "country"))
  val <- set.list.attr(val, "region", names(eppd))

  return(val)
}

fnPrepareHHSLikData <- function(hhs, anchor.year = 1970L){
  hhs$W.hhs <- qnorm(hhs$prev)
  hhs$v.hhs <- 2*pi*exp(hhs$W.hhs^2)*hhs$se^2
  hhs$sd.W.hhs <- sqrt(hhs$v.hhs)
  hhs$idx <- hhs$year - (anchor.year - 1)

  hhslik.dat <- subset(hhs, used)
  return(hhslik.dat)
}

fnCreateLikDat <- function(epp.data, anchor.year=1970L){
  
  likdat <- list(anclik.dat = fnPrepareANCLikelihoodData(epp.data$anc.prev, epp.data$anc.n, , anchor.year=anchor.year),
                 hhslik.dat = fnPrepareHHSLikData(epp.data$hhs, anchor.year=anchor.year))
  likdat$lastdata.idx <- max(unlist(likdat$anclik.dat$anc.idx.lst), likdat$hhslik.dat$idx)
  likdat$firstdata.idx <- min(unlist(likdat$anclik.dat$anc.idx.lst), likdat$hhslik.dat$idx)
  return(likdat)
}

fnCreateParam <- function(theta, fp){

  if(!exists("eppmod", where = fp))  # backward compatibility
    fp$eppmod <- "rspline"

  if(fp$eppmod == "rspline"){
    u <- theta[1:fp$numKnots]
    beta <- numeric(fp$numKnots)
    beta[1] <- u[1]
    beta[2] <- u[1]+u[2]
    for(i in 3:fp$numKnots)
      beta[i] <- -beta[i-2] + 2*beta[i-1] + u[i]
    
    return(list(rvec = as.vector(fp$rvec.spldes %*% beta),
                iota = exp(theta[fp$numKnots+1]),
                ancbias = theta[fp$numKnots+2]))
  } else { # rtrend
    return(list(tsEpidemicStart = fp$proj.steps[which.min(abs(fp$proj.steps - theta[1]))], # t0
                rtrend = list(tStabilize = theta[1]+theta[2],  # t0 + t1
                              r0 = exp(theta[3]),              # r0
                              beta = theta[4:7]),
                ancbias = theta[8]))
  }
}

fnPrepareANCLikelihoodData <- function(anc.prev, anc.n, anchor.year = 1970L, return.data=TRUE){
    ## anc.prev: matrix with one row for each site and column for each year
    ## anc.n: sample size, matrix with one row for each site and column for each year
    ## anchor.year: year in which annual prevalence output start -- to determine index to compare data
    ## NOTE: requires year to be stored in column names of anc.prev
    # anc.prev <- anc.prev[,colnames(anc.prev)  2000]


    if (nrow(anc.prev) > 1)
      anc.prev <- anc.prev[apply(!is.na(anc.prev), 1, sum) > 0,] # eliminate records with no observations
    if (nrow(anc.n) > 1)
      anc.n <- anc.n[apply(!is.na(anc.n), 1, sum) > 0,] # eliminate records with no observations


    if (!is.matrix(apply(!is.na(anc.prev), 1, which))) {
      ancobs.idx <- mapply(intersect, apply(!is.na(anc.prev), 1, which), apply(!is.na(anc.n), 1, which))  
    } else {
      ancobs.idx <- t(mapply(intersect, lapply(split(!is.na(anc.prev), rownames(!is.na(anc.prev))), which),
                             lapply(split(!is.na(anc.n), rownames(!is.na(anc.n))), which)))
      ancobs.idx <- split(ancobs.idx, rownames(ancobs.idx))
    } 
    ## limit to years with both prevalence and N observations (likely input errors in EPP if not)

    anc.years.lst <- lapply(ancobs.idx, function(i) as.integer(colnames(anc.prev)[i]))
    anc.prev.lst <- setNames(lapply(1:length(ancobs.idx), function(i) as.numeric(anc.prev[i, ancobs.idx[[i]]])), rownames(anc.prev))
    anc.n.lst <- setNames(lapply(1:length(ancobs.idx), function(i) as.numeric(anc.n[i, ancobs.idx[[i]]])), rownames(anc.n))
    
    x.lst <- mapply(function(p, n) (p*n+0.5)/(n+1), anc.prev.lst, anc.n.lst)
    if (is.matrix(x.lst)) {
      x.lst <- split(x.lst, colnames(x.lst))
    }
    W.lst <- lapply(x.lst, qnorm)
    v.lst <- mapply(function(W, x, n) 2*pi*exp(W^2)*x*(1-x)/n, W.lst, x.lst, anc.n.lst)
    if (is.matrix(v.lst)) {
      v.lst <- split(v.lst, colnames(v.lst))
    }
    anc.idx.lst <- lapply(anc.years.lst, "-", anchor.year-1)  ## index of observations relative to output prevalence vector

    anclik.dat <- list(W.lst = W.lst,
                       v.lst = v.lst,
                       n.lst = anc.n.lst,
                       anc.idx.lst = anc.idx.lst)
    
    if(return.data){ ## Return the data matrices in the list (for convenience)
      anclik.dat$anc.prev <- anc.prev
      anclik.dat$anc.n <- anc.n
    }

    return(anclik.dat)
  }


get.script.dir <- function() {
  initial.options <- commandArgs(trailingOnly = FALSE)
  file.arg.name <- "--file="
  script.name <- sub(file.arg.name, "", initial.options[grep(file.arg.name, initial.options)])
  return(paste0(dirname(script.name),'/'))
}

code_dir <- get.script.dir()

setwd(paste0(root,'strPath'))
source("Regions.R")

i <- "ZIMBABWE_2015_Final"
  
test <- F
if (Sys.info()[1] == "Linux") {
  root <- "/home/j" 
  region_name <- "SSA"
  folder_name <- "ZIMBABWE_2015_Final"
} else {
  root <- "J:"
  if(test == T) {
    region_name <- "SSA"
    folder_name <- "ZIMBABWE_2015_Final"
  } else {
    region_name <- commandArgs()[3]
    folder_name <- commandArgs()[4]
  }
}

iso3 <- commandArgs(trailingOnly=T)[1]
run_date <- commandArgs(trailingOnly=T)[2]
run_name <- commandArgs(trailingOnly=T)[3]
spectrum_file_date <- commandArgs(trailingOnly=T)[4]

dt_iso3 <- iso3
if (grepl('ZAF_', dt_iso3))
  dt_iso3 <- 'ZAF'
location_f <- fread(paste0(root,'strPath/spectrum_file_list_',spectrum_file_date,'.csv'))
location_f[subnat!='', subnat:=paste0('_',subnat)]
version_id <- location_f[paste0(iso3, subnat)==dt_iso3, version]
version_id <- ifelse(length(version_id) > 1, 'new', version_id)

region_name <- location_f[paste0(iso3, subnat)==dt_iso3 & version == version_id,region]
folder_name <- location_f[paste0(iso3, subnat)==dt_iso3 & version == version_id, file_name]
folder_name <- gsub('.PJNZ', '', folder_name)

dt_iso3 <- iso3

print(iso3)
print(region_name)
print(folder_name)

## PROVINCE LOOP BEGINS HERE

loc_list <- read.csv(paste0(root,'/strPath/zaf_subloc_map.csv'))

if (grepl('ZAF', iso3)) {
  iter_list <- unique(loc_list$spectrum_code)
} else {
  iter_list <- c(iso3)
}

supplement_survey <- fread(paste0(root,"/strPath/supplement_survey_data.csv"))

for (iso3 in iter_list) {
  nat_iso3 <- strsplit(iso3, split="_")[[1]][1] # Grab national iso3 e.g. ZAF from the list of iso3s
  iso3_stub <- gsub(paste0(nat_iso3,"_"),"",iso3)
  dir.create(paste0(tmp_root,'/WORK/02_mortality/03_models/hiv/epp_input/',run_name,'/',iso3))

  ep.path <- paste0(root,"/strPath/",folder_name)
  ep4.ext <- '.ep4'
  if (version_id == 'old') {
     ep.path <- paste0(root,"/strPath/",folder_name) 
    ep4.ext <- '.ep3'
  }
  
  ep1 <- scan(paste(ep.path, ".ep1", sep=""), "character", sep="\n")
  ep1 <- ep1[3:length(ep1)]

  ep4 <- scan(paste(ep.path,ep4.ext, sep=""), "character", sep="\n")
  ep4 <- ep4[3:length(ep4)]


  firstprojyr.idx <-  which(sapply(ep1, substr, 1, 11) == "FIRSTPROJYR")

  lastprojyr.idx <-  which(sapply(ep1, substr, 1, 10) == "LASTPROJYR")
  popstart.idx <- which(ep1 == "POPSTART")+1
  popend.idx <- which(ep1 == "POPEND")-1


  start.year <- as.integer(read.csv(text=ep1[firstprojyr.idx], header=FALSE)[2])
  stop.year <- as.integer(read.csv(text=ep1[lastprojyr.idx], header=FALSE)[2])

  IRR2 <- fread(paste0(root,"/strPath/GEN_IRR.csv"))
  IRR2 <- IRR2[age < 55,]

  sex_IRR <- fread(paste0(root,"/strPath/FtoM_inc_ratio_epidemic_specific.csv"))
  sex_IRR <- sex_IRR[epidemic_class=="GEN",]
  sex_IRR[,year:=year+start.year-1]

  missing_years <- c()
  if (sex_IRR[,max(year)] < stop.year)
    missing_years <- (sex_IRR[,max(year)]+1):stop.year
  replace_IRR <- sex_IRR[order(year)][rep(nrow(sex_IRR), times=length(missing_years))]
  if (length(missing_years) > 0)
    replace_IRR[,year:=missing_years]
  sex_IRR <- rbind(sex_IRR, replace_IRR)

  sex_IRR[,sex:=2]

  male_IRR <- copy(sex_IRR)
  male_IRR[,FtoM_inc_ratio:=1.0]
  male_IRR[,sex:=1]

  sex_IRR <- rbind(sex_IRR, male_IRR)

  tmp_iso3 <- iso3

  pop <- fread(paste0(root,"/strPath/",iso3,"_pop.csv"))[age > 14 & age < 55,]
  pop <- pop[year >= start.year,]
  
  pop$age <- strtoi(pop$age)
  pop[(age-5) %%  10 != 0, age:=as.integer(age-5)]
  pop[,value:=as.numeric(value)]

  pop1 <-data.table(aggregate(value ~ sex + age + year,pop,FUN=sum))[order(sex,age)]
  missing_years <- c()
  if (pop1[,max(year)] < stop.year)
    missing_years <- (pop1[,max(year)]+1):stop.year
  replace_pop <- pop1[rep(which(pop1[,year] == pop1[,max(year)]), times=length(missing_years))]
  replace_years <- rep(1:(stop.year-pop1[,max(year)]), each=length(which(pop1[,year] == pop1[,max(year)])))
  replace_pop[,year:=year+replace_years]
  pop1 <- rbind(pop1, replace_pop)
  
  tmp_iso3 <- ifelse(grepl('IND', iso3), iso3, iso3)
  mortart_read <- fread(paste0(root,"/strPath/",iso3,"_HIVonART.csv"))
  mortart_read <- melt(mortart_read, id = c("durationart", "cd4_category", "age", "sex"))
  setnames(mortart_read, c("variable","value","cd4_category"),c("draw","mort","cd4"))
  mortart_read <- mortart_read[age!="55-100",]
  mortart_read <- mortart_read[,draw := substr(draw,5,8)]

  progdata_read <- fread(paste0(root,"/strPath/",iso3,"_progression_par_draws.csv"))
  progdata_read <- progdata_read[,lambda:=1/prog]

  mortnoart_read <- fread(paste0(root,"/strPath/",iso3,"_mortality_par_draws.csv"))

  for (k in 1:1000) {
    print(k)

    IRR <- runif(16, IRR2$lower, IRR2$upper)
    IRR2[,IRR:=IRR]

    IRR2[,IRR:=IRR2[,IRR]/IRR2[age==25 & sex==1,IRR]]

    combined_IRR <- merge(sex_IRR, IRR2, by='sex', allow.cartesian=TRUE)
    combined_IRR[,comb_IRR := FtoM_inc_ratio * IRR]

    pop2 <- merge(pop1, combined_IRR, by=c('sex', 'age', 'year'))

    pop2[,wt:=comb_IRR*value]
    sex_agg <- pop2[,.(wt=sum(wt)),by=.(year, age)]

    total <- pop2[,.(total = sum(wt)),by=.(year)]
    pop2 <- merge(pop2, total, by=c('year'))
    pop2[,ratio:=wt/total]


    sex_agg <- merge(sex_agg, total, by=c('year'))
    sex_agg[,ratio:=wt/total]

    mortart <- mortart_read[draw==k,]
    mortart[,age:= as.integer(sapply(strsplit(mortart[,age],'-'), function(x) {x[1]}))]
    mortart[,sex:=as.integer(sex)]

    cd4_cats <- unique(mortart[,cd4])
    durat_cats <- unique(mortart[,durationart])
    cd4_vars <- expand.grid(durationart=durat_cats, cd4=cd4_cats)

    expanded_pop <- pop2[rep(1:nrow(pop2), times=length(cd4_cats)*length(durat_cats))]
    expanded_pop <- expanded_pop[order(year, sex, age)]
    expanded_pop <- cbind(expanded_pop, cd4_vars[rep(1:(nrow(cd4_vars)), times=nrow(pop2)),])
    combined_mort <- merge(expanded_pop, mortart, by=c('durationart', 'cd4', 'sex', 'age'))
    mortart <- combined_mort[,.(mort=sum(ratio*mort)), by=.(durationart, cd4, year)]

    mortart <- mortart[cd4=="ARTGT500CD4", cat := 1]
    mortart <- mortart[cd4=="ART350to500CD4", cat := 2]
    mortart <- mortart[cd4=="ART250to349CD4", cat := 3]
    mortart <- mortart[cd4=="ART200to249CD4", cat := 4]
    mortart <- mortart[cd4=="ART100to199CD4", cat := 5]
    mortart <- mortart[cd4=="ART50to99CD4", cat := 6] 
    mortart <- mortart[cd4=="ARTLT50CD4", cat := 7]
    mortart[,risk:=-1*log(1-mort)]
    mortart <- mortart[,c("risk","cat","durationart","year"), with=F]
    mortart <- mortart[, setattr(as.list(risk), 'names', cat), by=c("year","durationart")]
    mortart <- mortart[order(year, durationart)]

    mortart1 <- mortart[durationart=="LT6Mo",]
    mortart2 <- mortart[durationart=="6to12Mo",]
    mortart3 <- mortart[durationart=="GT12Mo",]

    alpha1gbd <- as.matrix(data.frame(mortart1[,c("1","2","3","4","5","6", "7"), with=F]))
    alpha2gbd <- as.matrix(data.frame(mortart2[,c("1","2","3","4","5","6", "7"), with=F]))
    alpha3gbd <- as.matrix(data.frame(mortart3[,c("1","2","3","4","5","6", "7"), with=F]))

      
    progdata <- progdata_read[draw==k,]
    progdata[,risk:=-1*log(1-prog)/0.1]
    progdata[,prob:=1-exp(-1*risk)]
    progdata[,age:= as.integer(sapply(strsplit(progdata[,age],'-'), function(x) {x[1]}))]

    cd4_cats <- unique(progdata[,cd4])
    cd4_vars <- data.table(cd4=cd4_cats)

    expanded_pop <- sex_agg[rep(1:nrow(sex_agg), times=length(cd4_cats))]
    expanded_pop <- expanded_pop[order(year, age)]
    expanded_pop <- cbind(expanded_pop, cd4_vars[rep(1:(nrow(cd4_vars)), times=nrow(sex_agg)),])
    combined_prog <- merge(expanded_pop, progdata, by=c('cd4', 'age'))
    progdata <- combined_prog[,.(prob=sum(ratio*prob)), by=.(cd4, year)]

    progdata <- progdata[cd4=="GT500CD4", cat := 1]
    progdata <- progdata[cd4=="350to500CD4", cat := 2]
    progdata <- progdata[cd4=="250to349CD4", cat := 3]
    progdata <- progdata[cd4=="200to249CD4", cat := 4]
    progdata <- progdata[cd4=="100to199CD4", cat := 5]
    progdata <- progdata[cd4=="50to99CD4", cat := 6] 
    progdata[,risk:=-1*log(1-prob)]
    progdata <- progdata[,.(year,risk,cat)]
    progdata <- progdata[, setattr(as.list(risk), 'names', cat), by=.(year)]
    progdata <- progdata[order(year)]
    progdata <- progdata[,c("1","2","3","4","5","6"), with=F]
    progdata <- data.frame(progdata)


    mortnoart <- mortnoart_read[draw==k,]
    mortnoart[,age:= as.integer(sapply(strsplit(mortnoart[,age],'-'), function(x) {x[1]}))]
    mortnoart[,risk:=-1*log(1-mort)/0.1]
    mortnoart[,prob:=1-exp(-1*risk)]

    cd4_cats <- unique(mortnoart[,cd4])
    cd4_vars <- data.table(cd4=cd4_cats)

    expanded_pop <- sex_agg[rep(1:nrow(sex_agg), times=length(cd4_cats))]
    expanded_pop <- expanded_pop[order(year, age)]
    expanded_pop <- cbind(expanded_pop, cd4_vars[rep(1:(nrow(cd4_vars)), times=nrow(sex_agg)),])
    combined_mu <- merge(expanded_pop, mortnoart, by=c('cd4', 'age'))
    mortnoart <- combined_mu[,.(prob=sum(ratio*prob)), by=.(cd4, year)]

    mortnoart <- mortnoart[cd4=="GT500CD4", cat := 1]
    mortnoart <- mortnoart[cd4=="350to500CD4", cat := 2]
    mortnoart <- mortnoart[cd4=="250to349CD4", cat := 3]
    mortnoart <- mortnoart[cd4=="200to249CD4", cat := 4]
    mortnoart <- mortnoart[cd4=="100to199CD4", cat := 5]
    mortnoart <- mortnoart[cd4=="50to99CD4", cat := 6] 
    mortnoart <- mortnoart[cd4=="LT50CD4", cat := 7] 
    mortnoart[,risk:=-1*log(1-prob)]
    mortnoart <- mortnoart[,.(year,risk,cat)]
    mortnoart <- mortnoart[, setattr(as.list(risk), 'names', cat), by=.(year)]
    mortnoart <- mortnoart[order(year)]
    mortnoart <- mortnoart[,c("1","2","3","4","5","6", "7"), with=F]
    mortnoart <- data.frame(mortnoart)
    mugbd <- as.matrix(mortnoart)

    source(paste0(root,"/strPath/read_epp_files.R"))  
    library(splines)
    date <- Sys.Date()

    ## Restandardize folder names (put spaces back in)
      folder_name <- gsub("__"," ",folder_name)

    ## Function to do the following:
    ## (1) Read data, EPP subpopulations, and popualation inputs
    ## (2) Prepare timestep inputs for each EPP subpopulation


    if (k == 1) {
      bw.out <- prepare.epp.fit(ep.path)
      for (n in names(bw.out)) {
        attr(bw.out[[n]], 'eppfp')$mortyears <- nrow(attr(bw.out[[n]], 'eppfp')$cd4prog)
        attr(bw.out[[n]], 'eppfp')$cd4years <- nrow(attr(bw.out[[n]], 'eppfp')$cd4prog)
      }
      if (iso3 %in% supplement_survey[,unique(iso3)]) {
        print('found survey')
        survey_subpop <- supplement_survey[iso3==dt_iso3, unique(subpop)]
        print(names(bw.out))
        print(survey_subpop)
        tmp_survey <- supplement_survey[iso3==dt_iso3,.(year, prev, se, n)]
        tmp_survey[,used:=TRUE]
        tmp_survey[prev==0,used:=FALSE]
        tmp_survey[,W.hhs:=qnorm(prev)]
        tmp_survey[,v.hhs:=2*pi*exp(W.hhs^2)*se^2]
        tmp_survey[,sd.W.hhs := sqrt(v.hhs)]
        tmp_survey[,idx := year - (start.year-1)]

        attr(bw.out[[survey_subpop]], 'likdat')$hhslik.dat <- rbind(attr(bw.out[[survey_subpop]], 'likdat')$hhslik.dat, as.data.frame(tmp_survey[used==TRUE,]))
      }
    } else {
      mu <- as.vector(t(mugbd))
      alpha1 <- as.vector(t(alpha1gbd))
      alpha2 <- as.vector(t(alpha2gbd))
      alpha3 <- as.vector(t(alpha3gbd))
      cd4artmort <- cbind(mu, alpha1, alpha2, alpha3)

      for (n in names(bw.out)) {
        attr(bw.out[[n]], 'eppfp')$cd4artmort <- cd4artmort
        attr(bw.out[[n]], 'eppfp')$cd4prog <- progdata
      }
    }

    for (n in names(bw.out)) {
      attr(bw.out[[n]], 'eppfp')$mortyears <- nrow(attr(bw.out$Urban, 'eppfp')$cd4prog)
      attr(bw.out[[n]], 'eppfp')$cd4years <- nrow(attr(bw.out$Urban, 'eppfp')$cd4prog)
    }


    ## MAKE NEW, PROVINCE-SPECIFIC OBJECT HERE
    # This is done because we only want the province-specific data, not that from all the other provinces
    if (length(iter_list) > 1) {
      tmp_obj <- list()
      tmp_obj[[iso3_stub]] <- bw.out[[iso3_stub]]
      bw.out <- tmp_obj # we need to replace the bw.out object so that it's all the same format
    }
    save(bw.out, file = paste0(tmp_root,"/strPath.RData"))
    }
}
## PROVINCE LOOP ENDS HERE
