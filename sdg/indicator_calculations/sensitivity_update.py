'''
Date: 8/8/2016
Purpose: Run updated sensitivity analysis for Lancet revision
'''
import pandas as pd 
import numpy as np 
from scipy.stats.mstats import gmean
import sys

from getpass import getuser
if getuser() == 'strUser':
    SDG_REPO = "/homes/strUser/sdg-capstone-paper-2015"
if getuser() == 'strUser':
    SDG_REPO = '/homes/strUser/sdgs/sdg-capstone-paper-2015'
if getuser() == 'strUser':
    SDG_REPO = ('/ihme/code/test/strUser/under_development'
                '/sdg-capstone-paper-2015')
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test

indicators_master = '/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv'

def arithmetic_mean(arr):
    return np.mean(arr)

def geometric_mean(arr):
    return gmean(arr)

def take_min(arr):
	return np.min(arr)

def floor(arr):
	arr[arr < 0.01] = 0.01
	return arr

def copyit(arr):
	return arr

def apply_methods(version, target_method, summary_method):
	'''
	version: int, SDG version
	target_method: function, how to summarize over target
	summary_method: function, how to summarize across target summaries

	returns dataframe with correct summary methods applied
	'''
	# Load data and merge on targets
	data = pd.read_csv('/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/'\
		+'04_outputs/indicator_values/indicators_scaled_{}.csv'.format(version))
	meta = pd.read_csv(indicators_master)
	data = data.merge(meta, on = 'indicator_id', how = 'left')
	data = data[['indicator_id','indicator_target','location_id','year_id','mean_val']]

	#Apply the floor
	data['mean_val'] = floor(data['mean_val'].values)

	# Apply summary method by target - geometric or arithmetic mean
	if target_method != copyit:
		data = data.groupby(['indicator_target','location_id','year_id'], as_index = False).aggregate(target_method)
	
	data['mean_val'] = floor(data['mean_val'].values)

	# Save intermediates
	if target_method == arithmetic_mean:
		tag = 'arithmetic_mean'
	elif target_method == geometric_mean:
		tag = 'geometric_mean'

	if target_method != copyit:
		data.to_csv('/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/'\
			+'04_outputs/sensitivity_analysis/{v}_{t}_intermediates.csv'.format(t=tag, v=version), index = False)

	data.drop('indicator_target', axis = 1, inplace = True)

	# Now summarize across all the targets
	data = data.groupby(['location_id','year_id'], as_index = False).aggregate(summary_method)

	data = data[['location_id','year_id','mean_val']]

	return data

def run_all(version):
	arith = apply_methods(version, arithmetic_mean, arithmetic_mean)
	geom1 = apply_methods(version, geometric_mean, geometric_mean)
	geom2 = apply_methods(version, geometric_mean, take_min)
	rawgeom = apply_methods(version, copyit, geometric_mean)

	together = arith.merge(geom1, on = ['location_id','year_id'], suffixes = ('_arith','_geom'))\
					.merge(geom2, on = ['location_id','year_id'])\
					.merge(rawgeom, on = ['location_id','year_id'], suffixes = ('_geom_min','_raw_geom'))
	#together = together.rename(columns = {'mean_val':'mean_val_geom_min'})

	# Generate ranks for each mean
	together = together.sort_values(by = ['year_id','mean_val_arith'], ascending = False)\
						.reset_index(drop=True).reset_index()
	together = together.rename(columns = {'index':'rank_arithmetic_mean'})

	together = together.sort_values(by = ['year_id','mean_val_geom'], ascending = False)\
						.reset_index(drop=True).reset_index()
	together = together.rename(columns = {'index':'rank_geometric_mean'})

	together = together.sort_values(by = ['year_id','mean_val_geom_min'], ascending = False)\
						.reset_index(drop=True).reset_index()
	together = together.rename(columns = {'index':'rank_geometric_min'})

	together = together.sort_values(by = ['year_id','mean_val_raw_geom'], ascending = False)\
						.reset_index(drop=True).reset_index()
	together = together.rename(columns = {'index':'rank_raw_geom'})

	for col in ['rank_arithmetic_mean','rank_geometric_mean','rank_geometric_min','rank_raw_geom']:
		together[col] = together[col] + 1 - 192*((2015-together['year_id'])/5)

	# Save data
	together.to_csv('/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/'\
		+'04_outputs/sensitivity_analysis/different_means_{}.csv'.format(version), index = False)

if __name__ == '__main__':
	sdg_vers = sys.argv[1] # argparse is only useful for more complicated things
	run_all(sdg_vers)