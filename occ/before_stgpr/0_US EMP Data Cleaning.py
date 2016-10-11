#Clean US employment data to prepare to append to 2015 occ data


import numpy as np
import pandas as pd
import subprocess
from pandas import DataFrame

#Get datasets

industry_titles = pd.read_csv(open(r'C:/Users/strUser/Work/Data/industry_titles.csv'), dtype = {'industry_code':np.str})
area_titles = pd.read_csv(open(r'C:/Users/strUser/Work/Data/area_titles.csv'),dtype = {'area_fips':np.str})

#I ran the central function get_location_metadata with location_set_id(9) from within Stata to get IHME location names. I then exported that to a CSV to use here to fix country names.

#Runs a small Stata do file to get_locations
dofile = "H:/Code/occ/0a_get_locations.do"
cmd = ["C:\Program Files (x86)\Stata13\StataSE-64.exe", "do", dofile]
subprocess.call(cmd, shell = 'true')
QCEW = DataFrame() 

ihme_locations = pd.read_csv(r'C:/Users/strUser/Work/Data/get_locations.csv', encoding='latin-1')

#Only keep US locations for merge and rename variables
ihme_locations = ihme_locations[(ihme_locations['region_name'] == str('High-income North America'))]
ihme_locations = ihme_locations.loc[:,['location_name', 'ihme_loc_id']]     #Only keep variables needed for merge
ihme_locations = ihme_locations.rename(columns = {'location_name': 'area_title'})

#Loop through years to produce individually cleaned datasets from BLS. Will append them all together at end
for year in range(1990, 2015):
    QCEW = QCEW.append(pd.read_csv(open(r'C:/Users/strUser/Work/Data/QCEW/{date}.annual.singlefile.csv'.format(date = year)), usecols = ["area_fips", "industry_code", "annual_avg_emplvl", "own_code", "year"], dtype = {'area_fips':np.str}))

#Clean all datasets before merging
##Hold onto only relevant variables for GBD

QCEW = QCEW[(QCEW.own_code == 0) | ((QCEW.own_code == 5) & (QCEW.industry_code != '10'))]    #Drops distinctions the QCEW study made concerning industry types
QCEW = QCEW.drop('own_code', axis=1)        

#Add on human readable names
QCEW = pd.merge(QCEW, industry_titles, on='industry_code')
QCEW = pd.merge(QCEW, area_titles, on='area_fips')

#Need to only hold onto the right industries
industries = ['10', '11', '21', '22', '23', '31-33', '42', '44-45', '48-49', '52', '53', '81']
QCEW = QCEW[QCEW['industry_code'].isin(industries)]   
             
##Want to only keep states
#Start by renaming national obs to easily cast BLS strings to float

for row in QCEW.index:
    if QCEW.at[row, 'area_fips'] == 'US000':
        QCEW.at[row, 'area_fips'] = '00000'
    elif QCEW.at[row, 'area_fips'].isdigit() == False:
        QCEW.at[row, 'area_fips'] = '1'
        
QCEW.loc[:, 'area_fips'] = QCEW.area_fips.astype(float)
states = range(0, 57000, 1000)
QCEW = QCEW[QCEW['area_fips'].isin(states)]

#Shorten state names to match IHME to prepare for merge.
for row in QCEW.index:
    if QCEW.at[row, 'area_title'] == 'U.S. TOTAL':
        QCEW.at[row, 'area_title'] = 'United States'
    elif QCEW.at[row, 'area_title'].startswith('District') == False:
        QCEW.at[row, 'area_title'] = QCEW.at[row, 'area_title'].split('-',1)[0].strip()
        
QCEW = pd.merge(QCEW, ihme_locations, on='area_title')

#Some penultimate housekeeping: need to add together some variables to conform with IHME industries
##Start by pivoting dataset by industry title

QCEW = pd.pivot_table(QCEW, values='annual_avg_emplvl', index=['area_title', 'year', 'ihme_loc_id'], columns=['industry_title'])

#Now adding some variables, cleaning up some names, and dropping irrelevant industries

QCEW['Business_Services'] = QCEW['NAICS 53 Real estate and rental and leasing'] + QCEW['NAICS 52 Finance and insurance']
QCEW['Trade'] = QCEW['NAICS 42 Wholesale trade'] + QCEW['NAICS 44-45 Retail trade']

drop_obs = ['NAICS 42 Wholesale trade', 'NAICS 44-45 Retail trade', 'NAICS 52 Finance and insurance', 'NAICS 53 Real estate and rental and leasing']
QCEW = QCEW.drop(drop_obs, axis=1)

#%%
#Transform into proportions
QCEW = QCEW.rename(columns = {'NAICS 48-49 Transportation and warehousing':'Transport_Communication', 'NAICS 11 Agriculture, forestry, fishing and hunting': 'Agriculture', 'NAICS 21 Mining, quarrying, and oil and gas extraction':'Mining', 'NAICS 22 Utilities': 'Electricity_Gas_Water', 'NAICS 23 Construction': 'Construction', 'NAICS 31-33 Manufacturing': 'Manufacturing', 'NAICS 81 Other services, except public administration': 'Social_Services'})
columns = [col for col in QCEW.columns if 'Total' not in col]
QCEW[columns] = QCEW[columns].div(QCEW[columns].sum(axis='columns').values, axis='index')
QCEW.reset_index(inplace=True)

#Reshape for merging with global estimates.
QCEW = pd.melt(QCEW, id_vars=['ihme_loc_id', 'year'], value_vars=columns, var_name='categories', value_name='data')

QCEW.to_csv(r'C:/Users/strUser/work/data/QCEW_cleaned.csv')