# clear environment
rm(list=ls(all=TRUE))

library(data.table)
library(reshape2)
library(RColorBrewer)     
library(ggplot2)
library(boot)

if (Sys.info()[1] == "Linux") {
  root <- "/home/j" 
  iso3 <- commandArgs()[3]
  run_date <- commandArgs()[4]
  run_name <- commandArgs()[5]
  n.draws <- commandArgs()[6]
} else {
  root <- "J:"
  run_date <- "160122"
  run_name <- "160122_test"
  n.draws <- 1000
}

prev_dir <- "strPath"
inc_dir <- "strPath"
aims_folder <- "strPath"

setwd("strPath")


dt1 <- NULL

missing.draws <- c()
kept.draws <- c()
j = 1
for (i in c(1:n.draws)) {
  file <- paste0('results_incid',i,'.csv')
  if (file.exists(file)) {
    print(paste("Found draw",i))
    dt <- fread(file)
    tmp.n.draws <- length(names(dt)[names(dt) != 'year'])
    keep.draw <- sample(1:tmp.n.draws, 1)
    kept.draws <- c(kept.draws, keep.draw)
    dt <- dt[,c('year', paste0('draw',keep.draw)), with=F]
    dt <- melt(dt, id.vars = "year", variable.name = "run", value.name = "incid")
    dt <- dt[,draw:=i]
    dt1 <- rbindlist(list(dt1,dt))
  }
  else {
    print(paste("Missing draw",i))
    missing.draws <- c(missing.draws, i)
  }
}

replace.with <- sample(dt1[,unique(draw)], length(missing.draws), replace=TRUE)

if (length(missing.draws) > 0) {
  for (i in 1:length(missing.draws)) {
    tmp.dt <- dt1[draw==replace.with[i],]
    tmp.dt[,draw := missing.draws[i]]
    dt1 <- rbind(dt1, tmp.dt)
  }
}

dt1[,run:=NULL]
dt1[,incid:=incid*100]
setnames(dt1, c('draw', 'incid'), c('run', 'draw'))
reshaped.dt <- dcast.data.table(dt1,year~run, value.var='draw')
setnames(reshaped.dt, as.character(1:n.draws), paste0('draw', 1:n.draws))
reshaped.dt <- reshaped.dt[order(year),]

write.csv(reshaped.dt, file = paste0(root,"/strPath/",iso3,"_SPU_inc_draws.csv"), row.names=F)

prev_dt <- NULL

j = 1
for (i in c(1:n.draws)) {
  file <- paste0('results_prev',i,'.csv')
  if (file.exists(file)) {
    print(paste('prev',i))
    dt <- fread(file)
    dt <- dt[,c('year', paste0('draw',kept.draws[j])), with=F]
    dt <- melt(dt, id.vars = "year", variable.name = "run", value.name = "prev")
    dt <- dt[,draw:=i]
    prev_dt <- rbindlist(list(prev_dt,dt))
    j <- j + 1
  }
}

if (length(missing.draws) > 0) {
  for (i in 1:length(missing.draws)) {
    tmp.dt <- prev_dt[draw==replace.with[i],]
    tmp.dt[,draw := missing.draws[i]]
    prev_dt <- rbind(prev_dt, tmp.dt)
  }
}

prev_dt[,run:=NULL]
prev_dt[,prev:=prev*100]
setnames(prev_dt, c('draw', 'prev'), c('run', 'draw'))
out.prev <- dcast.data.table(prev_dt,year~run, value.var='draw')
setnames(out.prev, as.character(1:n.draws), paste0('draw', 1:n.draws))
out.prev <- out.prev[order(year),]

write.csv(out.prev, file = paste0(prev_dir,"/",iso3,"_SPU_prev_draws.csv"), row.names=F)
print('Finished prevalence')

# replace_i_list <- as.numeric(gsub('[A-Za-z]*', '', replace_names))

tmp_iso3 <- ifelse(grepl('_',iso3), gsub('_[A-Za-z0-9]*', '', iso3), iso3)
progdata <- fread(paste0(aims_folder,"/strPath/",iso3,"_progression_par_draws.csv"))

if (length(missing.draws) > 0) {
  for (i in 1:length(missing.draws)) {
    tmp.vals <- progdata[draw==replace.with[i],]
    tmp.vals[,draw := missing.draws[i]]
    tmp.vals[,replace.me := TRUE]
    setnames(tmp.vals, 'prog', 'replace.prog')

    progdata <- merge(progdata, tmp.vals, by=c('age', 'cd4', 'draw'), all.x=TRUE)
    progdata[replace.me==TRUE, prog:=replace.prog]

    progdata[,replace.me := NULL]
    progdata[,replace.prog := NULL]
  }
}


write.csv(progdata, file = paste0(aims_folder,"/strPath/",iso3,"_progression_par_draws.csv"), row.names = F)
print('Finished progression')

mortnoart <- fread(paste0(aims_folder,"/strPath/",iso3,"_mortality_par_draws.csv"))

if (length(missing.draws) > 0) {
  for (i in 1:length(missing.draws)) {
    tmp.vals <- mortnoart[draw==replace.with[i],]
    tmp.vals[,draw := missing.draws[i]]
    tmp.vals[,replace.me := TRUE]
    setnames(tmp.vals, 'mort', 'replace.mort')

    mortnoart <- merge(mortnoart, tmp.vals, by=c('age', 'cd4', 'draw'), all.x=TRUE)
    mortnoart[replace.me==TRUE, mort:=replace.mort]

    mortnoart[,replace.me := NULL]
    mortnoart[,replace.mort := NULL]
  }
}

write.csv(mortnoart, file = paste0(aims_folder,"/strPath/",iso3,"_mortality_par_draws.csv"), row.names = F)
print('Finished without-ART mortality')

mortart <- fread(paste0(aims_folder,"/strPath/",iso3,"_HIVonART.csv"))

mortart.melted <- melt(mortart, id.vars=c('durationart', 'cd4_category', 'age', 'sex'), value.name='mort')
mortart.melted[,draw:=as.integer(gsub('draw','',variable))]
mortart.melted[,variable := NULL]

if (length(missing.draws) > 0) {
  for (i in 1:length(missing.draws)) {
    tmp.vals <- mortart.melted[draw==replace.with[i],]
    tmp.vals[,draw := missing.draws[i]]
    tmp.vals[,replace.me := TRUE]
    setnames(tmp.vals, 'mort', 'replace.mort')

    mortart.melted <- merge(mortart.melted, tmp.vals, by=c('durationart', 'cd4_category', 'age', 'sex', 'draw'), all.x=TRUE)
    mortart.melted[replace.me==TRUE, mort:=replace.mort]

    mortart.melted[,replace.me := NULL]
    mortart.melted[,replace.mort := NULL]
  }
}

out.mortart <- dcast.data.table(mortart.melted,durationart+cd4_category+age+sex~draw, value.var='mort')
setnames(out.mortart, as.character(1:n.draws), paste0('mort', 1:n.draws))
out.mortart <- out.mortart[order(durationart, cd4_category, age, sex)]

write.csv(out.mortart, file = paste0(aims_folder,"/strPath/",iso3,"_HIVonART.csv"), row.names = F)
print('Finished with-ART mortality')
