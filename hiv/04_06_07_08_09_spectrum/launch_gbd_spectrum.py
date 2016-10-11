'''
Launch GBD Spectrum

For each location, this script launches several tasks:
	1. Run stage 1 Spectrum (gbd_spectrum.py, all locations)
	2. Compile stage 1 draws (compile_results.py, all locations)
	3. Compute stage 1 summary data (save_stage_summary_data.do, all locations)
	4. Adjust stage 1 incidence (incidence_adjustment_duration.R, Type 2 locations)
	5. Run stage 2 Spectrum (gbd_spectrum.py, Type 2 locations)
	6. Compile stage 2 draws (compile_results.py, Type 2 locations)
	7. Compute stage 2 summary data (save_stage_summary_data.do, Type 2 locations)
	8. Plot mortality results (graph_summary_deaths_v2.R, all locations)
Then it compiles all of the individual location death graphs.


NOTES

1. Subnational locations (identified with an underscore in the location ID) are launched
after all non-subnational locations because the order is slightly different if we only have
national VR data. For instance, we only have national VR for Moldova, but UNAIDS has subnational
files. We need to know the estimated aggregate from Stage 1 to adjust subnational incidence
for Stage 2.

2. Since we use incidence adjustment ratios from locations with VR to adjust incidnece in
locations *without* VR, the incidence adjustment for locations without VR will only launch
after incidence adjustments in all with-VR locations have finished.
'''
import sys, os, time, csv, re
import numpy as np

# Identify location of code for portability 
code_path = os.path.dirname(os.path.realpath(__file__)) + '/'
sys.path.append(code_path)
import BeersInterpolation as beers

# Flexibily convert array to a particular type
def convert_row(arr, func):
	arr_copy = []
	for i in arr:
		try:
			arr_copy.append(func(i))
		except:
			arr_copy.append(i)
	return arr_copy

directory = sys.argv[1]

# Directory for adjusted incidence and ratios
adj_inc_dir = '160515_echo1'
# Generate adj_inc_dir if necessary
adj_inc_path = 'strPath' + adj_inc_dir
if not os.path.isdir(adj_inc_path + '_adj'):
	os.mkdir(adj_inc_path + '_adj')
if not os.path.isdir(adj_inc_path + '_ratios'):
	os.mkdir(adj_inc_path + '_ratios')

# Alternative coverage directories
# Stage 2 should use percentages, not counts
coverage_dir = 'none'
coverage_dir_s2 = '160120_pct'

config_path = directory + '/config.csv'
with open(config_path, 'r') as f:
	f_reader = csv.reader(f)
	config_data = [row for row in f_reader]
config = {row[0]: int(row[1]) for row in config_data if row[0] != 'prior_adj'}
config['prior_adj'] = [row for row in config_data if row[0] == 'prior_adj'][0][1]

n_jobs = config['jobs']

# Get run name
folder_name = os.path.split(directory)[-1]
error_path = directory + '/errors'

# Generate summary output structure
if not os.path.isdir(directory + '/results/'):
	os.mkdir(directory + '/results/')

if not os.path.isdir(directory + '/results/stage_1'):
	os.mkdir(directory + '/results/stage_1')
if not os.path.isdir(directory + '/results/stage_2'):
	os.mkdir(directory + '/results/stage_2')
if not os.path.isdir(directory + '/results/best'):
	os.mkdir(directory + '/results/best')

# Get list of locations
iso_list = [row[0] for row in beers.openCSV(directory + '/iso_list.csv')[1:]]
iso_list_no_sub = [row[0] for row in beers.openCSV(directory + '/iso_list_no_sub.csv')[1:]]

num_countries = 1

# Handles running counterfactuals
if config['ART'] == 1:
	counter = 'ART'
if config['no_ART'] == 1:
	counter = 'no_ART'

# Identify and read configuration data
prefix = '/home/j/'
type_config_path = '%sstrPath/type_configurations.csv' % prefix

with open(type_config_path, 'r') as f:
	f_reader = csv.reader(f)
	config_data = [row for row in f_reader]

config_data_int = [convert_row(row, int) for row in config_data[1:]]

