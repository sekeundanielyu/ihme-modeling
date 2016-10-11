################################################################################
## Description: Submits python ST-GPR jobs to cluster
################################################################################

## Libraries
import sys
import os
from subprocess import call
from platform import system
import pandas as pd
from time import sleep

## Set cluster issues to True to prevent submission of jobs and run functions in sequence
cluster_issues = False

## Determine model number
modnum = sys.argv[1]

## Detect operating system and set cancer folder
root = "/home/j" if system() == 'Linux' else "J:"
cancer_folder = root+'/WORK/07_registry/cancer'

## Set number of draws 
num_draws = 0

## set working directory
wkdir = cancer_folder + '/03_models/01_mi_ratio/01_code'
os.chdir(wkdir)

## Set script os.path
script_path = wkdir + '/03_st_gpr/spacetimeGPR/spacetime_gpr.py'
shell_path = cancer_folder + '/00_common/code/py_shell.sh'
output_extension = '_model_output.csv'

## get information from model control
model_control = pd.read_csv(cancer_folder + '/03_models/01_mi_ratio/01_code/_launch/model_control.csv')

## set output_directory
output_directory = "/ihme/gbd/WORK/07_registry/cancer/03_models/01_mi_ratio/03_st_gpr/model_" + modnum
possible_causes = sorted(os.listdir(output_directory))
try: possible_causes.remove('compiled_model_outputs.csv')
except: pass

## Load superregions list. Set super region 64 (USA and other high income) to the first iteration since these data are used for all other models
super_regions = pd.read_csv(cancer_folder + '/00_common/data/modeled_locations.csv')[['super_region_id']]
sr_input = pd.unique(super_regions.loc[pd.notnull(super_regions.super_region_id), 'super_region_id']).astype(int)
sr_list = [64, 4] + [x for x in sr_input if x not in [64, 4]]

## Loop through models for each super region
for sr in sr_list:
    sr = str(sr)
    print(sr)
    
    for cause in possible_causes:
        print(cause)
        possible_sexes = os.listdir(output_directory + '/'+ cause)
        for sex in possible_sexes: 
                
            ## Submit
            qsub = '/usr/local/bin/SGE/bin/lx-amd64/qsub -P proj_cancer_prep -cwd -pe multi_slot 5 -l mem_free=10G'
            prefix = 'sg{}'.format(modnum)            
            jname = "_".join(['-N ', prefix, cause[4:], sr, sex])
            shell = shell_path + ' ' + script_path
            sub = " ".join([qsub, jname, shell, modnum, cause, sex, sr, str(num_draws), str(int(cluster_issues))])
            call(sub.split())
            sleep(30)
            
    ## Pause between major super regions
    if sr in ['64', '4']:
        sleep(90)
      
for cause in possible_causes:
  possible_sexes = os.listdir(output_directory + '/'+ cause)
  for sex in possible_sexes:
      for sr in sr_list:
        attempts = 1
        sr = str(sr)
        finished_file = output_directory + "/" + cause + "/"+ sex+ "/"+ sr+ output_extension
        while not os.path.isfile(finished_file):
            print("checking again for {}".format(finished_file))
            sleep(60)
            attempts += 1
            if attempts > 300: quit("ERROR: could not find all outputs in the time allowed")
        if (os.path.isfile(finished_file)): next
         
print "All gpr outputs found."


