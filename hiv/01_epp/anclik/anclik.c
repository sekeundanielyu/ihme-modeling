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

#include <gsl/gsl_math.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_integration.h>
#include <gsl/gsl_rng.h>  // needed only for mvrandist.h

#include "mvrandist.h"


////////////////////////////////////////////////////////////////////////////////


struct anclik_integrand_param{
  size_t numsites;      // number of sites
  gsl_vector **dst;     // array of vectors: difference between observed and model (transformed)
  gsl_vector **vst;     // array of vectors: variance for each site (transformed)
  gsl_vector **mean;    // array of vectors: vector of 0s of appropriate length for each site
  gsl_matrix **sigma;   // array of matrices: matrix to use for each site covariances
  double s2_pr_alpha;
  double s2_pr_beta;
};
  
double anclik_integrand(double s2, void * params){

  struct anclik_integrand_param *p = (struct anclik_integrand_param *) params;

  double integrand = 0.0;
  for(size_t i = 0; i < p->numsites; i++){
    gsl_matrix_set_all(p->sigma[i], s2);
    for(size_t j = 0; j < p->vst[i]->size; j++)
      gsl_matrix_set(p->sigma[i], j, j, s2+gsl_vector_get(p->vst[i],j));
    integrand += ldmvnorm(p->dst[i], p->mean[i], p->sigma[i]);
  }

  integrand += log(s2)*(-p->s2_pr_alpha-1.0) - 1.0/(p->s2_pr_beta * s2);  // Note: omits normalising constant beta^alpha/Gamma(alpha).
  integrand = exp(integrand);

  return integrand;
}


double anclik(size_t numsites, gsl_vector **dst, gsl_vector **vst, gsl_vector **mean, gsl_matrix **sigma, double s2_pr_alpha, double s2_pr_beta){
  // numsites: number of size (length of arrays dst, vst, mean, sigma)
  // dst: array of vectors with differences between transformed observed and modelled prevalences
  // vst: array of vectors with clinic level variances (transformed) for each site
  // mean: vector of 0s for each clinic to pass to mean of dmvnorm.
  // sigma: covariance matrix of appropriate size for each clinic.
  // s2_pr_alpha: shape parameter for inverse-gamma prior on variance of clinic-level effects
  // s2_pr_beta: scale parameter for inverse-gamma prior on variance of clinic-level effects
  // NOTE: mean and sigma are passed as arguments so they can be allocated once and reused if calling anclik many times

  gsl_set_error_handler_off();
  
  double val, err;
  struct anclik_integrand_param param = {numsites, dst, vst, mean, sigma, s2_pr_alpha, s2_pr_beta};
  gsl_function anclik_integrand_f = {&anclik_integrand, &param};
  gsl_integration_workspace * wk = gsl_integration_workspace_alloc (1000);
  gsl_integration_qag(&anclik_integrand_f, 1.0e-15, 0.3, 0.0001220703, 0.0001220703, 1000, GSL_INTEG_GAUSS21, wk, &val, &err);

    
  // free memory
  gsl_integration_workspace_free(wk);

  return val;
}