type_configurations = {}
for t in np.unique([row[0] for row in config_data_int]):
	type_configurations[t] = {}
	for s in np.unique([row[1] for row in config_data_int if row[0] == t]):
		type_configurations[t][s] = {}
		for p in np.unique([row[2] for row in config_data_int if row[0] == t and row[1] == s]):
			type_configurations[t][s][p] = [row[3] for row in config_data_int if row[0] == t and row[1] == s and row[2] == p][0]

# Find subnational locations and create dictionary to 
# store hold job IDs
subnational_aggregation = {}
subnat_list = np.unique([re.sub('_\w+', '', a) for a in iso_list if '_' in a])
for k in subnat_list:
	subnational_aggregation[k] = []

# Generate list of location types
with open('/strPath/country_types.csv', 'r') as f:
	f_reader = csv.reader(f)
	model_type_data = [row for row in f_reader]

model_types = {row[0]: row[1] for row in model_type_data[1:]}

# Pull out no_VR countries
no_VR_countries = [k for k in model_types if model_types[k] == 'CON_no_VR' and k in iso_list]

# Split out subnational and non-subnational locations
sep_iso_list = [a for a in iso_list if ('_' in a)]
first_iso_list = [a for a in iso_list if a not in sep_iso_list]

no_VR_holds = []
graph_compile_holds = []
tmp_seed = 0

# Iterate through non-subnational locations
for ISO in first_iso_list:
	# Number of Stage 1 jobs and runs
	n_jobs = type_configurations[model_types[ISO]][1]['n_jobs']
	n_runs = type_configurations[model_types[ISO]][1]['n_runs']
	stage_1_inc_adj = type_configurations[model_types[ISO]][1]['inc_adj']

	job_names = []
	graph_holds = []
	i = 1
	if num_countries % 4 == 0:
		time.sleep(10)
	
	# Launch Spectrum. Holds on loc_write_adj_i, which no longer exists
	i = 1
	for j in xrange(n_jobs):
		shell_command = "qsub -pe multi_slot 1 -P proj_hiv -l mem_free=2G -hold_jid " + ISO + "_write_adj_" + str(i) + " -N " + ISO + "_spectrum_" + str(i) + " \"" + code_path + 'python_shell.sh' + "\" \"" + code_path + "gbd_spectrum.py\" \"" + ISO + "\" \"" + directory + "\" " + str(i) + ' ' + str(n_runs) + ' ' + str(stage_1_inc_adj) + ' \"stage_1\" \"none\" \"five_year\" \"' + coverage_dir + '\"'
		os.system(shell_command)
		job_names.append(ISO + "_spectrum_"+ str(i))
		i += 1

	# Launch Stage 1 compilation
	job_list = ','.join(job_names)
	compile_qsub = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + job_list + ' -N ' + ISO + '_compile_spectrum \"' + code_path + 'python_shell.sh' + "\" \"" + code_path + 'compile_results.py\" \"' + ISO + "\" \"" + directory + "\" \"stage_1\" \"five_year\""
	os.system(compile_qsub)
	inc_adj_hold = ISO + '_compile_spectrum'

	# Launch Stage 1 summary generation
	summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + inc_adj_hold + ' -N ' + ISO + '_summary_data \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + ISO + " stage_1\""
	os.system(summary_data_cmd)
	graph_holds.append(ISO + '_summary_data')

	if ISO.find('_') != -1:
		base_ISO = ISO.split('_')[0]
		subnational_aggregation[base_ISO].append(ISO + '_compile_spectrum')

	# Adjust incidence if type is correct
	if model_types[ISO] == "CON_VR":
		inc_adj_cmd = 'qsub -pe multi_slot 3 -P proj_hiv -l mem_free=2G -hold_jid ' + inc_adj_hold + ' -N ' + ISO + '_adj_inc \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'incidence_adjustment_duration.R\" \"' + ISO + " " + folder_name + " " + adj_inc_dir + "\""
		os.system(inc_adj_cmd)
		stage_2_hold = ISO + '_adj_inc'
		no_VR_holds.append(ISO + '_adj_inc')

	# Stage 2 configuration
	stage_2_n_jobs = type_configurations[model_types[ISO]][2]['n_jobs']
	stage_2_n_runs = type_configurations[model_types[ISO]][2]['n_runs']
	stage_2_inc_adj = type_configurations[model_types[ISO]][2]['inc_adj']

	# Stage 2 branch of process
	if model_types[ISO] != 'CON_no_VR':
		if stage_2_n_jobs > 0:
			job_names = []
			
			# Launch Stage 2 Spectrum
			i = 1
			for j in xrange(stage_2_n_jobs):
				shell_command = "qsub -pe multi_slot 1 -P proj_hiv -l mem_free=2G -hold_jid " + stage_2_hold + " -N " + ISO + "_spectrum_stage_2_" + str(i) + " \"" + code_path + 'python_shell.sh' + "\" \"" + code_path + "gbd_spectrum.py\" \"" + ISO + "\" \"" + directory + "\" " + str(i) + ' ' + str(stage_2_n_runs) + ' ' + str(stage_2_inc_adj) + ' \"stage_2\" \"' + adj_inc_dir + '_adj\" \"five_year\" \"' + coverage_dir_s2 + '\"'
				os.system(shell_command)
				job_names.append(ISO + "_spectrum_stage_2_"+ str(i))
				i += 1

			# Launch Stage 2 compilation
			job_list = ','.join(job_names)
			compile_qsub = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + job_list + ' -N ' + ISO + '_compile_spectrum_stage_2 \"' + code_path + 'python_shell.sh' + "\" \"" + code_path + 'compile_results.py\" \"' + ISO + "\" \"" + directory + "\" \"stage_2\""
			os.system(compile_qsub)
			filter_hold = ISO + '_compile_spectrum_stage_2'

			# Launch Stage 2 summary generation
			summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + filter_hold + ' -N ' + ISO + '_summary_data_stage_2 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + ISO + " stage_2\""
			os.system(summary_data_cmd)
			graph_holds.append(ISO + '_summary_data_stage_2')

		tmp_seed += 1
		
		# Launch summary graphs
		graph_job_list = ','.join(graph_holds)
		graph_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + graph_job_list + ' -N ' + ISO + '_summary_graphs \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'graph_summary_deaths_v2.R\" \"' + ISO + "\" \"" + folder_name + "\""
		os.system(graph_cmd)

		graph_compile_holds.append(ISO + '_summary_graphs')

