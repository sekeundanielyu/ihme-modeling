
'''
Takes CODEm's (2015) cross-validation methodology generate 10 ko sets based on location_id, age_group_id, 
sex_id missingness of data. CODEm's original code creates different (mutually exclusive) test sets per 
knockout, I'm concatenating them together just because we're only calculating CV stats once (at the end of GPR).

'''


import sys
sys.dont_write_bytecode = True

run_root = sys.argv[1]
central_root = sys.argv[2]
holdouts = int(sys.argv[3])

import pandas as pd
import os
os.chdir(central_root)
import codem_ko as ko

## Settings
seed = 12345

## Bring in data
os.chdir(run_root)
data = pd.read_hdf('temp.h5', 'prepped')
## Reset Index
data = data.reset_index(drop=True)
## Syntax: df, # of holdouts, seed
knockouts = ko.generate_knockouts(data, holdouts=holdouts, seed=seed)
## Subset and convert from boolean to int
frame = pd.DataFrame()
for i in range(0,holdouts+1):
    holdout = knockouts[i]
    holdout = holdout*1 
    ## I only want one test set, combine train and test1; set to train
    holdout['train'] = holdout['train'] + holdout['test1']
    holdout = holdout.drop(['test1', 'test2'], axis =1)
    colname = 'train%s' %(holdouts-i)
    holdout.columns = [colname]
    frame = pd.concat([frame, holdout], axis=1)
    
## Bring back to data_id
output = pd.concat([data['data_id'], frame], axis=1).convert_objects()

## Output
output.to_hdf('param.h5', 'kos', mode = 'a', format='f')


