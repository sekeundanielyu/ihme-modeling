"""
From exposures, generate inputs needed for PAF calculations
Wed May 25 11:41:53 2016
"""

import pandas as pd
import platform
import os
import sys

if platform.system() == 'Windows':
    drive = 'J:'
    postscale_dir = 'C:/Users//Desktop/'
    pops = "{d}/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/population.dta".format(d=drive)
    loc = 15    
    
else:
    drive = '/home/j'
    postscale_dir = sys.argv[1]
    pops = sys.argv[2]
    loc = sys.argv[3]
    
#From postscale, bring in alc_lpc, as well as prevalences, and bingers.
pops = pd.read_stata(pops)

for file in os.listdir(postscale_dir):
    if file == 'alc_lpc_{l}.dta'.format(l=loc):
        alc_lpc = pd.read_stata(postscale_dir+file)
    elif file == '3363_dismod_output_{l}.dta'.format(l=loc):
        binges = pd.read_stata(postscale_dir+file)
    elif file == '3366_dismod_output_{l}.dta'.format(l=loc):
        binge_drinkers = pd.read_stata(postscale_dir+file)
    elif file == 'prevalences_{l}.dta'.format(l=loc):
        prevalences = pd.read_stata(postscale_dir+file)

prevalences = pd.concat([prevalences, binge_drinkers, binges], ignore_index=True)

#%% Change age_groups to match 

prevalences[''] = 1
prevalences.loc[((prevalences['age_group_id'] >= 12) & (prevalences['age_group_id'] <= 16)), ''] = 2
prevalences.loc[(prevalences['age_group_id'] > 16), ''] = 3
    
#%% Start with transformations to alcohol lpc 

#Calculate total consumption from alc_lpc. First merge with population file, then multiply alc_lpc by population
draws = [draw for draw in alc_lpc.columns if 'alc_lpc_' in draw]
alc_lpc = alc_lpc[['location_id', 'year_id', 'age_group_id', 'sex_id'] + draws]
alc_lpc = pd.merge(alc_lpc, pops, on=['location_id', 'year_id', 'sex_id', 'age_group_id'], how='left')

alc_lpc[draws] = alc_lpc[draws].multiply(alc_lpc['pop_scaled'], axis='index')

#Determine alc lpc for each sex, by year & location 
alc_lpc_sex_split = alc_lpc.groupby(['location_id', 'year_id', 'sex_id'])[draws+['pop_scaled']].sum()
alc_lpc_sex_split[draws] = alc_lpc_sex_split[draws].divide(alc_lpc_sex_split['pop_scaled'], axis='index')
alc_lpc_sex_split.reset_index(inplace=True)

#Find mean and variance of alc_lpc_sex_split
alc_lpc_sex_split['alc_lpc_mean'] = alc_lpc_sex_split[draws].mean(axis='columns')
alc_lpc_sex_split['alc_lpc_variance'] = alc_lpc_sex_split[draws].var(axis='columns')

alc_lpc_sex_split = alc_lpc_sex_split[['location_id', 'year_id', 'sex_id', 'alc_lpc_mean', 'alc_lpc_variance', 'pop_scaled']]

#%% Aggregate and scale prevalences/binge drinkers by age groups

draws = [draw for draw in prevalences.columns if 'draw' in draw]

#Add on population, which is needed for PAF template
print(pops)
print(prevalences)
prevalences = prevalences[['location_id','year_id','sex_id','age_group_id','modelable_entity_id',''] + draws]
prev_w_pop = pd.merge(prevalences, pops, on=['location_id', 'year_id', 'sex_id', 'age_group_id'], how='left')
prev_w_pop[draws] = prev_w_pop[draws].multiply(prev_w_pop['pop_scaled'], axis='index')

#Find total # of people in each sex/age group, then scale to  age groups.
prevalences_jurgen = prev_w_pop.groupby(['location_id', 'year_id', 'sex_id', 'modelable_entity_id', ''])[draws+['pop_scaled']].sum()
prevalences_jurgen[draws] = prevalences_jurgen[draws].divide(prevalences_jurgen['pop_scaled'], axis='index')

prevalences_jurgen.reset_index(inplace=True)

#Create mean, se of draws
prevalences_jurgen['mean'] = prevalences_jurgen[draws].mean(axis='columns')
prevalences_jurgen['se'] = prevalences_jurgen[draws].std(axis='columns')

#Pivot to match PAF template
prevalences_jurgen['modelable_entity_id'] = prevalences_jurgen['modelable_entity_id'].astype(str)

prevalences_jurgen = prevalences_jurgen[['location_id', 'year_id', 'sex_id', 'modelable_entity_id', '', 'mean', 'se', 'pop_scaled']]
prevalences_jurgen = pd.pivot_table(prevalences_jurgen, index=['location_id', 'sex_id', 'year_id', ''], columns='modelable_entity_id').reset_index()

#Get rid of multi-index to change names to match PAF template
prevalences_jurgen.columns = [''.join(col).strip() for col in prevalences_jurgen.columns.values]

#%% Combine with alc_lpc, then rename columns to match template

final = pd.merge(prevalences_jurgen, alc_lpc_sex_split, on=['location_id', 'year_id', 'sex_id'], how='left')

names = {'sex_id':'SEX', '':'AGE_CATEGORY', 'mean3365':'LIFETIME_ABSTAINERS', 'mean3367':'FORMER_DRINKERS', 'mean3364':'DRINKERS', 'pop_scaled3367':'POPULATION', 'alc_lpc_mean':'PCA', 'alc_lpc_variance':'VAR_PCA', 'mean3363':'BINGE_TIMES', 'se3363':'BINGE_TIMES_SE', 'mean3366':'BINGERS', 'se3366':'BINGERS_SE'}
final.rename(columns=names, inplace=True)

final = final[['SEX', 'AGE_CATEGORY', 'location_id', 'year_id', 'BINGE_TIMES', 'BINGE_TIMES_SE', 'BINGERS', 'BINGERS_SE', 'DRINKERS', 'LIFETIME_ABSTAINERS', 'FORMER_DRINKERS', 'PCA', 'VAR_PCA', 'POPULATION']]

#Export by year
export_machine = final.groupby('year_id')
for year, data in export_machine:
    data.to_csv(postscale_dir+'alc_intermediate_{l}_{y}.csv'.format(l=loc, y=year))
    