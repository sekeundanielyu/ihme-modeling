# collect prevalence draws from dw.PREV_REI_IDS
import sys
import os
from getpass import getuser
import sqlalchemy as sql
import pandas as pd
import numpy as np

sys.path.append('/ihme/code/python_shared/')
import cluster_helpers as ch

if getuser() == 'strUser':
    SDG_REPO = "/homes/strUser/sdg-capstone-paper-2015"
if getuser() == 'strUser':
    SDG_REPO = ('/ihme/code/test/strUser/under_development'
                '/sdg-capstone-paper-2015')
if getuser() == 'strUser':
    SDG_REPO = "/homes/strUser/sdgs/sdg-capstone-paper-2015"
sys.path.append(SDG_REPO)
sys.path.append("/home/j/WORK/10_gbd/00_library/transmogrifier/")
import transmogrifier.gopher as gopher
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test


def submit_collect(measure_id):
    """Submit a cluster job to collect processed draws."""
    log_dir = "/share/temp/sgeoutput/sdg/"
    if not os.path.exists(log_dir):
        os.mkdir(log_dir)
    jobname = "sdg_risk_burden_{m}".format(m=measure_id)
    worker = "{}/data_prep/risk_burden.py".format(SDG_REPO)
    shell = "{}/sdg_utils/run_on_cluster.sh".format(SDG_REPO)
    args = ["run_one", measure_id]
    job_id = ch.qsub(worker, shell, 'proj_sdg', custom_args=args,
                     name=jobname, log_dir=log_dir, slots=10,
                     verbose=True)
    return job_id


def collect_risk_attrib_burden(rei_ids, measure_id,
                               locs=None):
    ''' Given a list of rei_ids, use gopher to get attributable mortality draws
    and save to out directory. Since these are from dalynator draws, no further
    processing should be necessary.
    (except perhaps interpolation? Can do that as final step)

    Note: run this with a big qlogin because I use extra cores to read more
    files in parallel
    '''
    # note -- untested since I don't have permission to create new directories
    if not locs:
        #locs = set(qry.queryToDF(qry.LOCATIONS.format(lsid=35)).location_id)
        query = "select location_id from locations where level = 3" # Only 188 countries
        engine = sql.create_engine('strConnection')
        locs = set(pd.read_sql_query(query, engine).location_id.values)

    df = gopher.draws(gbd_ids={"rei_ids": rei_ids,
                               "cause_ids": [294]},
                      source='dalynator',
                      version=dw.RISK_BURDEN_DALY_VERS,
                      location_ids=locs,
                      age_group_ids=[27],
                      sex_ids=[3],
                      year_ids=[1990, 1995, 2000, 2005, 2010, 2015],
                      measure_ids=[measure_id],
                      metric_ids=[1],
                      verbose=True,
                      num_workers=10
                      )
    out_dir = dw.RISK_BURDEN_OUTDIR
    # everything is already formatted perfectly so it can just be saved
    if not os.path.exists(out_dir):
        os.mkdir(out_dir)
    for rei_id in df.rei_id.unique():
        print rei_id
        odf = df.query("rei_id == @rei_id")
        #sdg_test.all_sdg_locations(odf)
        odf.to_hdf(
            out_dir + "/{}.h5".format(int(rei_id)), key="data", format="table",
            data_columns=["location_id", "year_id"])
    return df

if __name__ == "__main__":
    process = sys.argv[1]
    if process == "run_all":
        for measure_id in [1, 2]:
            submit_collect(measure_id)
    elif process == "run_one":
        measure_id = int(sys.argv[2])
        if measure_id == 1:
            rei_ids = dw.RISK_BURDEN_REI_IDS
        elif measure_id == 2:
            rei_ids = dw.RISK_BURDEN_DALY_REI_IDS
        else:
            raise ValueError("Invalid measure_id: {m}".format(m=measure_id))
        collect_risk_attrib_burden(rei_ids, measure_id)
    else:
        raise ValueError("Invalid process: {p}".format(p=process))
