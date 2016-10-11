/******************************************************************************************
 *
 *  This implements the random effects likelihood for ANC HIV prevalence described by
 *  Alkema, Raftery, Clark Ann Appl Stat 2007. (http://dx.doi.org/10.1214/07-AOAS111)
 *
 *  It relies on GNU Scientific Library (GSL) for QAG numerical integration routine
 *
 *  GPLv3, no warranty, etc...
 *
 *  Created by Jeff Eaton on 2014-11-12 <jeffrey.eaton@imperial.ac.uk>
 *
 *****************************************************************************************/

double anclik(size_t numsites, gsl_vector **dst, gsl_vector **vst, gsl_vector **mean, gsl_matrix **sigma, double s2_pr_alpha, double s2_pr_beta);
// numsites: number of size (length of arrays dst, vst, mean, sigma)
// dst: array of vectors with differences between transformed observed and modelled prevalences
// vst: array of vectors with clinic level variances (transformed) for each site
// mean: vector of 0s for each clinic to pass to mean of dmvnorm.
// sigma: covariance matrix of appropriate size for each clinic.
// s2_pr_alpha: shape parameter for inverse-gamma prior on variance of clinic-level effects
// s2_pr_beta: scale parameter for inverse-gamma prior on variance of clinic-level effects
// NOTE: mean and sigma are passed as arguments so they can be allocated once and reused if calling anclik many times
