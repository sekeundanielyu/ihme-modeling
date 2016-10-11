"""
Description: Calls ST and GPR for one cancer site/sex/super-region combination then finalizes the data
 
"""
################################
## 
################################
## Import Libraries
import pandas as pd
from platform import system
import sys, os
from time import sleep
from subprocess import call

## Detect operating system
root = "/home/j/" if system() == 'Linux' else "J:/"
os.chdir(root+'WORK/07_registry/cancer/03_models/01_mi_ratio/01_code/03_st_gpr/spacetimeGPR')
import run_st_gpr.call_processes as sg

################################
## Set paths and preferences
################################
modnum = sys.argv[1]
cause = sys.argv[2]
sex = sys.argv[3]
sr = sys.argv[4]
num_draws = int(sys.argv[5])   
cluster_issues = bool(int(sys.argv[6]))
re_run_spacetime = True
  
## Data paths
model = 'm_{}'.format(modnum)
data_path = '/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr/model_'+modnum+'/'+cause+'/'+sex+'/'
cancer_folder = root+'/WORK/07_registry/cancer'
script_path = cancer_folder + '/03_models/01_mi_ratio/01_code/03_st_gpr/spacetimeGPR/run_st_gpr/call_processes.py'
shell_path = cancer_folder + '/00_common/code/py_shell.sh'
qsub = '/usr/local/bin/SGE/bin/lx-amd64/qsub -P proj_cancer_prep -cwd -pe multi_slot 3 -l mem_free=6G -N'
   
#set conditional file locations
st_output = '{}{}_st_output.csv'.format(data_path, sr)
if num_draws > 0:
    output_directory = '/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/06_draws/' + cause + '/' + sex + '/'
    gpr_output_suffix = '_gpr_output_with_draws.csv'
    final_output_suffix = '_model_output_with_draws.csv'
else:
    output_directory = data_path
    gpr_output_suffix = '_gpr_output.csv'
    final_output_suffix = '_model_output.csv'

## Ensure presence of output directory
if not os.path.exists(output_directory): os.makedirs(output_directory) 

################################
## Smooth data with spacetime (all countries)
################################
if not os.path.exists(st_output) or re_run_spacetime:
    sg.run_Spacetime(linear_results = '{}{}_st_input.csv'.format(data_path, sr), st_results = st_output)

################################
## Create List of Locations
################################
## open the st_output
st_output = pd.read_csv(data_path + sr + '_st_output.csv')
expected_rows = st_output[['year', 'age', 'sex']].drop_duplicates().shape[0]

## Adjust location variable
from datetime import date
if date.today().year == 2016 and 'iso3' in st_output.columns.values: st_output.rename(columns={'iso3':'ihme_loc_id'}, inplace=True)     

## create list of locations
ihme_loc_id_list = list(st_output['ihme_loc_id'].unique())

## Set list to run and check USA models first
if sr == '64':
    ihme_loc_id_list.remove('USA')
    ihme_loc_id_list = ['USA'] + ihme_loc_id_list
    
################################
## Adjust model against residuals with GPR, then finalize
################################
## Run each process and verify results
for process in ['gpr', 'finalize']:
    ## Remove previous compilations
    if process == 'gpr' and os.path.exists(output_directory + sr + gpr_output_suffix): os.remove(output_directory + sr + gpr_output_suffix)
    if process == 'finalize' and os.path.exists(output_directory + sr + final_output_suffix): os.remove(output_directory + sr + final_output_suffix)    
    
    ## Wait for gpr outputs from USA before finalizing super-regions that are not 'High Income'       
    if process == 'finalize' and sr != '64':
        us_data_file = output_directory + '64' + gpr_output_suffix if not num_draws else output_directory + 'USA' + gpr_output_suffix
        if not os.path.exists(us_data_file):
            print("  waiting for usa gpr output...")
            while not os.path.exists(us_data_file): sleep(5)
    
    ## Submit process
    for iso in ihme_loc_id_list:
        jname = "_".join([process[:3], cause[4:7], sex[:1], sr, iso, model])
        sub = " ".join([qsub, jname, shell_path, script_path, modnum, cause, sex, str(sr), iso, str(num_draws), process])
        if not cluster_issues: call(sub.split())  
        
    ## check for results
    if process == 'gpr':            
        sg.verify_results(process, ihme_loc_id_list, data_path, output_directory, gpr_output_suffix, gpr_output_suffix, sr, num_draws, modnum, cause, sex, expected_rows, cluster_issues)
    if process == 'finalize':            
        sg.verify_results(process, ihme_loc_id_list, data_path, output_directory, gpr_output_suffix, final_output_suffix, sr, num_draws, modnum, cause, sex, expected_rows, cluster_issues)

## ################################################################
## END
## ################################################################
