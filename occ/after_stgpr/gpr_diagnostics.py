"""
Visualization tool
Mon Jun 13 14:44:55 2016
"""
import pandas as pd
import os
import platform
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Set directories and options
debug = True

if debug == True:
    path = "C:/Users/strUser/Desktop/debug/"
    location_checks = pd.read_csv('H:/location_checks.csv')
    grab = [81]
    versions= ['debug']

else:
    path = "/share/gbd/WORK/05_risk/02_models/02_results/drugs_alcohol/paf/output/"
    location_checks = pd.read_csv('/snfs2/HOME/strUser/location_checks.csv')
    grab = list(location_checks.location_id.unique())
    versions = ['3', '4']

merge_machine = []
compare = {}
for version in versions:
    for file in os.listdir(path+version):
        file_name = file.split('_')
        mort = file_name[1]
        location = int(file_name[2])
        year = int(file_name[3])
        sex = int(file_name[4].replace('.csv', ''))

        if location in grab:
            data = pd.read_csv(path+version+'/'+file)
            data['mort'] = mort
            data['location_id'] = location
            data['year_id'] = year
            data['sex_id'] = sex

            merge_machine.append(data)

    compare[version] = pd.concat(merge_machine, ignore_index=True)

if debug == True:
    df_debug = compare['debug']
    draws = [col for col in df_debug.columns if 'draw' in col]

    df_debug['mean'] = df_debug[draws].mean(axis='columns')
    df_debug['min'] = df_debug[draws].min(axis='columns')
    df_debug['max'] = df_debug[draws].max(axis='columns')

    df_debug = df_debug[['mort', 'cause_id', 'cause_name', 'location_id', 'year_id', 'sex_id', 'age_group_id', 'mean', 'min', 'max']]

else:
    for version in versions:
        draws = [col for col in compare[version].columns if 'draw' in col]

        if int(version) < int(versions[1]):
            name = 'old'
        else:
            name = 'new'

        compare[version]['mean_{}'.format(name)] = compare[version][draws].mean(axis='columns')
        compare[version]['min_{}'.format(name)] = compare[version][draws].min(axis='columns')
        compare[version]['max_{}'.format(name)] = compare[version][draws].max(axis='columns')

    pafs = pd.merge(compare[0], compare[1], on=['mort', 'location_id', 'cause_id', 'cause_name', 'year_id', 'sex_id', 'age_group_id'], how='outer')

#%%
#Append each model PDF with each location produced.

#def append_pdf(location):


