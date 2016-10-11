"""
Scale function for cluster parallelization
Mon Apr 11 11:46:53 2016
"""
import sys
import numpy as np
import pandas as pd
import logging as log

#Set local variables

location = sys.argv[1]
grouping = sys.argv[2]

log.basicConfig(filename='/ihme/scratch/users//log/scaling_{g}_{l}.txt'.format(g=grouping, l=location), level=log.DEBUG, format='%(asctime)s %(message)s', datefmt='%m/%d/%Y %I:%M:%S')

data = pd.read_hdf('/ihme/scratch/users/strUser/{g}.hdf'.format(g=grouping), 'data', where='location_id == {l}'.format(l=location))
frames = []

log.debug('HDF has been read.')

draws = [col for col in data.columns if 'draw' in col]

#%%
#Scale to 1 for each year, sex, draw

#Bound results below at 0
data[draws] = data[draws].where(data[draws]>=0, 0)

#Don't include injury total when scaling, append on afterwards
if grouping == 'inj':
    total = data[data['me_name'] == 'occ_inj_total']
    data = data[data['me_name'] != 'occ_inj_total']

grouper = data.groupby(['year_id', 'sex_id'])
log.debug('Starting loop!')

#Replace draws with draw_i/total_draw_i
for (year, sex), data in grouper:
    log.debug('Loop: {y} {s}'.format(y=year, s=sex))
    data[draws] /= data[draws].sum()
    data[draws] = np.round(data[draws], 5)

    #Append to new scaled dataset
    frames.append(data)
    log.debug('Loop finished!')

log.debug('Merging!')

#Export!
scaled = pd.concat(frames, ignore_index=True)

if grouping =='inj':
    scaled = scaled.append(total, ignore_index=True)

log.debug('Concatted!')
scaled.to_csv('/home/j/WORK/05_risk/risks/occ/gpr_output/gpr_scaled_results/scale_{g}_{i}.csv'.format(g=grouping, i=location), index=False)

log.debug('Merging finished!')
