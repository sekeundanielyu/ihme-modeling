"""

Description: 

"""
import pandas as pd
from pymc import gp
#from scipy import stats
import numpy as np

## UTILITY FUNCTIONS
def invlogit(x):
    return np.exp(x)/(np.exp(x)+1)

def logit(x):
    return np.log(x / (1-x))
    
def invlogit_var(mu,var):
    return (var * (np.exp(mu)/(np.exp(mu)+1)**2)**2)
    
def logit_var(mu,var):
    return (var / (mu*(1-mu))**2)
    
    
## GPR FUNCTION
def fit_gpr(df, amp, obs_variable='observed_data', obs_var_variable='obs_data_variance', mean_variable='st_prediction', year_variable='year', scale=30, diff_degree=2, draws=0):
        
    # create a dataframe with non-null 1st stagemodel  data and variance 
    data = df.ix[(pd.notnull(df[obs_variable])) & (pd.notnull(df[obs_var_variable]))]
   
   # establish mean_prior data frame 
    mean_prior = df[[year_variable, mean_variable]].drop_duplicates()
    
    # define function that interpolates data (estimates values) based on the mean prior varaiables
    def mean_function(x):
        return np.interp(x, mean_prior[year_variable], mean_prior[mean_variable])
    M = gp.Mean(mean_function)
    
    # create a covariance matrix
    C = gp.Covariance(eval_fun=gp.matern.euclidean, diff_degree  =diff_degree, amp = amp, scale = scale)
    if len(data)>0:
        gp.observe(M=M, C=C, obs_mesh=data[year_variable], obs_V=data[obs_var_variable], obs_vals=data[obs_variable])
    
    # calculate the model mean based on the mean prior prediction
    model_mean = M(mean_prior[year_variable]).T

    # calculate the variance based on the covaraince of the mean prior, then use that to calculate the confidence interval
    model_variance = C(mean_prior[year_variable])
    model_lower = model_mean - np.sqrt(model_variance)*1.96
    model_upper = model_mean + np.sqrt(model_variance)*1.96
    
    if draws > 0:  
        real_draws = pd.DataFrame({year_variable:mean_prior[year_variable],'gpr_mean':model_mean,'gpr_var':model_variance,'gpr_lower':model_lower,'gpr_upper':model_upper})

        real_years = range(real_draws[year_variable].min(), real_draws[year_variable].max()+1)
        ## create realizations one at a time to reduce computational load        
        realizations = []        
        for i in range(draws):        
            realizations.append(gp.Realization(M, C)(real_years))
  
        for i in range(0,len(realizations)):
            real_draws['draw{}'.format(i)] = realizations[i]
            
        real_draws = pd.merge(df,real_draws,on=year_variable,how='left')
        
        return real_draws
    
    else:
        results = pd.DataFrame({year_variable:mean_prior[year_variable],'gpr_mean':model_mean,'gpr_var':model_variance,'gpr_lower':model_lower,'gpr_upper':model_upper})
        results = pd.merge(df,results,on=year_variable,how='left')
        
        return results