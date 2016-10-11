
setwd('anclik')
system("R CMD SHLIB -lgsl -lgslcblas anclikR.c anclik.c mvrandist.c")
dyn.load(paste("anclikR", .Platform$dynlib.ext, sep=""))
library(mvtnorm) # required for calling fnANClik with VERSION = "R"

fnPrepareANCLikelihoodData <- function(anc.prev, anc.n, anchor.year = 1970L, return.data=TRUE){
    ## anc.prev: matrix with one row for each site and column for each year
    ## anc.n: sample size, matrix with one row for each site and column for each year
    ## anchor.year: year in which annual prevalence output start -- to determine index to compare data
    ## NOTE: requires year to be stored in column names of anc.prev

    anc.prev <- anc.prev[apply(!is.na(anc.prev), 1, sum) > 0,] # eliminate records with no observations
    anc.n <- anc.n[apply(!is.na(anc.n), 1, sum) > 0,] # eliminate records with no observations

    tmp1 <- apply(!is.na(anc.prev), 1, which)
    tmp2 <- apply(!is.na(anc.n), 1, which)
    if (is.matrix(tmp1)) {
      tmp1 <- split(t(tmp1), colnames(tmp1))
      tmp2 <- split(t(tmp2), colnames(tmp2))

      ancobs.idx <- mapply(intersect, tmp1, tmp2)
      ancobs.idx <- split(t(ancobs.idx), colnames(ancobs.idx))
    } else {
      ancobs.idx <- mapply(intersect, tmp1, tmp2)  
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

fnANClik <- function(qM, anclik.dat, s2.pr.alpha = 0.58, s2.pr.beta = 93, VERSION="C"){
    ## qM: vector of probit-transformed annual prevalences (starting in anchor.year specified for anclik.dat)
    ## anclik.dat: list including transformed ANC prevalence data
    ## s2.pr.alpha: parameter for inverse-gamma prior on ANC site-level effects
    ## s2.pr.beta: parameter for inverse-gamma prior on ANC site-level effects
    
    d.lst <- mapply(function(w, idx) w - qM[idx], anclik.dat$W.lst, anclik.dat$anc.idx.lst)
    if (is.matrix(d.lst)) {
      d.lst <- split(d.lst, colnames(d.lst))
    }

    if (class(d.lst) != 'list') {
      d.lst <- split(d.lst, names(d.lst))
      d.lst <- lapply(d.lst, as.vector)
      anclik.dat$v.lst <- split(anclik.dat$v.lst, names(anclik.dat$v.lst))
      anclik.dat$v.lst <- lapply(anclik.dat$v.lst, as.vector)
    }
    if(VERSION == "R"){
        V.lst <- lapply(anclik.dat$v.lst, function(x) diag(x, nrow=length(x)))
        return(integrate(Vectorize(function(s2)
                                   exp(sum(mapply(dmvnorm, x=d.lst, sigma = lapply(V.lst, function(m) s2+m), MoreArgs=list(log=TRUE))))*s2^(-s2.pr.alpha-1)*exp(-1/(s2.pr.beta*s2))), 1e-15, 0.3, subdivisions=1000, stop.on.error=FALSE)$value)
    }
    
    return(.Call("anclikR", d.lst, anclik.dat$v.lst, s2.pr.alpha, s2.pr.beta))
}



sample.b.one <- function(d, v, s2.pr.alpha = 0.58, s2.pr.beta = 93){
  ## Use rejection sampling to sample clinic level effect (Alkema, Raftery, Clark 2007)
  ## p(b.s | M, W.s) \propto N( d.st, v.st) * (b.s^2/2 + 1/beta2)^(-alpha-1/2)
  ## 1) sample from normal distribution with weighted mean and variance
  ## 2) reject based on second term of product
  
  max.val <- (1/s2.pr.beta)^(-s2.pr.alpha-0.5)  # maximized when b=0, to normalize rejection sampling
  b <- Inf
  while(runif(1) > (0.5*b^2 + 1/s2.pr.beta)^(-s2.pr.alpha-0.5) / max.val)
    b <- rnorm(1, sum(d/v)/sum(1/v), 1/sum(1/v))
  return(b)
}

sample.b.site <- function(qM, anclik.dat, s2.pr.alpha = 0.58, s2.pr.beta = 93){
  ## Sample b.s values for all clinics
  ## parameters defined the same as fnANClik
  
  d.lst <- mapply(function(w, idx) w - qM[idx], anclik.dat$W.lst, anclik.dat$anc.idx.lst)
  return(mapply(sample.b.one, d.lst, anclik.dat$v.lst, s2.pr.alpha, s2.pr.beta))
}


sample.pred.site <- function(qM, b.site, anclik.dat, v.infl=0){
  ## Sample predicted prevalences in the same years as observed ANC prevalences in each site

  ## qM: vector of probit-transformed annual prevalences (starting in anchor.year specified for anclik.dat)
  ## b.site: vector of site-level random effects
  ## v.infl: additive variance term to (tranformed) binomial variance
  ## Note: b.site must be drawn from same posterior sample as qM (b.site | qM)!!!

  ## site-level fitted values
  fit.site <- mapply(function(b, idx) qM[idx] + b, b.site, anclik.dat$anc.idx.lst)

  ## variance fitted values
  vpred.site <- mapply(function(pred, n) 2*pi*exp(pred^2)*pnorm(pred)*(1-pnorm(pred)) / n + v.infl, fit.site, anclik.dat$n.lst)

  ## predicted values (probit scale)
  pred.site <- mapply(rnorm, sapply(fit.site, length), fit.site, lapply(vpred.site, sqrt))
  
  return(lapply(pred.site, pnorm)) # natural scale
}