# Iterate through subnational locations
for top_ISO in subnat_list:
	subnat_units = [a for a in sep_iso_list if top_ISO in a]
	agg_holds = []
	subnat_graph_holds = {}
	subnat_graph_holds[top_ISO] = []

	# Launch Stage 1
	for ISO in subnat_units:
		subnat_graph_holds[ISO] = []
		n_jobs = type_configurations[model_types[ISO]][1]['n_jobs']
		n_runs = type_configurations[model_types[ISO]][1]['n_runs']
		stage_1_inc_adj = type_configurations[model_types[ISO]][1]['inc_adj']

		job_names = []
		i = 1
		if num_countries % 4 == 0:
			time.sleep(10)
		i = 1
		for j in xrange(n_jobs):
			shell_command = "qsub -pe multi_slot 1 -P proj_hiv -l mem_free=2G -hold_jid " + ISO + "_write_adj_" + str(i) + " -N " + ISO + "_spectrum_" + str(i) + " \"" + code_path + 'python_shell.sh' + "\" \"" + code_path + "gbd_spectrum.py\" \"" + ISO + "\" \"" + directory + "\" " + str(i) + ' ' + str(n_runs) + ' ' + str(stage_1_inc_adj) + ' \"stage_1\" \"none\" \"five_year\" \"' + coverage_dir + '\"'
			os.system(shell_command)
			job_names.append(ISO + "_spectrum_"+ str(i))
			i += 1

		job_list = ','.join(job_names)
		compile_qsub = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + job_list + ' -N ' + ISO + '_compile_spectrum \"' + code_path + 'python_shell.sh' + "\" \"" + code_path + 'compile_results.py\" \"' + ISO + "\" \"" + directory + "\" \"stage_1\" \"five_year\""
		os.system(compile_qsub)
		summary_hold = ISO + '_compile_spectrum'
		agg_holds.append(ISO + '_compile_spectrum')

		summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + summary_hold + ' -N ' + ISO + '_summary_data \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + ISO + " stage_1\""
		os.system(summary_data_cmd)
		subnat_graph_holds[ISO].append(ISO + '_summary_data')

	# Aggregate to national
	agg_job_list = ','.join(agg_holds)
	subnat_agg_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + agg_job_list + ' -N ' + top_ISO + '_aggregate_stage_1 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'aggregate_subnational_data.do\" \"' + top_ISO + " " + folder_name + " stage_1\""
	os.system(subnat_agg_cmd)
	summary_hold = top_ISO + '_aggregate_stage_1'
	if top_ISO == 'MDA':
		inc_adj_hold = summary_hold	

	# Generate *national* summaries
	summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + summary_hold + ' -N ' + top_ISO + '_summary_data \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + top_ISO + " stage_1\""
	os.system(summary_data_cmd)
	subnat_graph_holds[top_ISO].append(top_ISO + '_summary_data')

	# Launch Stage 2 Spectrum
	stage_2_n_jobs = type_configurations[model_types[subnat_units[0]]][2]['n_jobs']
	stage_2_n_runs = type_configurations[model_types[subnat_units[0]]][2]['n_runs']
	stage_2_inc_adj = type_configurations[model_types[subnat_units[0]]][2]['inc_adj']
	if stage_2_n_jobs > 0:
		agg_holds = []
		for ISO in subnat_units:
			if top_ISO != 'MDA':
				inc_adj_hold_list = [ISO + '_spectrum_' + str(i) for i in range(1, n_jobs + 1)]
				inc_adj_hold = ','.join(inc_adj_hold_list)
			inc_adj_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + inc_adj_hold + ' -N ' + ISO + '_adj_inc \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'incidence_adjustment_duration.R\" \"' + ISO + " " + folder_name + " " + adj_inc_dir + "\""
			os.system(inc_adj_cmd)
			stage_2_hold = ISO + '_adj_inc'


			job_names = []
			i = 1
			for j in xrange(stage_2_n_jobs):
				shell_command = "qsub -pe multi_slot 3 -P proj_hiv -l mem_free=2G -hold_jid " + stage_2_hold + " -N " + ISO + "_spectrum_stage_2_" + str(i) + " \"" + code_path + 'python_shell.sh' + "\" \"" + code_path + "gbd_spectrum.py\" \"" + ISO + "\" \"" + directory + "\" " + str(i) + ' ' + str(stage_2_n_runs) + ' ' + str(stage_2_inc_adj) + ' \"stage_2\" \"' + adj_inc_dir + '_adj\" \"five_year\" \"' + coverage_dir_s2 + '\"'
				os.system(shell_command)
				job_names.append(ISO + "_spectrum_stage_2_"+ str(i))
				i += 1

			job_list = ','.join(job_names)
			compile_qsub = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + job_list + ' -N ' + ISO + '_compile_spectrum_stage_2 \"' + code_path + 'python_shell.sh' + "\" \"" + code_path + 'compile_results.py\" \"' + ISO + "\" \"" + directory + "\" \"stage_2\""
			os.system(compile_qsub)
			agg_holds.append(ISO + '_compile_spectrum_stage_2')
			filter_hold = ISO + '_compile_spectrum_stage_2'

			summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + filter_hold + ' -N ' + ISO + '_summary_data_stage_2 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + ISO + " stage_2\""
			os.system(summary_data_cmd)
			subnat_graph_holds[ISO].append(ISO + '_summary_data_stage_2')

			graph_compile_holds.append(ISO + '_summary_graphs')

		# Launch Stage 2 aggregation
		agg_job_list = ','.join(agg_holds)
		subnat_agg_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + agg_job_list + ' -N ' + top_ISO + '_aggregate_stage_2 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'aggregate_subnational_data.do\" \"' + top_ISO + " " + folder_name + " stage_2\""
		os.system(subnat_agg_cmd)
		summary_hold = top_ISO + '_aggregate_stage_2'
		
		# Launch Stage 2 aggregate summaries
		summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + summary_hold + ' -N ' + top_ISO + '_summary_data_stage_2 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + top_ISO + " stage_2\""
		os.system(summary_data_cmd)
		filter_hold = top_ISO + '_summary_data_stage_2'
		subnat_graph_holds[top_ISO].append(top_ISO + '_summary_data_stage_2')

	# Launch subnational summary graphing
	for ISO in subnat_units:			
		graph_job_list = ','.join(subnat_graph_holds[ISO])
		graph_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + graph_job_list + ' -N ' + ISO + '_summary_graphs \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'graph_summary_deaths_v2.R\" \"' + ISO + "\" \"" + folder_name + "\""
		os.system(graph_cmd)


	# Launch national summary graphing
	graph_job_list = ','.join(subnat_graph_holds[top_ISO])
	graph_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + graph_job_list + ' -N ' + top_ISO + '_summary_graphs \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'graph_summary_deaths_v2.R\" \"' + top_ISO + "\" \"" + folder_name + "\""
	os.system(graph_cmd)

	graph_compile_holds.append(top_ISO + '_summary_graphs')

