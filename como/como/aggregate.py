import os
from version import ComoVersion
from adding_machine import agg_locations as al
from adding_machine import summarizers
from adding_machine.db import EpiDB
from multiprocessing import Pool
from hierarchies import dbtrees
import pandas as pd

lt = dbtrees.loctree(None, 35)
sdi_lts = dbtrees.loctree(None, 40, return_many=True)
locs = [l.id for l in lt.nodes]
locs.extend([l.root.id for l in sdi_lts])


def agg_cause_hierarchy(df):
    thisdf = df.copy()
    ct = dbtrees.causetree(None, 9)
    idx_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
    if 'rei_id' in thisdf.columns:
        idx_cols.append('rei_id')
    md = ct.max_depth()
    lvl = md-1
    while lvl >= 0:
        aggs = []
        for cause in ct.level_n_descendants(lvl):
            child_ids = [c.id for c in cause.children]
            if len(child_ids) > 0:
                agg = thisdf[thisdf.cause_id.isin(child_ids)]
                agg = agg.groupby(idx_cols).sum().reset_index()
                agg['cause_id'] = cause.id
                aggs.append(agg)
        aggs = pd.concat(aggs)
        thisdf = pd.concat([thisdf, aggs])
        lvl = lvl-1
    thisdf = thisdf.groupby(idx_cols+['cause_id']).sum().reset_index()
    return thisdf


def agg_causes(cvid, year, sex, measure_id, location_set_id):
    cv = ComoVersion(cvid)
    for dur in ['acute', 'chronic', 'total']:
        drawdir = os.path.join(cv.root_dir, 'draws', 'cause', dur)
        al.agg_all_locs_mem_eff(
            drawdir, drawdir, location_set_id,
            ['location_id', 'year_id', 'age_group_id', 'sex_id', 'measure_id',
                'cause_id'], year, sex, measure_id)


def agg_sequelae(cvid, year, sex, measure_id, location_set_id):
    cv = ComoVersion(cvid)
    drawdir = os.path.join(cv.root_dir, 'draws', 'sequela', 'total')
    al.agg_all_locs_mem_eff(
        drawdir, drawdir, location_set_id,
        ['location_id', 'year_id', 'age_group_id', 'sex_id', 'measure_id',
            'sequela_id'], year, sex, measure_id)


def agg_rei(cvid, year, sex, measure_id, location_set_id):
    cv = ComoVersion(cvid)
    drawdir = os.path.join(cv.root_dir, 'draws', 'rei', 'total')
    al.agg_all_locs_mem_eff(
        drawdir, drawdir, location_set_id,
        ['location_id', 'year_id', 'age_group_id', 'sex_id', 'measure_id',
            'rei_id', 'cause_id'], year, sex, measure_id)


def summ(cvid, location_id, id_type, dur):
    cv = ComoVersion(cvid)
    drawdir = os.path.join(cv.root_dir, 'draws', id_type, dur)
    summdir = os.path.join(cv.root_dir, 'summaries', id_type, dur)
    summarizers.launch_summaries_como({drawdir: summdir}, location_id)


def upload_cause_year_summaries(cvid, process_id, location_id, measure_id):
    db = EpiDB('gbd')
    eng = db.get_engine(db.dsn_name)
    for dur in ['acute', 'chronic', 'total']:
        for tn in ['single_year', 'multi_year']:
            try:
                if tn == 'single_year':
                    cols = ",".join([
                        'location_id', 'year_id', 'age_group_id', 'sex_id',
                        'measure_id', 'metric_id', 'cause_id', 'val', 'lower',
                        'upper'])
                elif tn == 'multi_year':
                    cols = ",".join([
                        'location_id', 'year_start_id', 'year_end_id',
                        'age_group_id', 'sex_id', 'measure_id', 'cause_id',
                        'metric_id', 'val', 'lower', 'upper'])

                summdir = "/ihme/centralcomp/como/%s/summaries/cause/%s/" % (
                        cvid, dur)
                summary_file = os.path.join(
                        summdir,
                        "%s_%s_%s.csv" % (measure_id, location_id, tn))
                ldstr = """
                    LOAD DATA INFILE '{sf}'
                    INTO TABLE gbd.output_epi_{tn}_v{pid}
                    FIELDS
                        TERMINATED BY ","
                        OPTIONALLY ENCLOSED BY '"'
                    LINES
                        TERMINATED BY "\\n"
                    IGNORE 1 LINES
                        ({cols})""".format(
                                sf=summary_file, pid=process_id, tn=tn,
                                cols=cols)
                res = eng.execute(ldstr)
                print 'Uploaded %s %s %s %s' % (
                        location_id, dur, measure_id, tn)
            except Exception as e:
                print e
                res = None
    return res


