##############################################################################
###                                                                        ###
###  Example of fitting EPP r-spline and r-trend model to data from        ###
###  to data from Botswana.                                                ###
###                                                                        ###
###  Created on 19 June 2015 by Jeff Eaton (jeffrey.eaton@imperial.ac.uk)  ###
###                                                                        ###
##############################################################################

get.script.dir <- function() {
  initial.options <- commandArgs(trailingOnly = FALSE)
  file.arg.name <- "--file="
  script.name <- sub(file.arg.name, "", initial.options[grep(file.arg.name, initial.options)])
  return(paste0(dirname(script.name),'/'))
}
args <- commandArgs(trailingOnly = TRUE)

model_name <- args[1]
i <- args[2]
iso3 <- args[3]
run_name <- args[4]

code_dir <- get.script.dir()

setwd(code_dir)

source("R/read_epp_files.R")  
source("R/epp.R")
source("R/likelihood.R")
library(ggplot2)
library(reshape)

data_dir <- '/strPath'
out.dir <- '/strPath'


## Function to do the following:
## (1) Read data, EPP subpopulations, and popualation inputs
## (2) Prepare timestep inputs for each EPP subpopulation

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

new.inf <- function(mod, fp) {
  attr(mod, "rvec")[fp$proj.steps %% 1 == 0.5] * (rowSums(mod[,-1,1]) + fp$relinfectART * rowSums(mod[,-1,-1])) / rowSums(mod) * mod[,1,1]
}
suscept.pop <- function(mod) {
  mod[,1,1]
}
plwh <- function(mod) {
  rowSums(mod[,-1,])
}
total.pop <- function(mod) {
  rowSums(mod)
}

fit.mod <- function(obj, ..., B0 = 1e5, B = 1e4, B.re = 3000, number_k = 500){
  ## ... : updates to fixed parameters (fp) object to specify fitting options
  
  likdat <<- attr(obj, 'likdat')  # put in global environment for IMIS functions.
  fp <<- attr(obj, 'eppfp')
  fp <<- update(fp, ...)
  
  fit <- IMIS(B0, B, B.re, number_k)
  fit$fp <- fp
  fit$likdat <- likdat

  rm(fp, likdat, pos=.GlobalEnv)

  return(fit)
}



load('strPath.RData')
dir.create(paste0(out.dir,'/',run_name,'/',iso3))

subpop <- names(bw.out)[1]

theta.rspline <- c(2.16003605, -0.76713859, 0.21682066, 0.03286402, 0.21494412,
                   0.40138627, -0.08235464, -16.32721684, 0.21625028, -2.97511957)


fp <- attr(bw.out[[subpop]], "eppfp")
param <- fnCreateParam(theta.rspline, fp)
print('test')
fp.rspline <- update(fp, list=param)
mod.rspline <- fnEPP(fp.rspline)


round(prev(mod.rspline), 3)               # prevalence


B0 <- 200000
B <- 1e3
B.re <- 5e2

result<-list()
for (subpop in names(bw.out)) {
  print(subpop)
  if (model_name == 'rspline')
    result[[subpop]] <- fit.mod(bw.out[[subpop]], equil.rprior=TRUE, B0=B0, B=B, B.re=B.re)

  if (model_name == 'rtrend')
    result[[subpop]] <- fit.mod(bw.out[[subpop]], eppmod="rtrend", iota=0.0025, B0=B0, B=B, B.re=B.re)
}



sim.mod <- function(fit){
  fit$param <- lapply(seq_len(nrow(fit$resample)), function(ii) fnCreateParam(fit$resample[ii,], fit$fp))
  fp.list <- lapply(fit$param, function(par) update(fit$fp, list=par))
  fit$mod <- lapply(fp.list, fnEPP)
  fit$prev <- sapply(fit$mod, prev)
  fit$incid <- mapply(incid, mod = fit$mod, fp = fp.list)
  fit$new.inf <- mapply(new.inf, mod = fit$mod, fp = fp.list)
  fit$suscept.pop <- sapply(fit$mod, suscept.pop)
  fit$plwh <- sapply(fit$mod, plwh)
  fit$total.pop <- sapply(fit$mod, total.pop)


  return(fit)
}

result <- lapply(result, sim.mod)

nat.draws <- function(result) {
  nat.inf <- Reduce('+', lapply(result, function(x){x$new.inf}))
  nat.suscept <- Reduce('+', lapply(result, function(x){x$suscept.pop}))

  nat.incid <- nat.inf/nat.suscept

  nat.plwh <- Reduce('+', lapply(result, function(x){x$plwh}))
  nat.total.pop <- Reduce('+', lapply(result, function(x){x$total.pop}))

  nat.prev <- nat.plwh/nat.total.pop
  output <- list(prev=nat.prev, incid=nat.incid)
  return(output)
}



cred.region <- function(x, y, ...)
  polygon(c(x, rev(x)), c(y[1,], rev(y[2,])), border=NA, ...)

transp <- function(col, alpha=0.5)
  return(apply(col2rgb(col), 2, function(c) rgb(c[1]/255, c[2]/255, c[3]/255, alpha)))

plot.prev <- function(fit, ylim=c(0, 0.22), col="blue"){
  plot(1970:2015, rowMeans(fit$prev), type="n", ylim=ylim, ylab="", yaxt="n", xaxt="n")
  axis(1, labels=FALSE)
  axis(2, labels=FALSE)
  cred.region(1970:2015, apply(fit$prev, 1, quantile, c(0.025, 0.975)), col=transp(col, 0.3))
  lines(1970:2015, rowMeans(fit$prev), col=col)
  ##
  points(fit$likdat$hhslik.dat$year, fit$likdat$hhslik.dat$prev, pch=20)
  segments(fit$likdat$hhslik.dat$year,
           y0=pnorm(fit$likdat$hhslik.dat$W.hhs - qnorm(0.975)*fit$likdat$hhslik.dat$sd.W.hhs),
           y1=pnorm(fit$likdat$hhslik.dat$W.hhs + qnorm(0.975)*fit$likdat$hhslik.dat$sd.W.hhs))
}

