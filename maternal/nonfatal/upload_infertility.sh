#!/usr/bin/env bash
source /ihme/code/central_comp/anaconda/bin/activate epidb_loaders
cd /ihme/centralcomp/epidb_loaders
#$ -N upload_infertility
#$ -cwd
#$ -P proj_custom_models
#$ -l mem_free=10G
#$ -pe multi_slot 5
#$ -o /share/temp/sgeoutput/maternal
#$ -e /share/temp/sgeoutput/maternal

filepath="$1"
echo "$filepath"

python ./bin/request_input_data_load.py --filepath "$filepath" --delete_group modelable_entity_id,nid



