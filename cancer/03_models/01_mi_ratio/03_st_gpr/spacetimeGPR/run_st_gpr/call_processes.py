
"""

Description: Defines ST, GPR, and Finalization for MI Models

"""
################################
## Ensure essential libraries are loaded
################################
## determine system and change working directory
from platform import system
from os import chdir
root = "/home/j/" if system() == 'Linux' else "J:/"
chdir(root+'WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/03_st_gpr/spacetimeGPR/run_st_gpr')

## Import libraries
import pandas as pd
import numpy as np
import os, sys
from time import sleep

## Import gpr (used by multiple functions)
import gpr.gpr as gpr
reload(gpr)

## Set numpy to run without warnings for invalid entries
np.seterr(invalid='ignore')

################################
## Smooth data with spacetime (all countries)
################################
def run_Spacetime(linear_results, st_results):
	## Import Libraries	   
	import spacetime.spacetime as st
	reload(st)
	
	print "..."
	print "Applying ST-Smoothing"
	print "..."
	
	## Read input data
	input_data= pd.read_csv(linear_results)
	input_data = input_data.where((pd.notnull(input_data)), None)
	input_data.convert_objects(convert_numeric = True)
	input_data.ix[:5]	 
   
	## Adjust location variable
	from datetime import date
	if date.today().year == 2016 and 'iso3' in input_data.columns.values: input_data.rename(columns={'iso3':'ihme_loc_id'}, inplace=True)
   
	# Initialize the smoother
	s = st.Smoother(input_data)
	
	# Set parameters (can additionally specify omega (age weight, positive real number) and zeta (space weight, between 0 and 1))
	s.lambdaa = 1
	s.omega = 2
	s.zeta = .9
	s.zeta_no_data = 0.5
	s.lambdaa_no_data = 3
	
	# Tell the smoother to calculate both time weights and age weights
	s.age_weights()
	
	## Could move time weights into s.smooth in order to be able to specify differnet lambdas for each country
	s.time_weights()
	
	# Run the smoother and write the results to a file
	s.smooth()
	results = s.format_output(include_mad=False)
	results.to_csv(st_results, index=False)
	
	
###############################
## Run GPR for the input
################################
def run_GPR(st_results, output_directory, gpr_output_suffix, sr = '', ihme_loc_id = '', num_draws = 0):	   
	## Import Libraries
	import gpr.gpr as gpr
	reload(gpr)		   
	
	##
	print "..."
	print "Applying GPR"
	print "..."
	
	##
	if ihme_loc_id == 'all': ihme_loc_id = ''	 
	
	##
	input_data = pd.read_csv(st_results)
	
	## Produce GPR estimates   
	gpr_output = pd.DataFrame()
	iso_list = pd.unique(input_data['ihme_loc_id']) if not ihme_loc_id else [ihme_loc_id] 
	for iso in iso_list:
		print iso
		iso_results = input_data.loc[input_data.ihme_loc_id==iso, :]
		for age in pd.unique(input_data['age']): 
			if num_draws: print '	age {}'.format(age)
			# Run one country-age group at a time
			iso_age_results = iso_results.ix[iso_results.age==age]
			# Use the maximum (age-specific) global mad to determine the amplitude (see st_gpr_input script)
			amp = iso_age_results.global_mad.max()
			if (np.isnan(amp)): 
				quit("ERROR: global mad not specified for {} age {}".format(iso, age))
			## generate gpr output
			gpr_out = gpr.fit_gpr(iso_age_results, amp=amp, draws=num_draws)
			# Append the results for this country-age run of gpr to all results
			gpr_output = gpr_output.append(gpr_out)
			if len(gpr_output[pd.notnull(gpr_output['gpr_mean'])]) == 0:
				quit("ERROR: no gpr output for age {}".format(age))
	
	## Define and reorder columns
	if num_draws:
		draw_cols = [n for n in list(gpr_output.columns.values) if any(var in n for var in ['draw'])]
		data_cols = ['observed_data', 'stage1_prediction', 'st_prediction', 'gpr_mean'] + draw_cols	   
	else:
		data_cols = ['observed_data', 'stage1_prediction', 'st_prediction', 'gpr_mean', 'gpr_lower', 'gpr_upper']
		
	meta_cols = ['ihme_loc_id', 'location_id', 'year', 'age', 'obs_data_variance', 'developed', 'cases']
	
	column_order = meta_cols + data_cols
	results = gpr_output[column_order]
	column_order.extend(list(set(results.columns) - set(column_order)))
		
	## Verify Presence of all data
	if ihme_loc_id == '' :
		if results.shape[0] != input_data.shape[0]: quit("ERROR: some data were lost during gpr")  
	else:
		if results.shape[0] != input_data[input_data.ihme_loc_id == ihme_loc_id].shape[0]: quit("ERROR: some data were lost during gpr")		
	
	## Save output
	gpr_output_file = output_directory + sr + gpr_output_suffix if ihme_loc_id == '' else output_directory + ihme_loc_id + gpr_output_suffix
	if num_draws: print("Saving draws to {}".format(gpr_output_file))
	else:	 print("Saving gpr results to {}".format(gpr_output_file))
	if not os.path.isdir(os.path.dirname(gpr_output_file)):
		os.makedirs(os.path.dirname(gpr_output_file))
	results[column_order].to_csv(gpr_output_file, index=False)
	   
