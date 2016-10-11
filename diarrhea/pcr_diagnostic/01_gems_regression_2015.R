### Calculating the age and pathogen-specific odds ratios for GEMS and TAC reanalysis ###
library(coxme)
library(plyr)
library(reshape2)
library(mvtnorm)

## Import accuracy file from 00_tac_accuracy.R ##
accuracy <- read.csv("J:/Project/Diarrhea/GEMS/min_loess_accuracy.csv") # bimodal accuracy (adenovirus eg)
accuracy <- subset(accuracy, pathogen!="tac_EAEC")

gems <- read.csv("J:/Project/Diarrhea/GEMS/gems_final.csv")

## Create new variable 'binary_[pathogen]' but cutting at Ct value
pathogens <- as.vector(accuracy$pathogen)
cts <- as.vector(accuracy$ct.inflection)

tac.results <- gems[,pathogens]
tac <- gems[,pathogens]
for(i in 1:12){
  value <- cts[i]
  path <- pathogens[i]
  obs <- tac.results[,path]
  tac.results[,path] <- ifelse(obs<value,1,0)
}

colnames(tac.results) <- paste0("binary_",substr(pathogens,5,20))

gems <- data.frame(gems, tac.results)

#### Main Regression ####
## Create variables for interaction of age and pathogen status ###
binary <- colnames(tac.results)
gems2 <- gems
for(b in 1:12){
  apath <- binary[b]
  age1 <- ifelse(gems[,apath]==1,ifelse(gems$age==1,1,0),0)
  age2 <- ifelse(gems[,apath]==1,ifelse(gems$age==2,1,0),0)
  age3 <- ifelse(gems[,apath]==1,ifelse(gems$age==3,1,0),0)
  out <- data.frame(age1,age2,age3)
  colnames(out) <- c(paste0(substr(apath,8,25),"age1"),paste0(substr(apath,8,25),"age2"),paste0(substr(apath,8,25),"age3"))
  gems2 <- data.frame(gems2, out)
}

### Big loop to model for each pathogen, then calculate uncertainty for each site/age combination ###
## Trick coxme to run a mixed effects conditional logistic regression model
gems2$time <- 1

# empty data frame for saving results
output <- data.frame()
out.odds <- data.frame()

for(b in 1:12){ 
  # pathogen
  path.now <- binary[b]
  # all other pathogens
  paths.in <- binary[binary!=path.now]
  
  # paste together formula
  paths.age <- c(paste0("(",substr(path.now,8,25),"age1|site.names)"), paste0("(",substr(path.now,8,25),"age2|site.names)"), paste0("(",substr(path.now,8,25),"age3|site.names)"))
  form <- as.formula(paste("Surv(time, case.control) ~ ", paste(paths.in, collapse="+"), paste0("+ ",path.now,":factor(age)"," +"),
                           paste(paths.age, collapse="+"), "+ strata(CASEID)"))
                          
  # regression
  fitme <- coxme(form, data=gems2)
  #fitme
  
  betas <- fitme$coefficients[12:14]
  matrix <- sqrt(vcov(fitme))
  se <- c(matrix[12,12], matrix[13,13],matrix[14,14])
  odds <- data.frame(lnor=betas, errors=se, pathogen = substr(path.now, 8, 25))
  
  age_group_id <- 2:21
  draw1 <- rnorm(1000, mean=betas[1], sd=se[1])
  draw2 <- rnorm(1000, mean=betas[2], sd=se[2])
  draw3 <- rnorm(1000, mean=betas[3], sd=se[3])
  draw4 <- c(draw2[1:500], draw3[501:1000])
  
  out <- data.frame(age_group_id)
  for(d in seq(1,1000,1)) {
      out[1:3,paste0("lnor_",d)] <- draw1[d]
      out[4,paste0("lnor_",d)] <- draw4[d]
      out[5:20,paste0("lnor_",d)] <- draw3[d]
  }
 
   out <- data.frame(out, pathogen = substr(path.now, 8, 25))

  output <- rbind.data.frame(output, out)
  out.odds <- rbind.data.frame(out.odds, odds)
}

write.csv(output, "J:/temp/user/GEMS/Regressions/me_fixed_effects.csv")


