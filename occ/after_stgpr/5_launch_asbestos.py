"""
Launch asbestos exposures
Thu Aug 18 15:44:21 2016
"""

import pandas as pd
import platform
import os

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Set options
get_dataset = False
debugger = True

# AIR = (C-N)/(S-N*)
# where
# C = Mesothelioma cancer mortality rate in the general population
# N = Mesothelioma mortality rate among those never-exposed to asbestos in general population
# S = Mesothelioma mortality rate of highly exposed group in working population
# N* = Mesothelioma mortality rate of never-exposed to asbestos in working population

template = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/template.csv'.format(drive), encoding='latin-1')

if get_dataset == True:

    #Read in inputs, based on Goodman, and Lin et al.
    N = pd.read_stata('{}/WORK/05_risk/risks/occ_carcino_asbestos/impact_ratio_n.dta'.format(drive))
    S = pd.read_stata('{}/WORK/05_risk/risks/occ_carcino_asbestos/impact_ratio_s.dta'.format(drive))

    air_inputs = pd.merge(N, S, on=['risk', 'year', 'whereami_id', 'sex', 'age'], how='outer')
    air_inputs.rename(columns={'sex':'sex_id', 'age':'age_group_id'}, inplace=True)

    #Convert ages to age_group_ids, remove extraneous columns
    air_inputs['age_group_id'] = ((air_inputs['age_group_id'])/5)+5

    air_inputs.drop(['risk', 'whereami_id', 'year'], axis=1, inplace=True)

    air_inputs.to_csv('/share/scratch/users//air_inputs.csv', index=False)

#Launch jobs for each location
for location in list(template['location_id'].unique()):

     if debugger == True:
         debug = " -o /share/temp/sgeoutput//output -e /share/temp/sgeoutput//errors "
     else:
         debug = ""

     os.system('qsub -P proj_custom_models -l mem_free=8G -pe multi_slot 4 -N air_exp_{l} {d} /snfs2/HOME/strUser/code/shells/stata_shell.sh /snfs2/HOME/strUser/code/occ/exposure_function_using_air.do {l}'.format(d=debug, l=location))