###############################
## Finalize estimates for the input. Replace estimates for developing countries that are lower than those of the USA
################################
def finalize_estimates(output_directory, gpr_output_suffix, final_output_suffix, sr = '', ihme_loc_id='', modnum = 0, cause = '', sex=''):
	print "..."
	print "Finalizing Estimates"
	print "..."
	
	## Import Libraries
	import re

	## Get upper cap
	model_control = pd.read_csv('/home/j/WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/_launch/model_control.csv')
	upper_cap = float(model_control.upper_cap[model_control.modnum == int(modnum)])
	
	## Determine run type
	if sr in ['0', 'none', 'any']: sr = ''
	if ihme_loc_id == 'all': ihme_loc_id = ''
	
	## Get input data	 
	if ihme_loc_id != '': 
		ihme_loc_output = output_directory + ihme_loc_id + gpr_output_suffix
		if os.path.isfile(ihme_loc_output):
			input_data = pd.read_csv(ihme_loc_output)
		else:
			input_data = pd.read_csv(output_directory + sr + gpr_output_suffix)
			input_data = input_data[input_data['ihme_loc_id'] == ihme_loc_id]					 
	else:
		input_data = pd.read_csv(output_directory + sr + gpr_output_suffix)
	 
	## Check input_data
	if input_data.shape[0] == 0: 
		print "ERROR: no input data"
		return False	 
	 
	## Define and reorder columns
	if any(item.startswith('draw') for item in input_data.columns.values):
		has_draws = True
		draw_cols = [n for n in list(input_data.columns.values) if any(var in n for var in ['draw'])]  #get only columns with "draw" in the name
		data_cols = ['observed_data', 'stage1_prediction', 'st_prediction', 'gpr_mean'] + draw_cols	   
	else:
		has_draws = False
		data_cols = ['observed_data', 'stage1_prediction', 'st_prediction', 'gpr_mean', 'gpr_lower', 'gpr_upper']
		
	meta_cols = ['ihme_loc_id', 'location_id', 'year', 'age', 'obs_data_variance', 'developed', 'cases']
	
	column_order = meta_cols + data_cols
	column_order.extend(list(set(input_data.columns) - set(column_order)))
			
	## Merge with the USA prediction (used in verification step below)
	is_USA = False if not re.search('USA', ihme_loc_id) else True	 
	if is_USA:
		merged_results = input_data	 
		convert_cols = data_cols
	else:	  
		print("Merging with USA data for comparison...")
		## Set us_data_file depending on process type. Outputs saved at the draw level should always be country-specific
		us_data_file = output_directory + '64' + gpr_output_suffix if not has_draws else output_directory + 'USA' + gpr_output_suffix		 
		   
		## Import USA data
		if not os.path.exists(us_data_file): quit("ERROR: Cannot finalize without USA gpr output")
		us_input = pd.read_csv(us_data_file)
		us_data = us_input[us_input.location_id == 102] 
			
		## Subset US data
		us_cols = ['year', 'age', 'gpr_mean']
		us_preds = us_data[us_cols]
		us_preds.columns = ['year', 'age', 'us_mean']
		
		## Verify that all data are present
		if input_data.shape[0] != us_preds.shape[0]: 
			print "ERROR: input data does not have same metadata as us predictions"
			return False

		## merge with us predictions
		merged_results = pd.merge(input_data, us_preds, on=['year', 'age'], how='left', sort=False)
		convert_cols = data_cols + ['us_mean']	   
								  
	## Transform data out of log or logit space
	print("Reverting from logit space...")
	def transformData(x):
		if not pd.isnull(x): x = upper_cap*gpr.invlogit(x)
		return(x)
	
	for col in convert_cols:
		if col != 'observed_data' and merged_results[col].isnull().sum(): 
			print "ERROR: missing values for model results in {}".format(col)
			return False
		merged_results[col] = merged_results[col].apply(transformData)
	
	## Verify conversion	
	print("Verifying conversion...")
	for col in convert_cols:
		if col == 'observed_data': 
			continue
		if merged_results[col].min() < 0 or merged_results[col].max() > upper_cap:
			quit("ERROR: error in data reversion of {}".format(col))
			
	## Replace final predictions for developing countries that are lower than the USA prediction with the USA prediction
	if is_USA:
		final_results = merged_results
	if not is_USA:	  
		print("Verifying results...")
		check_results = merged_results.loc[(merged_results['gpr_mean'] < merged_results['us_mean']) & (merged_results['developed'] == 0), :]
		if check_results.shape[0] == 0:
			final_results = merged_results
		else:
			print("Adjusting unrealistic results...")
			## separate results by type	   
			acceptable_results = merged_results.loc[(merged_results['gpr_mean'] > merged_results['us_mean']) | (merged_results['developed'] == 1), :]
			replaced_columns = ['gpr_mean', 'gpr_lower','gpr_upper'] + draw_cols if has_draws else ['gpr_mean', 'gpr_lower','gpr_upper']
			kept_columns = [n for n in list(check_results.columns.values) if not any(var in n for var in replaced_columns)]			   
			adjust_results = check_results[kept_columns]

			## revert us_data	 
			replacement_cols = us_cols + draw_cols if has_draws else ['year', 'age', 'gpr_mean', 'gpr_lower','gpr_upper']
			for col in data_cols:			 
				us_data[col] = us_data[col].apply(transformData)

			## replace results	  
			replaced_results = pd.merge(adjust_results, us_data[replacement_cols], on=['year','age'], how='left', sort=False)
			replaced_results['replaced_with_US_pred'] = 1
			final_results = acceptable_results.append(replaced_results)

			# check for errors			  
			error_replacing = True if final_results[(final_results['gpr_mean'] < final_results['us_mean']) & (final_results.developed == 0)].shape[0] else False  #if there are any rows that are still unrealistic
			if len(final_results['age'].unique()) < len(input_data['age'].unique()): error_replacing = True
			if error_replacing: 
				print "ERROR: error replacing unrealistic results"
				return False	   
	
	## Format
	if sr != '64' and not is_USA: final_results = final_results[final_results['ihme_loc_id'] != "USA"]
	final_results['model_number'] = modnum
	final_results['acause'] = cause
	final_results.rename(columns={'cases': 'cases_input'}, inplace=True)
	if not has_draws:
		final_results['sex'] = sex
		column_order = list(final_results.columns.values)
	else:
		final_results['sex'] = 1 if sex == 'male' else 2 
		column_order = [x for x in list(final_results.columns.values) if x not in draw_cols]
		column_order = column_order + draw_cols
	
	## Drop cases column to prevent confusion when using the MI estimates for other models
	column_order =	[n for n in column_order if not any(var in n for var in ['cases'])] 
	
	## Verify presence of all data
	if final_results.shape[0] != input_data.shape[0]: quit("ERROR: some data were lost during finalization")	  
	
	## Save
	if not os.path.isdir(os.path.dirname(output_directory)):
		os.makedirs(os.path.dirname(output_directory))
	if not ihme_loc_id: 
		print('Saving sr {} results to {}'.format(sr, output_directory))
		print('		  super region {}'.format(sr))
		final_results[column_order].to_csv(output_directory+ sr + final_output_suffix, index=False)
		for i in sorted(list(final_results['ihme_loc_id'].unique())):
			print('		  {}'.format(i))
			final_results[final_results['ihme_loc_id'] == i][column_order].to_csv(output_directory+ sr + final_output_suffix, index=False) 
	else:
		print('Saving {} results to {}'.format(ihme_loc_id, output_directory))
		final_results[column_order].to_csv(output_directory+ ihme_loc_id + final_output_suffix, index=False) 
   
	return True

