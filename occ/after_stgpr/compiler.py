"""
Compile all locations together
Tue May  3 09:56:52 2016
"""

import pandas as pd
import os
import sys

#Read in arguments and set file paths
model = sys.argv[1]
version = sys.argv[2]

directory = '/ihme/scratch/users//temp/'

#Read each compiled location and append together; delete files afterwards
merge_machine = []
for file in os.listdir(directory):
    if model in file:
        data = pd.read_csv(directory+file)
        merge_machine.append(data)
        os.remove(directory+file)

compiled = pd.concat(merge_machine, ignore_index=True)
compiled.to_stata('/home/j/WORK/05_risk/risks/occ/gpr_output/gpr_results/{m}_{v}.dta'.format(m=model, v=version))

print(model)
print(version)
