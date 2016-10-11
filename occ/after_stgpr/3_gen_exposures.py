"""
Take scaled gpr_results and combine with economically active population to generate exposures
Tue Apr 12 11:04:27 2016
"""

import pandas as pd
import platform
import os

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Set local variables and get datasets
    #Set up some options
    #Choose which set of models to run ('ea', 'occ' or 'inj')
estimates = ['ea']

create_datasets = False

    #Economically active population
eapep = pd.read_stata('{}/Project/GBD/RISK_FACTORS/Data/occupational_risks/Data/Raw/Master FINAL - EAPEP.dta'.format(drive))
eapep = eapep[['iso3', 'year', 'age_group', 'MPR', 'FPR']]

    #Covariates to add onto eapep
covariates = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/covariates_for_eapep.csv'.format(drive))

    #Location of scaled proportion of workers in each economic activity, occupation, injury groups
scaled = '{}/WORK/05_risk/risks/occ/gpr_output/gpr_scaled_results/'.format(drive)

    #Location for merged intermediate datasets for parallelizing on cluster
inter = '{}/WORK/05_risk/risks/occ/exposures/intermediate/'.format(drive)

   #Template for GPR
template = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/template.csv'.format(drive), encoding = "ISO-8859-1")

#%%Read in exposures and rename to match gpr datasets
exposure = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/exposures.csv'.format(drive))
exposure = exposure[1:]

    #Rename exposure category groups to match gpr category groups
exposure_categories = list(exposure['group'].unique())
rename_categories = ['occ_ea_agriculture', 'occ_ea_mining', 'occ_ea_manufacturing', 'occ_ea_electricity_gas_water', 'occ_ea_construction', 'occ_ea_trade', 'occ_ea_transport_communication', 'occ_ea_business_services', 'occ_ea_social_services']
change = dict(zip(exposure_categories, rename_categories))
exposure.set_index('group', inplace=True)
exposure.rename(index=change, inplace=True)

    #Change data to float type
exposure[list(exposure.columns)] = exposure[list(exposure.columns)].astype(float)

   #Add back in the categories
exposure.reset_index(inplace=True)
exposure.rename(columns={'group':'me_name'}, inplace=True)

#%%
## Clean economically active population estimates to meet GBD requirements. Prep to run through STGPR.
## Only needs to be run once, then commented out for subsequent runs.

##Rename columns to match GBD standards
#eapep.rename(columns={'iso3':'ihme_loc_id', 'year':'year_id', 'age_group':'age_group_id'}, inplace=True)
#eapep = eapep[eapep['year_id'] <=2015]
#
##Concat male and female with sex_ids
#male = eapep[['ihme_loc_id', 'year_id', 'age_group_id', 'MPR']]
#male['sex_id'] = 1
#male.rename(columns={'MPR':'data'}, inplace=True)
#
#female = eapep[['ihme_loc_id', 'year_id', 'age_group_id', 'FPR']]
#female['sex_id'] = 2
#female.rename(columns={'FPR':'data'}, inplace=True)
#
#econ = pd.concat([female, male])
#
##Replace with GBD age groups (only want ages +15)
#ages = list(econ['age_group_id'].unique())
#ages = ages[:-2]
#
#gbd_ages = list(template['age_group_id'].unique())
#gbd_ages = gbd_ages[3:-3]
#
#econ['age_group_id'].replace(to_replace=ages, value=gbd_ages, inplace=True)
#econ = econ[(econ['age_group_id'] != 'TOTAL (0+)') & (econ['age_group_id'] != 'TOTAL 15+')]
#
##Add three rows for age groups above 65+, using 65+ estimates for new observations
#for i in range(2):
#    append = econ[['ihme_loc_id', 'year_id', 'sex_id']]
#    append.drop_duplicates(inplace=True)
#    append['age_group_id'] = 19+i
#    econ = econ.append(append)
#
#econ.sort(['ihme_loc_id', 'year_id', 'sex_id', 'age_group_id'], inplace=True)
#
##Merge onto template for STGPR purposes. Add on some variables
#pre_gpr = pd.merge(econ, template, how='right', on=['ihme_loc_id', 'year_id', 'sex_id', 'age_group_id'])
#pre_gpr = pd.merge(pre_gpr, covariates, how='inner', on=['location_id', 'year_id', 'sex_id', 'age_group_id'])
#
##Convert data to percentage
#pre_gpr['data'] /= 100
#
#pre_gpr['variance'] = np.nan
#pre_gpr['standard_deviation'] = np.nan
#pre_gpr['nid'] = np.nan
#pre_gpr['me_name'] = 'eapep'
#pre_gpr['sample_size'] = np.nan
#
#pre_gpr.to_csv(r'J:\WORK\05_risk\risks\occ\raw\eapep\eapep.csv')

