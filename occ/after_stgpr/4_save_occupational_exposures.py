"""
4. Save occupational exposures
Thu Apr 28 11:08:36 2016
"""

import pandas as pd
import os
import platform

if platform.system() == 'Windows':
    drive = 'J:'
else:
    drive = '/home/j'

#Read in exposure data
exposures = pd.read_csv('{}/WORK/05_risk/risks/occ/raw/exposures/modelable_entity_names.csv'.format(drive))
exposures = exposures[19:]

models = list(exposures['modelable_entity_id'])
description = list(exposures['modelable_entity_name'])
exposure = list(exposures['exposure'])
group = list(exposures['group'])

#%%
#Submit jobs

for i in range(len(models)):
    os.system('qsub -P proj_custom_models -o /snfs2/HOME/ -e /snfs2/HOME/ -l mem_free=2G -pe multi_slot 2 -N occ_save_{m} /snfs2/HOME//code/shells/stata_shell.sh /snfs2/HOME//code/occ/save_results.do "model({m}) description({d}) exposure({e}) group({g})"'.format(m = models[i], d = description[i].replace(',',''), e=exposure[i], g=group[i]))

save_results, modelable_entity_id(8914) description(occupational exposure to asbestos, high) in_dir(/ihme/scratch/users//occ_carcino/occ_carcino_asbestos/high/) metrics(proportion) risk_type(exp) mark_best(yes)
