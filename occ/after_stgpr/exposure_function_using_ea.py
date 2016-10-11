"""
Exposure function using ea
Mon Apr 18 13:33:32 2016
"""

import sys
import pandas as pd
import platform

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Create local variables
location = sys.argv[1]

data = pd.read_csv('{d}/WORK/05_risk/risks/occ/exposures/intermediate/inter_ea_{l}.csv'.format(d=drive, l=location))
data = data.drop_duplicates(['sex_id', 'year_id', 'me_name', 'age_group_id'])

pop = data[['year_id', 'sex_id', 'age_group_id', 'pop_scaled']]

carcinos = ["arsenic", "acid", "benzene", "beryllium", "cadmium", "chromium", "diesel", "ets", "formaldehyde", "nickel", "pah", "silica", "trichloroethylene"]
output = '/share/scratch/users/strUser/'

turnover = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/turnover.csv'.format(drive))

draws = [col for col in data.columns if 'draw' in col]

#Category groups for exposures (cat1 = High, cat2 = Low, cat3 = None)
cat1 = []
cat2 = []
cats = [cat1, cat2]

for i in range(1000):
    cats[0].append('exp_cat1_{}'.format(i))
    cats[1].append('exp_cat2_{}'.format(i))

#First step of process for each occupational exposure: '% of population in each economic activity' * '% of population economically active'
data[draws] = data[draws].multiply(data['eapep'], axis='index')

#%%Occupational carcinogens: exposure = '% of population economically active'*'% of population in a specific industry'*'% exposed'*'turnover_factor' by duration of exposure & development status

for carcino in carcinos:
    #Copy dataset and add on blank variables for high/low exposures
    temp = data.copy()
    catty = pd.DataFrame(columns = cats[0])
    temp = pd.concat([temp, catty], axis=1)

    #Multiply draws by exposures, then sum across categories
    temp[cats[0]] = temp[draws].multiply(temp[carcino], axis='index')
    temp[cats[0]] = temp[cats[0]].multiply(temp['pop_scaled'],axis='index')
    exposures = temp.groupby(['location_id', 'year_id', 'sex_id', 'region_name'])[cats[0]].sum()
    exposures.reset_index(inplace=True)

    catty = pd.DataFrame(columns = cats[1])
    exposures = pd.concat([exposures, catty], axis=1)

    #Now get total size of workforce in anticipation of applying turnover factors
    exposures = pd.merge(exposures, turnover, on=['year_id', 'sex_id', 'region_name'], how='left')
    exposures = exposures[exposures['location_id']== int(location)]

    #Different high/low exposure values depending on duration of carcinogen & development status. If developed, put .9 in low exposure group.
    if carcino in ["benzene", "formaldehyde"]:
        if temp['developed'].all() == True:
            exposures[cats[0]] = (exposures[cats[0]]*.1).multiply(exposures['ot_short'], axis='index')
            exposures[cats[1]] = (exposures[cats[0]]*.9).multiply(exposures['ot_short'], axis='index')

        else:
            exposures[cats[0]] = (exposures[cats[0]]*.5).multiply(exposures['ot_short'], axis='index')
            exposures[cats[1]] = (exposures[cats[0]]*.5).multiply(exposures['ot_short'], axis='index')
    else:
        if temp['developed'].all() == True:
            exposures[cats[0]] = (exposures[cats[0]]*.1).multiply(exposures['ot_long'], axis='index')
            exposures[cats[1]] = (exposures[cats[0]]*.9).multiply(exposures['ot_long'], axis='index')

        else:
            exposures[cats[0]] = (exposures[cats[0]]*.5).multiply(exposures['ot_long'], axis='index')
            exposures[cats[1]] = (exposures[cats[0]]*.5).multiply(exposures['ot_long'], axis='index')

    #Now weight on age-group specific population estimates
    exposures = pd.merge(exposures, pop, how='left', on=['year_id', 'sex_id', 'age_group_id'])
    exposures[cats[0]] = exposures[cats[0]].divide(exposures['pop_scaled'], axis='index')
    exposures[cats[1]] = exposures[cats[1]].divide(exposures['pop_scaled'], axis='index')

    #Issue with merging so drop duplicates
    exposures.drop_duplicates(['location_id', 'year_id', 'sex_id', 'age_group_id'], inplace=True)

    #Export by location, year, sex, exposure category
    grouper = exposures.groupby(['location_id', 'year_id', 'sex_id'])
    for (location, year, sex), dataset in grouper:
        dataset_high = pd.concat([dataset['age_group_id'], dataset[cats[0]]], axis=1)
        dataset_high.rename(columns=dict(zip(cats[0], draws)), inplace=True)
        dataset_high.to_csv(output+'occ_carcino/occ_carcino_{c}/high/18_{l}_{y}_{s}.csv'.format(c=carcino, l=int(location), y=year, s=sex))

        dataset_low = pd.concat([dataset['age_group_id'], dataset[cats[1]]], axis=1)
        dataset_low.rename(columns=dict(zip(cats[1], draws)), inplace=True)
        dataset_low.to_csv(output+'occ_carcino/occ_carcino_{c}/low/18_{l}_{y}_{s}.csv'.format(c=carcino, l=int(location), y=year, s=sex))