plot.incid <- function(fit, ylim=c(0, 0.05), col="blue"){
  plot(1970:2015, rowMeans(fit$incid), type="n", ylim=ylim, ylab="", yaxt="n", xaxt="n")
  axis(1, labels=FALSE)
  axis(2, labels=FALSE)
  cred.region(1970:2015, apply(fit$incid, 1, quantile, c(0.025, 0.975)), col=transp(col, 0.3))
  lines(1970:2015, rowMeans(fit$incid), col=col)
}

plot.rvec <- function(fit, ylim=c(0, 3), col="blue"){
  rvec <- lapply(fit$mod, attr, "rvec")
  rvec <- mapply(function(rv, par){replace(rv, fit$fp$proj.steps < par$tsEpidemicStart, NA)},
                 rvec, fit$param)
  plot(fit$fp$proj.steps, rowMeans(rvec, na.rm=TRUE), type="n", ylim=ylim, ylab="", yaxt="n")
  axis(2, labels=FALSE)
  cred.region(fit$fp$proj.steps, apply(rvec, 1, quantile, c(0.025, 0.975), na.rm=TRUE), col=transp(col, 0.3))
  lines(fit$fp$proj.steps, rowMeans(rvec, na.rm=TRUE), col=col)
}

pdffile <- paste0(out.dir, "strPath/test_results",i,".pdf")

pdf(pdffile, width=13, height=8)
years <- unique(floor(result[[1]]$fp$proj.steps))
nat.data <- nat.draws(result)
var_names <- sapply(1:ncol(nat.data$prev), function(a) {paste0('draw',a)})
out_data <- lapply(nat.data, data.frame)
for (n in c('prev', 'incid')) {
  names(out_data[[n]]) <- var_names
  out_data[[n]]$year <- years
  col_idx <- grep("year", names(out_data[[n]]))
  out_data[[n]] <- out_data[[n]][, c(col_idx, (1:ncol(out_data[[n]]))[-col_idx])]
  write.csv(out_data[[n]], paste0(out.dir, "strPath/results_",n,i,".csv"), row.names=FALSE)
}

for (subpop in names(result)) {
  country_name <- attr(result[[subpop]], 'country')

  site_names <- rownames(result[[subpop]]$likdat$anclik.dat$anc.prev)
  name <- site_names[1]

  bias_i <- ifelse(model_name=='rspline', ncol(result[[subpop]]$resample)-1, ncol(result[[subpop]]$resample)) 
  mean_bias <- mean(result[[subpop]]$resample[,bias_i])


  result[[subpop]]$likdat$anclik.dat$anc.prev <- pnorm(qnorm(result[[subpop]]$likdat$anclik.dat$anc.prev) - mean_bias)
  anc_plot_data <- melt(result[[subpop]]$likdat$anclik.dat$anc.prev)
  anc_plot_data$data_type <- 'Bias Adjusted ANC Data'
  anc_plot_data <- anc_plot_data[!is.na(anc_plot_data$value),]
  rownames(result[[subpop]]$prev) <- years
  prev_data <- melt(result[[subpop]]$prev)
  prev_data$data_type <- 'EPP Estimate'

  has_hhs <- ifelse(nrow(result[[subpop]]$likdat$hhslik.dat) > 0, TRUE, FALSE)
  if (has_hhs) {
    hhs_plot_data <- result[[subpop]]$likdat$hhslik.dat[,c('year', 'prev', 'W.hhs', 'sd.W.hhs')]
    hhs_plot_data$upper <- pnorm(hhs_plot_data$W.hhs + qnorm(0.975)*hhs_plot_data$sd.W.hhs)
    hhs_plot_data$lower <- pnorm(hhs_plot_data$W.hhs - qnorm(0.975)*hhs_plot_data$sd.W.hhs)
    hhs_plot_data$data_type <- "Survey Data"
  }
  c_palette <- c('#006AB8','#4D4D4D','#60BD68')
  gg <- ggplot() + geom_line(data=prev_data, aes(x=X1, y=value, colour=data_type, group=X2), alpha=0.1) +
    geom_line(data=anc_plot_data, aes(x=X2, y=value, colour=data_type, group=X1)) + 
    geom_point(data=anc_plot_data, aes(x=X2, y=value, colour=data_type, group=X1)) +
    scale_colour_manual(values=c_palette) + ggtitle(paste0(country_name,' ', subpop, ": ", model_name))
  if (has_hhs) {
    gg <- gg + geom_point(data=hhs_plot_data, aes(x=year, y=prev, colour=data_type), size=3) +
      geom_errorbar(data=hhs_plot_data, aes(x=year, ymax=upper, ymin=lower, colour=data_type), size=1)
  }
  print(gg)
  }
rownames(nat.data$prev) <- years
prev_data <- melt(nat.data$prev)
prev_data$data_type <- 'EPP Estimate'

gg <- ggplot() + geom_line(data=prev_data, aes(x=X1, y=value, colour=data_type, group=X2), alpha=0.1) +
  scale_colour_manual(values=c_palette) + ggtitle(paste0(country_name,' national', ": ", model_name))
print(gg)

dev.off()