def ucys(args):
    upload_cause_year_summaries(*args)


def upload_sequela_year_summaries(cvid, process_id, location_id, measure_id):
    db = EpiDB('gbd')
    eng = db.get_engine(db.dsn_name)
    for tn in ['single_year', 'multi_year']:
        try:
            if tn == 'single_year':
                cols = ",".join([
                    'location_id', 'year_id', 'age_group_id', 'sex_id',
                    'measure_id', 'metric_id', 'sequela_id', 'val', 'lower',
                    'upper'])
            elif tn == 'multi_year':
                cols = ",".join([
                    'location_id', 'year_start_id', 'year_end_id',
                    'age_group_id', 'sex_id', 'measure_id', 'sequela_id',
                    'metric_id', 'val', 'lower', 'upper'])

            summdir = (
                    "/ihme/centralcomp/como/%s/"
                    "summaries/sequela/total/" % cvid)
            summary_file = os.path.join(
                    summdir,
                    "%s_%s_%s.csv" % (measure_id, location_id, tn))
            ldstr = """
                LOAD DATA INFILE '{sf}'
                INTO TABLE gbd.output_sequela_{tn}_v{pid}
                FIELDS
                    TERMINATED BY ","
                    OPTIONALLY ENCLOSED BY '"'
                LINES
                    TERMINATED BY "\\n"
                IGNORE 1 LINES
                    ({cols})""".format(
                            sf=summary_file, pid=process_id, tn=tn, cols=cols)
            res = eng.execute(ldstr)
        except Exception as e:
            print e
            res = None
    return res


def usys(args):
    upload_sequela_year_summaries(*args)


def upload_rei_year_summaries(cvid, process_id, location_id, measure_id):
    db = EpiDB('gbd')
    eng = db.get_engine(db.dsn_name)
    for tn in ['single_year', 'multi_year']:
        try:
            if tn == 'single_year':
                cols = ",".join([
                    'location_id', 'year_id', 'age_group_id', 'sex_id',
                    'measure_id', 'metric_id', 'rei_id', 'cause_id', 'val',
                    'lower', 'upper'])
            elif tn == 'multi_year':
                cols = ",".join([
                    'location_id', 'year_start_id', 'year_end_id',
                    'age_group_id', 'sex_id', 'measure_id', 'rei_id',
                    'cause_id', 'metric_id', 'val', 'lower', 'upper'])

            summdir = (
                    "/ihme/centralcomp/como/%s/"
                    "summaries/rei/total/" % cvid)
            summary_file = os.path.join(
                    summdir,
                    "%s_%s_%s.csv" % (measure_id, location_id, tn))
            ldstr = """
                LOAD DATA INFILE '{sf}'
                INTO TABLE gbd.output_impairment_{tn}_v{pid}
                FIELDS
                    TERMINATED BY ","
                    OPTIONALLY ENCLOSED BY '"'
                LINES
                    TERMINATED BY "\\n"
                IGNORE 1 LINES
                    ({cols})""".format(
                            sf=summary_file, pid=process_id, tn=tn, cols=cols)
            res = eng.execute(ldstr)
        except Exception as e:
            print e
            res = None
    return res


def urys(args):
    upload_rei_year_summaries(*args)


def upload_cause_summaries(cvid):
    cv = ComoVersion(cvid)
    process_id = cv.gbd_process_version_id
    pool = Pool(9)
    args = [(cvid, process_id, l, m)
            for l in locs
            for m in [3, 5, 6, 22, 23, 24]]
    pool.map(ucys, args)
    pool.close()
    pool.join()


def upload_sequela_summaries(cvid):
    cv = ComoVersion(cvid)
    process_id = cv.gbd_process_version_id
    pool = Pool(9)
    args = [(cvid, process_id, l, m)
            for l in locs
            for m in [3, 5, 6]]
    pool.map(usys, args)
    pool.close()
    pool.join()
    cv.mark_best()
    cv.create_compare_version()


def upload_rei_summaries(cvid):
    cv = ComoVersion(cvid)
    process_id = cv.gbd_process_version_id
    pool = Pool(9)
    args = [(cvid, process_id, l, m)
            for l in locs
            for m in [3, 5, 6]]
    pool.map(urys, args)
    pool.close()
    pool.join()
