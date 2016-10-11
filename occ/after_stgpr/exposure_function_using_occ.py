"""
Generate exposures requiring occupations
Tue May  3 10:32:31 2016
"""

import os
import sys
import pandas as pd
import platform 

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'
    
#Read in arguments and data
location = sys.argv[1]

data = pd.read_csv('{d}/WORK/05_risk/risks/occ/exposures/intermediate/inter_occ_{l}.csv'.format(d=drive, l=location))

ea_split = pd.read_csv('{d}/WORK/05_risk/risks/occ/exposures/intermediate/inter_ea_{l}.csv'.format(d=drive, l=location))

output = '/ihme/scratch/users/strUser/'

draws = [col for col in data.columns if 'draw' in col]
    
#First step of process for each occupational exposure: '% of population in each economic activity' * '% of population economically active'
data[draws] = data[draws].multiply(data['eapep'], axis='index')

#%% Occupational back pain

grouper = data.groupby('me_name')
for me_name, group in grouper:
    save = group.groupby(['location_id', 'year_id', 'sex_id'])
    for (location, year, sex), dataset in save:
        os.makedirs(output+'occ_backpain/{m}'.format(m=me_name), exist_ok=True)
        dataset.to_csv(output+'occ_backpain/{m}/18_{l}_{y}_{s}.csv'.format(m=me_name, l=int(location), y=year, s=sex))

#%% Occupational exposure to asthmagens
# Need to transform categories to match relative risks. Start with the occupations as a baseline

#We split the occupations by the economic activity production/transport
transport_split = data.loc[(data['me_name'] == 'occ_occ_production_transport_laborers'), draws].reset_index(drop=True)

frames = []
grouper = ea_split.groupby('me_name')
for me_name, group in grouper:
    group = group.reset_index(drop=True)
    group.loc[:, draws] = group.loc[:, draws].multiply(transport_split.values, axis='index')
    frames.append(group)

transport = pd.concat(frames)

categories = {}

#Confusing categories due to set up of RR. Basically, each category = some combination of occupations and adding the % transport occupation*% involved in other economic activites or occupations. 
#See lines 159-181 in this file: J:\WORK\05_risk\risks\occ\2013 work\01_exp\02_nonlit\01_code\01_8_occ_exp_prep_asthmagens 

categories['admin'] = data.loc[(data['me_name'] == 'occ_occ_clerical'), draws] + data.loc[(data['me_name'] == 'occ_occ_administrative_managerial'), draws].values
categories['technical'] = data.loc[(data['me_name'] == 'occ_occ_professional_technical'), draws]
categories['sales'] = data.loc[(data['me_name'] == 'occ_occ_sales'), draws] + data.loc[(data['me_name'] == 'occ_occ_sales'), draws].multiply(data.loc[(data['me_name'] == 'occ_occ_production_transport_laborers'), draws].values, axis='index')
categories['agriculture'] = data.loc[(data['me_name'] == 'occ_occ_agriculture'), draws] + transport.loc[(transport['me_name'] == 'occ_ea_agriculture'), draws].values
categories['mining'] = transport.loc[(transport['me_name'] == 'occ_ea_mining'), draws]
categories['transport'] = transport.loc[(transport['me_name'] == 'occ_ea_transport_communication'), draws]
categories['manufacturing'] = transport.loc[(transport['me_name'] == 'occ_ea_manufacturing'), draws]
categories['services'] = data.loc[(data['me_name'] == 'occ_occ_sales'), draws] + data.loc[(data['me_name'] == 'occ_occ_sales'), draws].multiply(data.loc[(data['me_name'] == 'occ_occ_production_transport_laborers'), draws].values, axis='index')

#Use a template for save_results to make a new dataset from amalgamated categories.
frames = []
export_machine = data[['location_id', 'year_id', 'age_group_id', 'sex_id']].drop_duplicates().reset_index(drop=True)
for me_name, dataset in categories.items():
    dataset = dataset.reset_index(drop=True)
    dataset = pd.concat([dataset, export_machine], axis=1)
    dataset['me_name'] = me_name
    frames.append(dataset)
    
final = pd.concat(frames, ignore_index=True)
    
grouper = final.groupby('me_name')
for me_name, group in grouper:
    save = group.groupby(['location_id', 'year_id', 'sex_id'])
    for (location, year, sex), dataset in save:
        os.makedirs(output+'occ_asthmagens/{m}'.format(m=me_name), exist_ok=True)
        dataset.to_csv(output+'occ_asthmagens/{m}/18_{l}_{y}_{s}.csv'.format(m=me_name, l=int(location), y=year, s=sex))
        