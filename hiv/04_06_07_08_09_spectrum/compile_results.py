import os, sys, glob

ISO = sys.argv[1]
directory = sys.argv[2]
run_folder = os.path.split(directory)[-1]
if len(sys.argv) > 3:
	stage = sys.argv[3]
	output_dir = '/strPath/' + run_folder + '/draws/' + stage + '/' + ISO + '/'
else:
	stage = ""
	output_dir = '/strPath/' + run_folder + '/draws/'
	print output_dir

variables_file = directory + '/variables.csv'
if len(sys.argv) > 4:
	if sys.argv[4] == 'single_year':
		variables_file = directory + '/variables_SA.csv'

print variables_file

file_list = glob.glob(output_dir + '/' + ISO + '*.csv')

cov_variables_file = directory + '/coverage_vars.csv'

no_ART_list = [f for f in file_list if 'no_ART' in f]

ART_list = [f for f in file_list if f not in no_ART_list and 'ART' in f]

HQ_list = [f for f in file_list if 'HQ' in f]

HI_list = [f for f in file_list if 'HI' in f] 

cat_list = '\" \"'.join(ART_list)
cat_list = '\"' + cat_list + '\"'

out_dir = '/strPath/' + run_folder + '/compiled/'+ stage

if not os.path.isdir(out_dir):
	try:
		os.makedirs(out_dir)
	except:
		pass

outfile = out_dir + '/' + ISO +'_ART_data.csv'

cp_command = 'cp \"' + variables_file + '\" \"' + outfile + '\"'
command = 'find \"' + output_dir + '\" -maxdepth 1 -name \"'+ ISO + '_ART*\" -exec cat {} \; >> \"' + outfile + '\"'

if len(ART_list) != 0: 
	os.system(cp_command)
	os.system(command)

cat_list = '\" \"'.join(no_ART_list)
cat_list = '\"' + cat_list + '\"'

outfile = out_dir + '/' + ISO +'_no_ART_data.csv'
cp_command = 'cp \"' + variables_file + '\" \"' + outfile + '\"'


command = 'find \"' + output_dir + '\" -maxdepth 1 -name \"'+ ISO + '_no_ART*\" -exec cat {} \; >> \"' + outfile + '\"'

if len(no_ART_list) > 0: 
	os.system(cp_command)
	os.system(command)

# ## HI
cat_list = '\" \"'.join(HI_list)
cat_list = '\"' + cat_list + '\"'

outfile = directory + '/results/' + stage + '/' + ISO + '_HI_data.csv'
cp_command = 'cp \"' + variables_file + '\" \"' + outfile + '\"'


command = 'find \"' + output_dir + '\" -maxdepth 1 -name \"'+ ISO + '_HI*\" -exec cat {} \; >> \"' + outfile + '\"'

if len(HI_list) > 0: 
	os.system(cp_command)
	os.system(command)

## HQ
cat_list = '\" \"'.join(HQ_list)
cat_list = '\"' + cat_list + '\"'

outfile = directory + '/results/' + stage + '/' + ISO + '_HQ_data.csv'
cp_command = 'cp \"' + variables_file + '\" \"' + outfile + '\"'

command = 'find \"' + output_dir + '\" -maxdepth 1 -name \"'+ ISO + '_HQ*\" -exec cat {} \; >> \"' + outfile + '\"'

if len(HQ_list) > 0: 
	os.system(cp_command)
	os.system(command)


coverage_list = [f for f in file_list if 'coverage' in f]
cat_list = '\" \"'.join(coverage_list)
cat_list = '\"' + cat_list + '\"'

outfile = out_dir + '/' + ISO + '_coverage.csv'
cp_command = 'cp \"' + cov_variables_file + '\" \"' + outfile + '\"'

command = 'find \"' + output_dir + '\" -maxdepth 1 -name \"'+ ISO + '_coverage*\" -exec cat {} \; >> \"' + outfile + '\"'

if len(coverage_list) > 0: 
	os.system(cp_command)
	os.system(command)
