/******************************************************************************************
 *
 *  Creates wrapper function to call anclik from R using GSL. Likelihood based on 
 *  Alkema, Raftery, Clark Ann Appl Stat 2007. (http://dx.doi.org/10.1214/07-AOAS111)
 *
 *  GPLv3, no warranty, etc...
 *
 *  Created by Jeff Eaton on 2014-11-12 <jeffrey.eaton@imperial.ac.uk>
 *
 *****************************************************************************************/

#include <R.h>
#include <Rinternals.h>

#include <gsl/gsl_vector.h>
#include <gsl/gsl_matrix.h>

#include "anclik.h"

SEXP anclikR(SEXP s_dst, SEXP s_vst, SEXP s_s2_pr_alpha, SEXP s_s2_pr_beta){
  // s_dst: list of vectors with differences between transformed observed and modelled prevalences
  // s_vst: list of vectors with clinic level variances (transformed) for each site
  // s_s2_pr_alpha: parameter for inverse-gamma prior on variance of clinic-level effects
  // s_s2_pr_beta: parameter for inverse-gamma prior on variance of clinic-level effects

  size_t numsites = length(s_dst);

  gsl_vector **dst = malloc(numsites * sizeof(gsl_vector*));
  gsl_vector **vst = malloc(numsites * sizeof(gsl_vector*));
  gsl_vector **mean = malloc(numsites * sizeof(gsl_vector*));
  gsl_matrix **sigma = malloc(numsites * sizeof(gsl_matrix*));
  
  // Copy R vectors into GSL vectors.
  for(size_t site = 0; site < numsites; site++){

    size_t nobs = length(VECTOR_ELT(s_dst, site));

    dst[site] = gsl_vector_alloc(nobs);
    vst[site] = gsl_vector_alloc(nobs);
    mean[site] = gsl_vector_calloc(nobs);  // initialize to 0
    sigma[site] = gsl_matrix_alloc(nobs, nobs);

    gsl_vector_view vw_tmp;
    vw_tmp = gsl_vector_view_array(REAL(VECTOR_ELT(s_dst, site)), nobs);
    gsl_vector_memcpy(dst[site], &vw_tmp.vector);
    vw_tmp = gsl_vector_view_array(REAL(VECTOR_ELT(s_vst, site)), nobs);
    gsl_vector_memcpy(vst[site], &vw_tmp.vector);
  }

  // create R object for return and call anclik
  SEXP s_val;
  PROTECT(s_val = allocVector(REALSXP, 1));
  *REAL(s_val) = anclik(numsites, dst, vst, mean, sigma, *REAL(s_s2_pr_alpha), *REAL(s_s2_pr_beta));;
  UNPROTECT(1);

  // free memory
  for(size_t i = 0; i < numsites; i++){
    gsl_vector_free(dst[i]);
    gsl_vector_free(vst[i]);
    gsl_vector_free(mean[i]);
    gsl_matrix_free(sigma[i]);
  }
  free(dst);
  free(vst);
  free(mean);
  free(sigma);

  return s_val;
}
