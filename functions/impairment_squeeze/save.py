from jobmon import sge
from glob import glob
import os

dirs = glob("strOutDir/*")
runfile = "save_custom_results"
for d in dirs:
    meid = os.path.basename(d)
    sge.qsub(
        runfile,
        "ss_save_%s" % meid,
        parameters=[
            meid,
            "super-squeeze result",
            d,
            '--env', 'prod',
            '--file_pattern', '{location_id}_{year_id}_{sex_id}.h5',
            '--h5_tablename', 'draws',
            '--best'],
        jobtype=None,
        conda_env="como",
        slots=20,
        memory=40,
        project='proj_como')
