import sys
import os
from jobmon import sge
import subprocess
from time import sleep
from datetime import datetime
from functools32 import lru_cache
import settings
import pandas as pd


# Set default file mask to readable-for all users
os.umask(0o0002)


@lru_cache()
def get_directories(mvid):
    """ Define and creat directories for cascade outputs and logs """
    sett = settings.load()
    logdir = '%s/%s' % (sett['log_dir'], mvid)
    try:
        os.makedirs(logdir)
    except:
        pass
    root_dir = '%s/%s' % (sett['cascade_ode_out_dir'], mvid)
    try:
        os.makedirs(root_dir)
    except:
        pass
    os.chmod(logdir, 0o775)
    os.chmod(root_dir, 0o775)
    return {'logdir': logdir, 'root_dir': root_dir}


def start_monitor_process(mvid):
    """ Start the monitoring subprocess """
    dirs = get_directories(mvid)
    root_dir = dirs['root_dir']
    monp = subprocess.Popen([
        '/ihme/code/central_comp/anaconda/envs/py35/bin/python',
        '%s/monitor_callable.py' % settings.this_path,
        root_dir])
    return monp


def submit_global(mvid, project):
    """ Submit the global dismod_ode job """
    dirs = get_directories(mvid)
    logdir = dirs['logdir']
    gfile = "%s/run_global.py" % settings.this_path
    jobname = 'dm_%s_G' % mvid
    jid = sge.qsub(
        gfile,
        jobname,
        project=project,
        slots=15,
        memory=30,
        parameters=[mvid],
        conda_env='cascade_ode',
        prepend_to_path='/ihme/code/central_comp/anaconda/bin',
        stderr='%s/%s.error' % (logdir, jobname))
    return jid


def get_meid(mvid):
    import sqlalchemy
    sett = settings.load()
    cstr = sett['epi_conn_str']
    eng = sqlalchemy.create_engine(cstr)
    meid = pd.read_sql("""
        SELECT modelable_entity_id FROM epi.model_version
        WHERE model_version_id = %s""" % mvid, eng)
    return meid.values[0][0]


def poll_sge(monp):
    """ Poll for running jobs. If there aren't any, kill the monitor
    process"""
    dirs = get_directories(mvid)
    root_dir = dirs['root_dir']
    print(root_dir)
    jobs_exist = True
    while jobs_exist:
        sleep(30)
        print("Polling dm_%s jobs ... %s" % (mvid, datetime.now()))
        dmjobs = sge.qstat(pattern="dm_%s" % mvid)
        dmjobs = dmjobs[dmjobs.name != 'dm_%s_P' % mvid]
        if len(dmjobs) == 0:
            jobs_exist = False
    monp.kill()


if __name__ == "__main__":
    mvid = int(sys.argv[1])
    meid = get_meid(mvid)
    if meid in [9422, 7695, 1175]:
        project = "proj_tb"
    else:
        project = "proj_dismod"
    monp = start_monitor_process(mvid)
    sleep(60)
    gjob = submit_global(mvid, project)
    poll_sge(monp)
