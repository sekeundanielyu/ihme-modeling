#%%
"""
Scale economic activity and occupations results to 1
Tue Apr  5 10:12:10 2016
"""

import pandas as pd
import os
import platform
import logging as log

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#File locations and global variables

gpr_results = r"{d}/WORK/05_risk/risks/occ/gpr_output/gpr_results/".format(d=drive)
temp = '/ihme/scratch/users//'

draws = []
for i in range(1000):
    draws.append('draw_{}'.format(i))

log.basicConfig(filename=temp+'log/scale_main.txt', level=log.DEBUG, format='%(asctime)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S')

#%%
# 1. Import all datasets, sort by type, category, and gender.

def import_datasets(group):
    merge_machine = []

    for files in os.listdir(gpr_results):
        if files.lower().endswith('.dta'):
            if group in files.lower():
                if '\r' in files:
                    files = files.replace('\r','')
                #Read in sex_id
                text = files.split(group)
                text = text[1].rstrip('.dta')
                text = text.split('_')
                gender = text[-1]

                data = pd.read_stata(gpr_results+files)

                #Change sex_id (odd # models are female for occ_ea, odd # models are male for occ_occ)
                if group == 'occ_ea_':
                    if int(gender)%2 == 0:
                        data['sex_id'] = 1
                    else:
                        data['sex_id'] = 2
                else:
                    if int(gender)%2 == 0:
                        data['sex_id'] = 2
                    else:
                        data['sex_id'] = 1

                data['location_id'] = data['location_id'].astype(int)

                data.drop(['index', 'Unnamed__0'], axis=1, inplace=True)
                merge_machine.append(data)

    return(merge_machine)

#ea = pd.concat(import_datasets('occ_ea_'))
#occ = pd.concat(import_datasets('occ_occ_'))
inj = pd.concat(import_datasets('occ_inj_'))

#%%
# 2. Scale categories and export

job_list = []
def scale_data(grouping, dataset):
    '''Submit jobs on cluster to scale locations by category type'''

    for location in dataset.location_id.unique():

        #For each location, make a job on the cluster, passing to the shell the location data and grouping type
        location = location.astype(int)
        job_name = 'occ_{t}_scaling_{l}'.format(t=grouping, l=location)
        os.system('qsub -P proj_custom_models -l mem_free=2G -pe multi_slot 1 -N {j} -o /snfs2/HOME/ -e /snfs2/HOME/ /snfs2/HOME//code/shells/python_shell.sh /snfs2/HOME//code/occ/2a_scaling_function.py {l} {g}'.format(j=job_name, l=location, g=grouping))
        job_list.append(job_name)

#Store compiled categories as HDF on cluster tmp
#ea.to_hdf('/ihme/scratch/users/strUser/ea.hdf'.format(drive), 'data', mode='w', format='table', data_columns=['location_id'])
#occ.to_hdf('/ihme/scratch/users/strUser/occ.hdf'.format(drive), 'data', mode='w', format='table', data_columns=['location_id'])
#inj.to_hdf('/ihme/scratch/users/strUser/inj.hdf', 'data', mode='w', format='table', data_columns=['location_id'])

log.debug('HDF files have been made!')

#For each category grouping, parallelize jobs on cluster
#scale_data('ea', ea)
#scale_data('occ', occ)
scale_data('inj', inj)

#Hold this job until all scaling jobs have been completed; this launches the code to generate exposures
log.debug('Submitted jobs, now waiting to generate exposures')

job_list = ','.join(job_list)
#os.system('qsub -P proj_custom_models -l mem_free=2G -h {j} -N generate_exposures /snfs2/HOME/strUser/code/shells/python_generate_exposures.sh'.format(j=job_list))

