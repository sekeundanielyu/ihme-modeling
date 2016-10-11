"""
Compile PAF inputs generated in step 05
Fri May 27 11:04:17 2016
"""

import pandas as pd
import platform
import os
import sys

if platform.system() == 'Windows':
    drive = 'J:'
    postscale_dir = 'C:/Users//Desktop/'
    
else:
    drive = '/home/j'
    postscale_dir = sys.argv[1]
    
#Read in alcohol locations
locations = pd.read_csv('{d}/WORK/05_risk/risks/drugs_alcohol/data/exp/temp/paf_locations.csv'.format(d=drive), encoding='Latin-1')

# Read in PAF inputs by country, then concatenate together
merge_machine = []
for file in os.listdir(postscale_dir):
    if 'alc_intermediate_' in file:
        data = pd.read_csv(postscale_dir+file)
        merge_machine.append(data)

paf_input = pd.concat(merge_machine, ignore_index=True)

#Add on info on locations
paf_input = pd.merge(paf_input, locations, on='location_id', how='left')

#Export by year
paf_input = paf_input.groupby('year_id')

for year, data in paf_input:
    data.to_csv(postscale_dir+'alc_data_{y}.csv'.format(y=year))
