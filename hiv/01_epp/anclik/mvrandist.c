/***************************************************************************************
 *  Multivariate Gaussian probability (log) density function
 *  Using the GSL - GNU Scientific Library. Visit www.gnu.org/software/gsl
 *  
 *  Initially based on code from Ralph dos Santos Silva: http://www.im.ufrj.br/ralph/downloads/mvrandist.tar.gz
 *  Copyright (C) 2007  Ralph dos Santos Silva
 *  
 *  Revised to (1) return log density, (2) use Cholesky decomposition instead of
 *  LU composition, and (3) omit other unecessary memory allocation.
 *
 ***************************************************************************************/

#include <math.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_matrix.h>
#include <gsl/gsl_blas.h>
#include <gsl/gsl_linalg.h>

/*****************************************************************************************************************/
double ldmvnorm(const gsl_vector *x, const gsl_vector *mean, const gsl_matrix *sigma){
  /* This function computes the log probability density log[p(x)] at x for a multivariate Gaussian distribution.
   *     mean   = the mean vector, size n
   *     sigma  = variance-covariance matrix, dimension n x n
   */

  if( (x->size != mean->size) || (mean->size != sigma->size1) || (sigma->size1 != sigma->size2)){
    GSL_ERROR("Incompatible dimensions in ldmvnorm", GSL_EINVAL);
  }

  // Create working copies of x and sigma (for in place manipulations)
  gsl_vector *x_cpy = gsl_vector_alloc(x->size);
  gsl_matrix *sigma_cpy = gsl_matrix_alloc(sigma->size1, sigma->size2);

  gsl_vector_memcpy(x_cpy, x);
  gsl_matrix_memcpy(sigma_cpy, sigma);
  

  // Calculate the pdf
  gsl_vector_sub(x_cpy, mean);

  gsl_linalg_cholesky_decomp(sigma_cpy);
  gsl_blas_dtrsv(CblasLower, CblasNoTrans, CblasNonUnit, sigma_cpy, x_cpy); // inv(L) %*% (x-mean)

  double rss;
  gsl_blas_ddot(x_cpy, x_cpy, &rss); // (x-mean)' %*% inv(sigma) %*% (x-mean)
  
  double logsqrtdet = 0.0;
  for(size_t i = 0; i < x->size; i++)
    logsqrtdet += log(gsl_matrix_get(sigma_cpy, i, i));
  
  double val = -logsqrtdet - 0.5 * x->size * log(2*M_PI) - 0.5 * rss;

  gsl_vector_free(x_cpy);
  gsl_matrix_free(sigma_cpy);
  
  return val;
}
/*****************************************************************************************************************/
double dmvnorm(const gsl_vector *x, const gsl_vector *mean, const gsl_matrix *sigma){
  /* This function computes the probability density p(x) at x for a multivariate Gaussian distribution.
   *     mean   = the mean vector, size n
   *     sigma  = variance-covariance matrix, dimension n x n
   */

  return exp(ldmvnorm(x, mean, sigma));
}
