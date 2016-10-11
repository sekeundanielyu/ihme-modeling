#!/bin/bash
source /ihme/code/central_comp/anaconda/bin/activate tasker
cd /ihme/centralcomp/custom_models/infertility/infertility
python -m tasks Hook --identity process_hook --local-scheduler --workers 4 &> ~/temp/infert_full_1.txt