##%%Occupational hearing loss: exposure = '% of population economically active'*'% of population in a specific industry'*'% exposed' by volume of exposure, year & development status
#
##Copy dataset and add on blank variables for high/low exposures
#temp = data.copy()
#catty = pd.DataFrame(columns = cats[0]+cats[1])
#temp = pd.concat([temp, catty], axis=1)
#
##Different high/low exposure values depending on development status, year
#if temp['developed'].all() == False:
#    temp.ix[temp['year_id']<2000, cats[0]] = temp.ix[temp['year_id']<2000, draws].multiply(temp.ix[temp['year_id']<2000, 'hearing_deving_hi_90'], axis='index').values
#    temp.ix[temp['year_id']<2000, cats[1]] = temp.ix[temp['year_id']<2000, draws].multiply(temp.ix[temp['year_id']<2000, 'hearing_deving_low_90'], axis='index').values
#
#    temp.ix[temp['year_id']>=2000, cats[0]] = temp.ix[temp['year_id']>=2000, draws].multiply(temp.ix[temp['year_id']>=2000, 'hearing_deving_hi_00'], axis='index').values
#    temp.ix[temp['year_id']>=2000, cats[1]] = temp.ix[temp['year_id']>=2000, draws].multiply(temp.ix[temp['year_id']>=2000, 'hearing_deving_low_00'], axis='index').values
#
#else:
#    temp[cats[0]] = temp[draws].multiply(temp['hearing_deved_hi'], axis='index')
#    temp[cats[1]] = temp[draws].multiply(temp['hearing_deved_low'], axis='index')
#
##Sum across categories
#exposures = temp.groupby(['location_id', 'year_id', 'sex_id', 'age_group_id'])[cats[0]+cats[1]].sum()
#exposures.reset_index(inplace=True)
#
##Export by location, year, sex, exposure category
#save = exposures.groupby(['location_id', 'year_id', 'sex_id'])
#for (location, year, sex), dataset in save:
#    dataset_high = pd.concat([dataset['age_group_id'], dataset[cats[0]]], axis=1)
#    dataset_high.rename(columns=dict(zip(cats[0], draws)), inplace=True)
#    dataset_high.to_csv(output+'occ_hearing/high/18_{l}_{y}_{s}.csv'.format(l=int(location), y=year, s=sex))
#
#    dataset_low = pd.concat([dataset['age_group_id'], dataset[cats[1]]], axis=1)
#    dataset_low.rename(columns=dict(zip(cats[1], draws)), inplace=True)
#    dataset_low.to_csv(output+'occ_hearing/low/18_{l}_{y}_{s}.csv'.format(l=int(location), y=year, s=sex))
#
##%% Occupational particulates '% of population economically active'*'% of population in a specific industry' by development status and magnitude
#
##Copy dataset and add on blank variables for high/low exposures
#temp = data.copy()
#catty = pd.DataFrame(columns = cats[0]+cats[1])
#temp = pd.concat([temp, catty], axis=1)
#
#    #Different high/low exposure values depending on development status
#if temp['developed'].all() == 0:
#    temp[cats[0]] = temp[draws].multiply(temp['copd_deving_hi'], axis='index')
#    temp[cats[1]] = temp[draws].multiply(temp['copd_deving_low'], axis='index')
#else:
#    temp[cats[0]] = temp[draws].multiply(temp['copd_deved_hi'], axis='index')
#    temp[cats[1]] = temp[draws].multiply(temp['copd_deved_low'], axis='index')
#
##Sum across categories
#exposures = temp.groupby(['location_id', 'year_id', 'sex_id', 'age_group_id'])[cats[0]+cats[1]].sum()
#exposures.reset_index(inplace=True)
#
##Export by location, year, sex, exposure category
#save = exposures.groupby(['location_id', 'year_id', 'sex_id'])
#for (location, year, sex), dataset in save:
#    dataset_high = pd.concat([dataset['age_group_id'], dataset[cats[0]]], axis=1)
#    dataset_high.rename(columns=dict(zip(cats[0], draws)), inplace=True)
#    dataset_high.to_csv(output+'occ_particulates/high/18_{l}_{y}_{s}.csv'.format(l=int(location), y=year, s=sex))
#
#    dataset_low = pd.concat([dataset['age_group_id'], dataset[cats[1]]], axis=1)
#    dataset_low.rename(columns=dict(zip(cats[1], draws)), inplace=True)
#    dataset_low.to_csv(output+'occ_particulates/low/18_{l}_{y}_{s}.csv'.format(l=int(location), y=year, s=sex))