################################
## Define function to check results
################################
def verify_results(process, ihme_loc_id_list, data_path, output_directory, gpr_output_suffix, output_suffix, sr, num_draws, modnum, cause, sex, expected_rows, cluster_issues=False):
	## set maximum number of attempts
	max_attempts = 1 if cluster_issues else 6 
	
	## find results for each location. run function after maximum number of attempts
	first = True
	for iso in ihme_loc_id_list:
		attempts = 0
		finished_file = '{}{}{}'.format(output_directory, iso, output_suffix)
		print "Verifying {} results for {}".format(process, iso)
		while not os.path.exists(finished_file):
			sleep(0.01)
			attempts += 1
			if attempts == max_attempts: 
				if process == 'gpr':
					run_GPR('{}{}_st_output.csv'.format(data_path, sr), output_directory, output_suffix, sr, ihme_loc_id=iso, num_draws=num_draws)
				elif process == 'finalize':					  
					successful = finalize_estimates(output_directory, gpr_output_suffix, output_suffix, sr=sr, ihme_loc_id=iso, modnum=modnum, cause=cause, sex=sex)
			if not successful:
				print "Re-running gpr..."
				run_GPR('{}{}_st_output.csv'.format(data_path, sr), output_directory, output_suffix, sr, ihme_loc_id=iso, num_draws=num_draws)
				sleep(4)
				successful = finalize_estimates(output_directory, gpr_output_suffix, output_suffix, sr=sr, ihme_loc_id=iso, modnum=modnum, cause=cause, sex=sex)
			if not successful:
				quit("Error during finalization that could not be corrected by re-running gpr")
			sleep(3)			  
			if not (os.path.exists(finished_file)): 
				quit("ERROR: error in {} for {}".format(process, iso))
			else:
				break
		
		## Verify that files are not missing data due to cluster issues. re-run functions if so.
		append_file = pd.read_csv(finished_file) 
		if append_file.shape[0] < expected_rows:
				run_GPR('{}{}_st_output.csv'.format(data_path, sr), output_directory, output_suffix, sr, ihme_loc_id=iso, num_draws=num_draws)
				finalize_estimates(output_directory, gpr_output_suffix, output_suffix, sr=sr, ihme_loc_id=iso, modnum=modnum, cause=cause, sex=sex)
				append_file = pd.read_csv(finished_file) 
				if append_file.shape[0] < expected_rows:
					quit("ERROR: error in {} for {}. Data are missing after process.".format(process, iso))
				
		## Append results to compilation
		"	  appending {}...".format(iso)
		if first:
			results_data = append_file
			first = False
		else:
			results_data = results_data.append(append_file, ignore_index = True)
		
	## Verify presence of all expected outputs
	test_locations = list(results_data.ihme_loc_id.unique())
	if	len(test_locations) < len(ihme_loc_id_list) or len([i for i in ihme_loc_id_list if i not in test_locations]) > 0:
		problem_locations_input = [i for i in ihme_loc_id_list if i not in test_locations]
		problem_locations_output = [i for i in test_locations if i not in ihme_loc_id_list] 
		quit("ERROR: number of locations in the output file do not match number of locations in the input file after {}. Problem locations are {} {}".format(process, problem_locations_input, problem_locations_output))

	## Save compiled results
	print("Saving {} model output...".format(process))	  
	results_data.to_csv('{}{}{}'.format(output_directory,sr,output_suffix), index=False)

				   
