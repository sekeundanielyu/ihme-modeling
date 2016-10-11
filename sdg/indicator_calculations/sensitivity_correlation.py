'''
Author: Mollie Holmberg
Purpose: Calculate correlation coefficients for sensitivity analysis
Date: 8/9/2016
'''
import pandas as pd
import numpy as np
from scipy.stats import pearsonr, spearmanr
import sys

def run_correlations(df, varx, vary):
    r, p = pearsonr(df[varx], df[vary])
    result = spearmanr(df[varx], df[vary])
    rho = result[0]
    prho = result[1]
    return pd.DataFrame({
        'x':[varx], 
        'y':[vary], 
        'Pearson R':[r], 
        'Pearson p-value':[p], 
        'Spearman R':[rho], 
        'Spearman p-value':[prho]
        })

def compile_correlations(version):
    data = pd.read_csv('/home/j/WORK/10_gbd/04_journals/'\
        +'gbd2015_capstone_lancet_SDG/04_outputs/sensitivity_analysis/'\
        +'different_means_{}.csv'.format(version))

    # Run the correlations
    dfs = []
    for v in ['mean_val_arith','mean_val_geom_min','mean_val_raw_geom']:
        d = run_correlations(data, 'mean_val_geom', v)
        dfs.append(d)
    corrs = pd.concat(dfs)

	# Make it look nicer
    corrs = corrs.replace({'mean_val_geom':'Geometric mean across targets',
              'mean_val_arith':'Arithmetic mean across targets',
              'mean_val_geom_min':'Min value across targets',
              'mean_val_raw_geom':'Geometric mean across indicators'})
    corrs.to_csv('/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/'\
        +'04_outputs/sensitivity_analysis/correlation_coefficients_{}.csv'.format(version), index = False)

if __name__ == '__main__':
    sdg_vers = sys.argv[1]
    compile_correlations(sdg_vers)