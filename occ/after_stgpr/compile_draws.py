"""
Aggregate draws on cluster
Wed Apr 27 16:10:19 2016
"""

import sys
import os

#Set filepaths and get arguments
file_path = '/ihme/covariates/ubcov/04_model/'

me_name = sys.argv[1]
data_id = sys.argv[2]
model_id = sys.argv[3]

path = file_path+'{m}/_models/{v}/{d}/draws'.format(m=me_name, v=data_id, d=model_id)
locations = []

#Find out how many locations we have
for file in os.listdir(path):
    text = file.split('_')
    locations.append(text[1])

locations = set(locations)

#%%
#Submit jobs and wait until they finish
names = []

for location in locations:
    names.append('compile_draws_{m}_{d}_{l}'.format(m=me_name, d=data_id, l=location))
    os.system('qsub -P proj_custom_models -l mem_free=4G -pe multi_slot 2 -N compile_draws_{m}_{d}_{l} /snfs2/HOME/strUser/code/shells/python_shell.sh /snfs2/HOME/strUser/code/occ/1a_compile_draws_by_location.py {l} {p} {m}'.format(l=location, p=path, m=me_name, d=data_id))

names = ','.join(names)
os.system('qsub -P proj_custom_models -l mem_free=4G -pe multi_slot 2 -hold_jid {n} -N compiler /snfs2/HOME/strUser/code/shells/python_shell.sh /snfs2/HOME/strUser/code/occ/1b_compiler.py {m} {v}'.format(n=names, m=me_name, v=data_id))
