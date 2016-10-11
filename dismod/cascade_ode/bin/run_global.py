import os
import json
import sys
import drill
from drill import Cascade, Cascade_loc
import upload
from importer import Importer
import warnings
import numpy as np
import getpass
from emr_calc import main as emr_calc
from jobmon import job, sge
sys.path.append('%s/../diagnostics' % drill.this_path)
import file_check
import math
import upload
import subprocess


# Set default file mask to readable-for all users
os.umask(0o0002)

# Disable warnings
def nowarn(message, category, filename, lineno, file=None, line=None):
    pass
warnings.showwarning = nowarn


def run_world(year, cascade, drop_emr=False, reimport=False):
    cl = Cascade_loc(1, 0, year, cascade, timespan=50, reimport=reimport)
    if drop_emr:
        cl.gen_data(1, 0, drop_emr=True)
    cl.run_dismod()
    cl.summarize_posterior()
    cl.draw()
    cl.predict()
    return cascade


def execute(conn_str, query):
    import sqlalchemy
    eng = sqlalchemy.create_engine(conn_str)
    conn = eng.connect()
    conn.execute(query)
    conn.close()


if __name__ == "__main__":

    mvid = int(sys.argv[1])
    runfile = "%s/run_children.py" % drill.this_path
    thisfile = "%s/run_global.py" % drill.this_path
    finfile = "%s/varnish.py" % drill.this_path

    # Get configuration options
    if os.path.isfile(os.path.join(drill.this_path, "../config.local")):
        settings = json.load(
                open(os.path.join(drill.this_path, "../config.local")))
    else:
        settings = json.load(open(
            os.path.join(drill.this_path, "../config.default")))
    logdir = '%s/%s' % (settings['log_dir'], mvid)
    j = job.Job('%s/%s' % (settings['cascade_ode_out_dir'], mvid))
    j.start()

    def update_run_time():
        from datetime import datetime
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print now
        query = """
            UPDATE epi.model_version
            SET model_version_run_start='%s'
            WHERE model_version_id=%s""" % (now, mvid)
        execute(settings['epi_conn_str'], query)

    try:
        os.makedirs(logdir)
    except:
        pass
    try:
        os.chmod(logdir, 0o775)
    except:
        pass
    try:
        rerun_num = int(sys.argv[2])
    except:
        rerun_num = 0
    try:
        cv_iter = int(sys.argv[3])
    except:
        mvm = Importer.get_model_version(mvid)
        cv_run = mvm.cross_validate_id.values[0]
        meid = mvm.modelable_entity_id.values[0]
        if meid in [9422, 7695, 1175]:
            project = "proj_tb"
        else:
            project = "proj_dismod"
        if cv_run == 1:
            cv_iters = range(11)
            jids = []
            for i in cv_iters:
                jobname = 'dm_%s_diag%s' % (mvid, i),
                jid = sge.qsub(
                        thisfile,
                        jobname,
                        project=project,
                        slots=15,
                        memory=30,
                        parameters=[mvid, 0, i],
                        conda_env='cascade_ode',
                        prepend_to_path='/ihme/code/central_comp/anaconda/bin',
                        stderr='%s/%s.error' % (logdir, jobname))
                jids.append(jid)

            # Submit finishing job
            varn_jobname = 'dm_%s_varnish' % (mvid)
            varn_jid = sge.qsub(
                    finfile,
                    varn_jobname,
                    project=project,
                    holds=jids,
                    slots=15,
                    memory=30,
                    parameters=[mvid],
                    conda_env='cascade_ode',
                    prepend_to_path='/ihme/code/central_comp/anaconda/bin',
                    stderr='%s/%s.error' % (logdir, varn_jobname))
            sys.exit()
        else:
            cv_iter = 0

    cascade = Cascade(mvid, reimport=False, cv_iter=cv_iter)
    has_csmr = 'mtspecific' in cascade.data.integrand.unique()
    csmr_cause_id = cascade.model_version_meta.add_csmr_cause.values[0]
    if csmr_cause_id is None:
        csmr_cause_id = np.nan
    ccvid = cascade.model_version_meta.csmr_cod_output_version_id.values[0]
    meid = cascade.model_version_meta.modelable_entity_id.values[0]
    if meid in [9422, 7695, 1175]:
        project = "proj_tb"
    else:
        project = "proj_dismod"
    user = getpass.getuser()
    remdf = cascade.model_params.query(
            'parameter_type_id == 1 & measure_id == 7')
    if len(remdf) > 0:
        remdf = remdf[['parameter_type_id', 'measure_id', 'age_start',
                       'age_end', 'lower', 'mean', 'upper']]
    else:
        remdf = None
    if (rerun_num == 0 and cv_iter == 0 and
            (not np.isnan(csmr_cause_id) or has_csmr) and
            (meid not in [9422, 7695, 1175])):

        if np.isnan(csmr_cause_id):
            csmr_cause_id = -1

        # Set the commit hash here
        upload.update_model_status(mvid, 0)
        commit_hash = sge.get_commit_hash(dir='%s/..' % drill.this_path)
        upload.set_commit_hash(mvid, commit_hash)

        # Run the world once for emr calculation
        update_run_time()
        run_world(2000, cascade, drop_emr=True)
        try:
            emr_calc.dismod_emr(mvid, csmr_cause_id, ccvid, user, remdf)
        except Exception, e:
            print(e)

        # ... then re-import the cascade and re-run the world
        cascade = Cascade(mvid, reimport=True, cv_iter=cv_iter)
        update_run_time()
        run_world(2000, cascade, reimport=True)

    elif rerun_num == 0 and cv_iter == 0:
        update_run_time()
        upload.update_model_status(mvid, 0)
        run_world(2000, cascade)

    elif rerun_num == 0:
        update_run_time()
        run_world(2000, cascade)

    j.finish()
    year_split_lvl = cascade.model_version_meta.fix_year.values[0]-1

    # Break if 3 attempts at the model have been made
    if rerun_num>3:
        rrs = file_check.reruns(mvid, cascade.location_set_version_id, cv_iter=cv_iter)
        log = open('%s/error.log' % cascade.root_dir, 'a')
        log.write('Model is incomplete after two attempted relaunches')
        for rr in rrs:
            log.write(rr)
        log.close()
        sys.exit()

    lt = cascade.loctree

    all_jids = []
    rrs = file_check.reruns(mvid, cascade.location_set_version_id, cv_iter=cv_iter)
    for sex in ['male','female']:
        def dependent_submit(location_id, hold_ids):
            node = lt.get_node_by_id(location_id)
            nodelvl = lt.get_nodelvl_by_id(location_id)
            num_children = len(node.children)
            if num_children==0:
                return 0
            else:
                jids = []
                for y in range(1990, 2016, 5):
                    job_name = "dm_%s_%s_%s_%s_%s" % (mvid, location_id,
                            sex[0], str(y)[2:], cv_iter)
                    if location_id==1:
                        num_slots = 20
                    else:
                        num_slots = min(20, num_children*2)
                    if (location_id, sex, y, cv_iter) in rrs:
                        params = [mvid, location_id, sex, y, cv_iter]
                        jid = sge.qsub(
                                runfile, job_name,
                                project=project,
                                holds=hold_ids,
                                slots=num_slots,
                                memory=int(math.ceil(num_slots*2.5)),
                                parameters=params,
                                conda_env='cascade_ode',
                                prepend_to_path='/ihme/code/central_comp/anaconda/bin',
                                stderr='%s/%s.error' % (logdir, job_name))
                        jids.append(jid)
                        all_jids.append(jid)
                for c in node.children:
                    dependent_submit(c.id, jids)

        dependent_submit(1, [])

    if len(rrs)>0:
        jobname = 'dm_%s_diag%s' % (mvid, cv_iter)
        jid = sge.qsub(
                thisfile,
                jobname,
                project=project,
                holds=all_jids,
                slots=15,
                memory=30,
                parameters=[mvid, rerun_num+1, cv_iter],
                conda_env='cascade_ode',
                prepend_to_path='/ihme/code/central_comp/anaconda/bin',
                stderr='%s/%s.error' % (logdir, jobname))

        # Check for finishing job and submit if not present. If it
        # already exists, add another hold.
        varn_jobname = 'dm_%s_varnish' % (mvid)
        varn_job = sge.qstat(pattern=varn_jobname)
        if len(varn_job) == 0 or cv_iter == 0:
            varn_jid = sge.qsub(
                    finfile,
                    varn_jobname,
                    project=project,
                    holds=jid,
                    slots=20,
                    memory=40,
                    parameters=[mvid],
                    conda_env='cascade_ode',
                    prepend_to_path='/ihme/code/central_comp/anaconda/bin',
                    stderr='%s/%s.error' % (logdir, varn_jobname))
        elif len(varn_job) > 0:
            varn_jid = int(varn_job.job_id.values[0])
            sge.add_holds(varn_jid, jid)