# Iterate through no_VR countries (for Stage 2)
for ISO in no_VR_countries:
	# Launch no_VR incidence adjustment (uses previously computed ratios)
	no_VR_hold_list = ','.join(no_VR_holds)
	inc_adj_cmd = 'qsub -pe multi_slot 3 -P proj_hiv -l mem_free=2G -hold_jid ' + no_VR_hold_list + ' -N ' + ISO + '_adj_inc \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'adjust_incidence_parallel_no_VR.do\" \"' + ISO + " " + adj_inc_dir + " " + folder_name + " " + code_path+ "\""
	os.system(inc_adj_cmd)
	stage_2_hold = ISO + '_adj_inc'


	stage_2_n_jobs = type_configurations[model_types[ISO]][2]['n_jobs']
	stage_2_n_runs = type_configurations[model_types[ISO]][2]['n_runs']
	stage_2_inc_adj = type_configurations[model_types[ISO]][2]['inc_adj']

	# Launch Stage 2 Spectrum
	if stage_2_n_jobs > 0:
		job_names = []
		i = 1
		for j in xrange(stage_2_n_jobs):
			shell_command = "qsub -pe multi_slot 3 -P proj_hiv -l mem_free=2G -hold_jid " + stage_2_hold + " -N " + ISO + "_spectrum_stage_2_" + str(i) + " \"" + code_path + 'python_shell.sh' + "\" \"" + code_path + "gbd_spectrum.py\" \"" + ISO + "\" \"" + directory + "\" " + str(i) + ' ' + str(stage_2_n_runs) + ' ' + str(stage_2_inc_adj) + ' \"stage_2\" \"' + adj_inc_dir + '_adj\" \"five_year\" \"' + coverage_dir_s2 + '\"'
			os.system(shell_command)
			job_names.append(ISO + "_spectrum_stage_2_"+ str(i))
			i += 1

		job_list = ','.join(job_names)
		compile_qsub = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + job_list + ' -N ' + ISO + '_compile_spectrum_stage_2 \"' + code_path + 'python_shell.sh' + "\" \"" + code_path + 'compile_results.py\" \"' + ISO + "\" \"" + directory + "\" \"stage_2\""
		os.system(compile_qsub)
		filter_hold = ISO + '_compile_spectrum_stage_2'

		summary_data_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + filter_hold + ' -N ' + ISO + '_summary_data_stage_2 \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'save_stage_summary_data.do\" \"' + folder_name + " " + ISO + " stage_2\""
		os.system(summary_data_cmd)
		graph_holds.append(ISO + '_summary_data_stage_2')
	tmp_seed += 1
	# Launch summary graphs
	graph_job_list = ','.join(graph_holds)
	graph_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + graph_job_list + ' -N ' + ISO + '_summary_graphs \"' + code_path + 'Rscript_shell.sh\" \"' + code_path + 'graph_summary_deaths_v2.R\" \"' + ISO + "\" \"" + folder_name + "\""
	os.system(graph_cmd)

	graph_compile_holds.append(ISO + '_summary_graphs')

# Launch summary graph compilation (launches after all other graphing jobs have finished)
graph_compile_job_list = ','.join(graph_compile_holds)
compile_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + graph_compile_job_list + ' -N spectrum_compile_graphs \"' + code_path + 'stata_shell.sh\" \"' + code_path + 'compile_summary_death_graphs.do\" \"' + folder_name + "\""
os.system(compile_cmd)

# Lauch draw removal (after all result compilation jobs have finished)
# Deletes "draws" folder since it contains the same information as the "compiled" folder
remove_draws_job_list = ','.join(graph_compile_holds)
remove_draws_cmd = 'qsub -P proj_hiv -l mem_free=2G -hold_jid ' + remove_draws_job_list + ' -N spectrum_remove_draw_dir \"' + code_path + 'python_shell.sh\" \"' + code_path + 'remove_draws.py\" \"' + folder_name + "\""
os.system(remove_draws_cmd)
