## Modified from IMIS package by Le Bao (http://cran.r-project.org/web/packages/IMIS/)

IMIS <- function(B0, B, B.re, number_k){
  X_k <- sample.prior(B0)                                
  c_names <- colnames(X_k)
  X_all = matrix(0, B0 + B*number_k, dim(X_k)[2])
  n_all <- 0
  X_all[1:B0,] <- X_k
    Sig2_global = cov(X_all[1:B0,])        # the prior covariance
  stat_all = matrix(NA, 6, number_k)                            # 6 diagnostic statistics at each iteration
  ##center_all = prior_all = like_all = NULL                      # centers of Gaussian components, prior densities, and likelihoods
  center_all = NULL
  prior_all = like_all = gaussian_sum = vector("numeric", B0 + B*number_k)
  sigma_all = list()                                            # covariance matrices of Gaussian components
  
  iter.start.time = proc.time()
  for (k in 1:number_k ){
    ptm.like = proc.time()
    prior_all[n_all + 1:dim(X_k)[1]] <-  prior(X_k)
    like_all[n_all + 1:dim(X_k)[1]] <-  likelihood(X_k)
    ptm.use = (proc.time() - ptm.like)[3]
    if (k==1)   print(paste(B0, "likelihoods are evaluated in", round(ptm.use/60,2), "minutes"))
    which_pos <- which(like_all[1:(n_all + dim(X_k)[1])] > 0)
    resample_n <- round(B0*0.0002)
    if (k == 1 & length(which_pos) < resample_n) {
      new_sample <- X_k
      print (paste("Resampling to get at least", resample_n ,"nonzero initial samples..."))
      print ("Consider raising B0...")
      new_like <- like_all
      tmp_which_pos <- which(new_like[1:(n_all + dim(new_sample)[1])] > 0)
      n_added <- 0
      print(paste('n_added =',length(tmp_which_pos),'of',resample_n))
      while (length(tmp_which_pos) < resample_n) {
        tmp_X_k <- sample.prior(B0)
        tmp_like <- likelihood(tmp_X_k)
        additions <- which(tmp_like[1:(n_all + dim(tmp_X_k)[1])] > 0)
        if (length(additions) > 0) {
          new_sample[(n_added+1):(n_added+1+length(additions)-1),] <- tmp_X_k[additions,]
          new_like[(n_added+1):(n_added+1+length(additions)-1)] <- tmp_like[additions]
          tmp_which_pos <- which(new_like[1:(n_all + dim(new_sample)[1])] > 0)
          n_added <- n_added + length(additions)
          print(paste('n_added =',length(tmp_which_pos),'of',resample_n))
        }
      }
      print ("Finished resampling")
      X_k <- new_sample
      X_all[1:B0,] <- X_k
      
      Sig2_global = cov(X_all[1:B0,])        # the prior covariance
      ptm.like = proc.time()
      prior_all[n_all + 1:dim(X_k)[1]] <-  prior(X_k)
      like_all[n_all + 1:dim(X_k)[1]] <-  likelihood(X_k)
      ptm.use = (proc.time() - ptm.like)[3]
      which_pos <- tmp_which_pos
      print(which_pos)
    }
    if(k > 2)
      gaussian_sum[(n_pos+1):length(which_pos)] <- rowSums(sapply(1:(k-2), function(j)dmvnorm(X_all[which_pos[(n_pos+1):length(which_pos)],], center_all[j,], sigma_all[[j]])))
    if(k > 1){
      n_pos <- length(which_pos)
      gaussian_sum[1:n_pos] <- gaussian_sum[1:n_pos] + dmvnorm(X_all[which_pos,], center_all[k-1,], sigma_all[[k-1]])
    }

    
    if (k==1)   envelop_pos = prior_all[which_pos]        # envelop stores the sampling densities
    if (k>1)    envelop_pos = (prior_all[which_pos]*B0/B + gaussian_sum[1:n_pos]) / (B0/B+(k-1))
    Weights = prior_all[which_pos]*like_all[which_pos]/ envelop_pos  # importance weight is determined by the posterior density divided by the sampling density
    stat_all[1,k] = log(mean(Weights)*length(which_pos)/(n_all+dim(X_k)[1]))                  # the raw marginal likelihood
    Weights = Weights / sum(Weights)
    stat_all[2,k] = sum(1-(1-Weights)^B.re)             # the expected number of unique points
    stat_all[3,k] = max(Weights)                                # the maximum weight
    stat_all[4,k] = 1/sum(Weights^2)                    # the effictive sample size
    stat_all[5,k] = -sum(Weights*log(Weights), na.rm = TRUE) / log(length(Weights))     # the entropy relative to uniform
    stat_all[6,k] = var(Weights/mean(Weights))  # the variance of scaled weights
    if (k==1)   print("Stage   MargLike   UniquePoint   MaxWeight   ESS   IterTime")
    iter.stop.time = proc.time()
    print(c(k, round(stat_all[1:4,k], 3), as.numeric(iter.stop.time - iter.start.time)[3]))
    iter.start.time = iter.stop.time

    ## choose the important point
    important = which(Weights == max(Weights))
    if (length(important)>1)  important = important[1]
    X_imp = X_all[which_pos[important],]
    center_all = rbind(center_all, X_imp)
    distance_all = mahalanobis(X_all[1:(n_all+dim(X_k)[1]),], X_imp, diag(diag(Sig2_global)) )
    label_nr = sort(distance_all, decreasing = FALSE, index=TRUE, method="quick")             # Sort the distances
    which_var = label_nr$ix[1:B]                                                              # Pick B inputs for covariance calculation

    ###########
    weight_close <- Weights[match(which_var, which_pos)]
    weight_close[!which_var %in% which_pos] <- 0
    
    Sig2 = cov.wt(X_all[which_var,], wt = weight_close+1/(n_all + dim(X_k)[1]), cor = FALSE, center = X_imp, method = "unbias")$cov
    sigma_all[[k]] = Sig2
    n_all <- n_all + dim(X_k)[1]
    if (is.matrix(X_all))     X_k = rmvnorm(B, X_imp, Sig2)                           # Draw new samples
    X_all[n_all + 1:B,] <- X_k
    colnames(X_k) <- c_names
    
    if (stat_all[2,k] > (1-exp(-1))*B.re)       break
  } # end of k
  which_X = sample(which_pos, B.re, replace = TRUE, prob = Weights)
  if (is.matrix(X_all)) resample_X = X_all[which_X,]

  return(list(stat=t(stat_all), resample=resample_X, center=center_all))
} # end of IMIS
