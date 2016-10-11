"""
Exposure function using injuries, followed by PAF calculation
Fri Jun 10 10:13:31 2016
"""

import sys
import subprocess
import pandas as pd
import platform

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Create local variables, read in primary inputs, set up directories
location = sys.argv[1]

intermediate = pd.read_csv('{d}/WORK/05_risk/risks/occ/exposures/intermediate/inter_inj_{l}.csv'.format(d=drive, l=location))
data = intermediate.drop_duplicates(['sex_id', 'year_id', 'me_name', 'age_group_id'])

ea_share = pd.read_csv('{d}/WORK/05_risk/risks/occ/exposures/intermediate/inter_ea_{l}.csv'.format(d=drive, l=location))
causes = pd.read_csv("{d}/WORK/05_risk/risks/occ/raw/exposures/injury_causes.csv".format(d = drive))
injury_cause_pairs = pd.read_csv("{d}/WORK/05_risk/risks/occ/raw/exposures/injury_cause_pairs.csv".format(d = drive))

output = '/share/scratch/users/strUser/'

draws = [col for col in data.columns if 'draw' in col]

#%%
# Total deaths in an industry = % of population involved in a given industry * % working for a given age/sex group * population size for a given age/sex group / 100,000 * Injury rate per 100,00 for a given industry

data[draws] = data[draws].multiply(data['eapep'], axis='index')
data[draws] = data[draws].multiply(data['pop_scaled'].values/100000, axis='index')

#Modify ea_share a little to match our data. Rename draws and me_names to merge succesfully
ea_share = ea_share[['location_id', 'year_id', 'sex_id', 'age_group_id', 'me_name']+draws]
ind_pct = ['ind_pct' + x for x in ea_share.columns if 'draw' in x]
ea_share.rename(columns=dict(zip(draws, ind_pct)), inplace=True)

new_me_name = ['occ_inj'+x.replace('occ_ea', '') for x in ea_share['me_name'].values]
ea_share['me_name'] = new_me_name

data = pd.merge(data, ea_share, on=['location_id', 'year_id', 'sex_id', 'age_group_id', 'me_name'], how='left')

#Combine % in industry with rate of deaths.
data[draws] = data[draws].multiply(data[ind_pct].values, axis='index')

data = data[['location_id', 'year_id', 'sex_id', 'age_group_id', 'me_name']+draws]

#%%
# Combine with COD results to generate PAFs (# of occupational injuries/# of total injuries) TMREL=0

#Get total deaths from dalynator (measure =1 is deaths, metric = 1 is amounts)

dofile = '/snfs2/HOME/strUser/code/general/get_draws.do'
measure = 1
metric = 1
source = "dalynator"

injury_causes = []

for cause in causes['cause_id'].values:
    cmd = ['stata', '-q', dofile, str(output+'get_draws/{c}_{l}.csv'.format(c = cause, l = location)), str(location), str(cause), str(measure), str(metric), str(source)]
    subprocess.call(cmd)
    injury_causes.append(pd.read_csv(output+'get_draws/{c}_{l}.csv'.format(c = cause, l = location)))

injury_causes = pd.concat(injury_causes, ignore_index=True)

total_unintentional_deaths = injury_causes.groupby(['location_id', 'year_id', 'sex_id', 'age_group_id']).sum()
total_unintentional_deaths.reset_index(inplace=True)

#Rename draws for merge
total_deaths = ['total_deaths_'+x.replace('draw_', '') for x in total_unintentional_deaths[draws].columns]
total_unintentional_deaths.rename(columns= dict(zip(draws, total_deaths)), inplace=True)

#Merge with occupational deaths, then divide occupational deaths by total deaths to get paf for each industry and cause (i.e. PAF = Total # of fatal occupational injuries/ Total # of fatal injuries)
occupational_injuries_paf = pd.merge(total_unintentional_deaths, data, on=['location_id', 'year_id', 'sex_id', 'age_group_id'], how='right')

occupational_injuries_paf[draws] = occupational_injuries_paf[draws].divide(occupational_injuries_paf[total_deaths].values, axis='index')
occupational_injuries_paf = occupational_injuries_paf[['location_id', 'year_id', 'sex_id', 'age_group_id', 'me_name']+draws]

occupational_injuries_paf = pd.merge(occupational_injuries_paf, injury_cause_pairs, on='me_name', how='right')

occ_inj_paf = occupational_injuries_paf.groupby(['location_id', 'year_id', 'sex_id', 'age_group_id', 'cause_id']).sum()
occ_inj_paf.reset_index(inplace=True)

loop = occ_inj_paf.groupby(['location_id', 'year_id', 'sex_id'])

for (location_id, year_id, sex_id), dataset in loop:
    dataset.to_csv(output+'occ_injury/paf_yll_{l}_{y}_{s}.csv'.format(l=location_id, y=year_id, s=sex_id), index=False)
    dataset.to_csv(output+'occ_injury/paf_yld_{l}_{y}_{s}.csv'.format(l=location_id, y=year_id, s=sex_id), index=False)
