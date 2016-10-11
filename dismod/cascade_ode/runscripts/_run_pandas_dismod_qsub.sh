#! /bin/bash
#$ -S /bin/bash

model_id=$1
export PATH=/ihme/code/central_comp/anaconda/bin:$PATH
source activate cascade_ode
echo "python /ihme/code/panda_cascade/bin/run_all.py $model_id"
python strCodeDir/run_all.py $model_id