###############################
## Run function if calling directly
################################
if __name__ == '__main__':
   
	## Set defaults and check for arguments
	modnum = sys.argv[1]
	cause = sys.argv[2]
	sex = sys.argv[3]
	sr = sys.argv[4]
	ihme_loc_id = sys.argv[5]
	num_draws = int(sys.argv[6])
	function = sys.argv[7]

	## Set data path
	data_path = '/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr/model_'+modnum+'/'+cause+'/'+sex+'/'
	
	##
	if num_draws:
		output_directory = '/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/06_draws/' + cause + '/' + sex + '/'
		gpr_output_suffix = '_gpr_output_with_draws.csv' 
		final_output_suffix = '_model_output_with_draws.csv'
	else:
		output_directory = data_path
		gpr_output_suffix = '_gpr_output.csv' 
		final_output_suffix = '_model_output.csv'

	## Run requested function
	if function == 'st': run_Spacetime(data_path + sr+'_st_input.csv', data_path+sr+'_st_output.csv')
	elif function == 'gpr': run_GPR(data_path+sr+'_st_output.csv', output_directory, gpr_output_suffix, sr, ihme_loc_id, num_draws)
	elif function == 'finalize': finalize_estimates(output_directory, gpr_output_suffix, final_output_suffix, sr, ihme_loc_id, modnum, cause, sex)
  
## ###
## END
## ###