#%%
# Import eapep gpr results and merge with scaled ea/occ proportion results for each country.

#Only keep needed age groups and years, rename some columns
eapep_gpr = pd.read_csv(r'{}/WORK/05_risk/risks/occ/gpr_output/gpr_results/eapep_gpr.csv'.format(drive))
eapep_gpr = eapep_gpr[(eapep_gpr['age_group_id'] >= 8) & (eapep_gpr['age_group_id'] <=21)]
eapep_gpr = eapep_gpr[(eapep_gpr['year_id'] == 1990) | (eapep_gpr['year_id'] == 1995) | (eapep_gpr['year_id'] == 2000) | (eapep_gpr['year_id'] == 2005) | (eapep_gpr['year_id'] == 2010) | (eapep_gpr['year_id'] == 2015)]
eapep_gpr.rename(columns={'gpr_mean':'eapep'}, inplace=True)
eapep_gpr = eapep_gpr[['year_id', 'location_id', 'sex_id', 'age_group_id', 'eapep']]

locs = list(eapep_gpr.location_id.astype(int).unique())
locs.remove(6)

names = []

def master_merger(grouping):
    '''Merges scaled datasets, with eapep and exposure values, and sends off to generate exposures to each occupational risk'''
    for loc in locs:
        if create_datasets == True:
            merge_a = pd.read_csv(scaled+'scale_{g}_{l}.csv'.format(g=grouping, l=loc))
            merge_a = merge_a[(merge_a['year_id'] == 1990) | (merge_a['year_id'] == 1995) | (merge_a['year_id'] == 2000) | (merge_a['year_id'] == 2005) | (merge_a['year_id'] == 2010) | (merge_a['year_id'] == 2015)]
            merge_a.drop(['age_group_id', ], axis=1, inplace=True)

            merge_b = eapep_gpr[eapep_gpr['location_id'] == loc]
            merge_c = template[template['location_id'] == loc]

            merger = pd.merge(merge_a, merge_b, how='inner', on=['location_id', 'year_id', 'sex_id'])

            #Add on exposures
            if grouping == 'ea':
                merger = pd.merge(merger, exposure, how='left', on='me_name')

            #Add on populations
            merger = pd.merge(merger, merge_c, how='left', on=['location_id', 'year_id', 'age_group_id', 'sex_id'])

            #Ship out
            merger.to_csv(inter+'inter_{g}_{l}.csv'.format(g=grouping, l=loc))

        #Submit jobs for each location
        os.system('qsub -P proj_custom_models -l mem_free=10G -pe multi_slot 5 -N {g}_exposures_{l} /snfs2/HOME/strUser/code/shells/python_shell.sh /snfs2/HOME/strUser/code/occ/exposure_function_using_{g}.py {l}'.format(g=grouping, l=loc))
        names.append('{g}_exposures_{l}'.format(g= grouping, l=loc))

for group in estimates:
    master_merger(group)

names = ','.join(names)
#os.system('qsub -P proj_custom_models -l mem_free=4G -pe multi_slot 4 -hold_jid {n} -N occ_save_results_launch /snfs2/HOME/strUser/code/shells/python_shell.sh /snfs2/HOME/strUser/code/occ/4_save_occupational_exposures.py'.format(n=names))
