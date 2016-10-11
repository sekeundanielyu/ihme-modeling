import subprocess
import pandas as pd
import os
import re
from datetime import datetime
from adding_machine.adding_machine import agg_locations as sr
import glob
from cluster_utils import submitter
import time


def wait(pattern, seconds):
    seconds = int(seconds)
    while True:
        qstat = submitter.qstat()
        if qstat['name'].str.contains(pattern).any():
            print time.localtime()
            time.sleep(seconds)
            print time.localtime()
        else:
            break

# pull in dependency map
dep_map = pd.read_csv('%s/dependency_map.csv' % os.getcwd())
input_mes = dep_map.input_me.unique()
output_string = dep_map.output_mes.unique()
output_mes = []
for i in output_string:
    output_mes.extend(i.split(';'))

# make timestamped output folder
date_regex = re.compile('\W')
date_unformatted = str(datetime.now())[0:13]
c_date = date_regex.sub('_', date_unformatted)
base_dir = '/ihme/centralcomp/custom_models/nonfatal_maternal/%s' % c_date
for output_me in output_mes:
    out_dir = ('%s/%s' % (base_dir, output_me))
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

# Run Adjustments
yearvals = range(1990, 2016, 5)
for index, row in dep_map.iterrows():
    for year in yearvals:
        class_name = row['class_name']
        input_me = row['input_me']
        output_me = row['output_mes']
        call = ('qsub -cwd -P proj_custom_models -o /share/temp/sgeoutput/'
                'maternal -e /share/temp/sgeoutput/maternal -pe multi_slot 15 '
                '-N adjust_%s_%s cluster_shell.sh maternal_core.py "%s" '
                '"%s" "%s" "%s" "%s"'
                % (class_name, year, class_name, base_dir, year, input_me,
                   output_me))
        print call
        subprocess.call(call, shell=True)

# # Wait for Adjustments to finish.
wait('adjust', 300)

# # Concatenate epi uploader sheets for Infertility
infertility_dir = '%s/2624/' % base_dir
to_upload_dir = ('/home/j/WORK/04_epi/01_database/02_data/maternal_sepsis/2624'
                 '/04_big_data')
if not os.path.exists(to_upload_dir):
    os.makedirs(to_upload_dir)
to_upload = []
for f in glob.glob(infertility_dir + "*.csv"):
    df = pd.read_csv(f)
    to_upload.append(df)
upload_me = pd.concat(to_upload)
upload_me.to_excel('%s/to_upload_infertility_incidence.xlsx' % to_upload_dir,
                   sheet_name='extraction', index=False)

# Upload Infertility using the Big Data Uploader
call = ('qsub upload_infertility.sh "%s/to_upload_infertility_incidence.xlsx"'
        % to_upload_dir)
subprocess.call(call, shell=True)

# Save Results of everything else
output_mes.remove('2624')
for me in output_mes:
    me = int(me)
    out_dir = ('%s/%s' % (base_dir, me))
    description = ('applied live births to incidence; applied duration')
    sr.save_custom_results(meid=me, description=description, input_dir=out_dir,
                           sexes=[2], mark_best=True, env='prod')
