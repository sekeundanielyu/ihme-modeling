import subprocess
import os
import sys
import re
from datetime import datetime
import time
try:
    from db_tools import dbapis, query_tools
    import db_process_upload
    import maternal_fns
except:
    sys.path.append(str(os.getcwd()).rstrip('/mmr'))
    from db_tools import dbapis, query_tools
    import db_process_upload
    import maternal_fns

enginer = dbapis.engine_factory()
query = ('SELECT cause_id FROM shared.cause_hierarchy_history '
         'WHERE cause_set_id = 8 AND cause_set_version_id = '
         '(SELECT cause_set_version_id FROM shared.cause_set_version '
         'WHERE cause_set_id = 8 and end_date IS NULL)')
causes = (query_tools.query_2_df(query, engine=enginer.engines["cod_prod"])
          ['cause_id'].tolist())

# set out directory
date_regex = re.compile('\W')
date_unformatted = str(datetime.now())[0:13]
date_str = date_regex.sub('_', date_unformatted)
out_dir = '/ihme/centralcomp/maternal_mortality/mmr/%s' % date_str
arc_out_dir = '%s/multi_year' % out_dir
mmr_out_dir = '%s/single_year' % out_dir
if not os.path.exists('%s' % out_dir):
    os.makedirs('%s' % out_dir)
if not os.path.exists('%s' % arc_out_dir):
    os.makedirs('%s' % arc_out_dir)
if not os.path.exists('%s' % mmr_out_dir):
    os.makedirs('%s' % mmr_out_dir)

env = 'gbd_prod'
proc_json = db_process_upload.create_tables(env)
json = proc_json.loc[0, 'v_return_string']
process_v = int(json.split()[2].replace('"', "").replace(",", ""))
yearvals = range(1990, 2016)

for year in yearvals:
    for cause in causes:
        call = ('qsub -cwd -P proj_custom_models -N "part1_%s_%s" -l '
                'mem_free=40G -pe multi_slot 20 -o '
                '/share/temp/sgeoutput/maternal '
                '-e /share/temp/sgeoutput/maternal cluster_shell.sh '
                'mmr/01_calculate_MMR_from_draws.py "%s" "%s" "%s" "%s"'
                % (cause, year, cause, year, process_v, mmr_out_dir))
        subprocess.call(call, shell=True)

maternal_fns.wait('part1', 300)

for cause in causes:
    call = ('qsub -cwd -P proj_custom_models -N "part2_%s" -l '
            'mem_free=40G -pe multi_slot 20 -o /share/temp/sgeoutput/maternal '
            '-e /share/temp/sgeoutput/maternal cluster_shell.sh '
            'mmr/02_calculate_ARC_from_MMR.py "%s" "%s"'
            % (cause, cause, arc_out_dir))
    subprocess.call(call, shell=True)

maternal_fns.wait('part2', 300)

upload_types = ['single', 'multi']
for u_type in upload_types:
    if u_type == 'single':
        in_dir = mmr_out_dir
    else:
        in_dir = arc_out_dir
    call = ('qsub -cwd -P proj_custom_models -N "part3_%s" -l mem_free=10G '
            '-pe multi_slot 5 -o /share/temp/sgeoutput/maternal '
            '-e /share/temp/sgeoutput/maternal cluster_shell.sh '
            'mmr/03_upload.py "%s" "%s" "%s" "%s"'
            % (u_type, u_type, process_v, env, in_dir))
    subprocess.call(call, shell=True)
    time.sleep(5)

