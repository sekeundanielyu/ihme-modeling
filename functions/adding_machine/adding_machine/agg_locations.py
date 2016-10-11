import os
import pandas as pd
import agg_engine as ae
try:
    from hierarchies import dbtrees
except:
    from hierarchies.hierarchies import dbtrees
from functools32 import lru_cache
from db import EpiDB
import super_gopher
import shutil
import summarizers
import warnings
from datetime import datetime
import sys
import uuid
from itertools import izip_longest


def grouper(iterable, n, fillvalue=None):
    """Collect data into fixed-length chunks or blocks"""
    args = [iter(iterable)] * n
    return izip_longest(fillvalue=fillvalue, *args)


# Disable warnings
def nowarn(message, category, filename, lineno, file=None, line=None):
    pass
warnings.showwarning = nowarn

# Set module-level variables
this_file = os.path.abspath(__file__)
this_path = os.path.dirname(this_file)
sex_map = {'male': 1, 'female': 2, 1: 1, 2: 2}
sentinel = None


def pretty_now():
    return datetime.now().strftime('[%m/%d/%Y %H:%M:%S]')


@lru_cache()
def get_pop():
    query = """
        SELECT age_group_id, year_id, location_id, sex_id, pop_scaled
        FROM mortality.output o
        LEFT JOIN mortality.output_version ov using (output_version_id)
        WHERE ov.is_best = 1
        AND year_id >= 1980 AND year_id <= 2015"""
    db = EpiDB('cod')
    eng = db.get_engine(db.dsn_name)
    pop = pd.read_sql(query, eng)
    return pop


def get_subpop(
        location_ids=None, year_ids=None, age_group_ids=None, sex_ids=None):
    query_str = []
    if location_ids is not None:
        if not hasattr(location_ids, "__iter__"):
            location_ids = [location_ids]
        location_ids = [str(l) for l in location_ids]
        query_str.append('(location_id in [%s])' % ",".join(location_ids))
    if age_group_ids is not None:
        if not hasattr(age_group_ids, "__iter__"):
            age_group_ids = [age_group_ids]
        age_group_ids = [str(l) for l in age_group_ids]
        query_str.append('(age_group_id in [%s])' % ",".join(age_group_ids))
    if year_ids is not None:
        if not hasattr(year_ids, "__iter__"):
            year_ids = [year_ids]
        year_ids = [str(l) for l in year_ids]
        query_str.append('(year_id in [%s])' % ",".join(year_ids))
    if sex_ids is not None:
        if not hasattr(sex_ids, "__iter__"):
            sex_ids = [sex_ids]
        sex_ids = [str(l) for l in sex_ids]
        query_str.append('(sex_id in [%s])' % ",".join(sex_ids))
    if len(query_str) > 0:
        query_str = " & ".join(query_str)
        return pop.query(query_str)
    else:
        return pop


def aggregate_child_locs(
        drawdir,
        lt,
        parent_location_id,
        year,
        sex,
        index_cols,
        sgs,
        include_leaves=False,
        operator='wtd_sum',
        force_lowmem=False,
        chunksize=4,
        draw_filters={},
        **kwargs):

    location_list = [
        l.id for l in lt.get_node_by_id(parent_location_id).children]
    location_list = list(location_list)
    pops = get_subpop(
            location_ids=location_list,
            year_ids=year,
            sex_ids=sex_map[sex])

    if force_lowmem:
        chunksize = chunksize
    else:
        chunksize = len(location_list)
    df = None
    indf = []
    for this_ll in grouper(location_list, chunksize, None):
        chunkdf = []
        this_ll = [l for l in this_ll if l is not None]
        for sg in sgs:
            try:
                thisdf = sg.content(
                    location_id=this_ll, year_id=year, sex_id=sex,
                    **draw_filters)
                this_ll = list(
                    set(this_ll) - set(thisdf.location_id.unique()))
                chunkdf.append(thisdf)
            except:
                continue
        chunkdf = pd.concat(chunkdf)
        chunkdf.reset_index(drop=True, inplace=True)

        for idx in ['location_id', 'year_id', 'age_group_id', 'sex_id']:
            try:
                pops[idx] = pops[idx].astype('int')
                chunkdf[idx] = chunkdf[idx].astype('int')
            except:
                pass
        chunkdf = chunkdf.merge(
                pops, on=['location_id', 'year_id', 'age_group_id', 'sex_id'])
        if df is not None:
            chunkdf = pd.concat([chunkdf, df])
        agg_cols = list(set(index_cols) - set(['location_id']))
        for ac in agg_cols:
            try:
                chunkdf[ac] = chunkdf[ac].astype('int')
            except:
                pass
        draw_cols = ['draw_%s' % i for i in range(1000)]
        if include_leaves:
            indf.append(chunkdf[chunkdf.location_id.isin(
                [l.id for l in lt.leaves()])].copy())
        if operator == 'wtd_sum':
            thispopdf = ae.aggregate(
                    chunkdf[index_cols+['pop_scaled']],
                    ['pop_scaled'],
                    agg_cols,
                    'sum')
            chunkdf = ae.aggregate(
                    chunkdf[index_cols+draw_cols+['pop_scaled']],
                    draw_cols,
                    agg_cols,
                    'wtd_sum',
                    weight_col='pop_scaled')
            chunkdf = chunkdf.merge(thispopdf)
        elif operator == 'sum':
            chunkdf = ae.aggregate(
                    chunkdf[index_cols+draw_cols+['pop_scaled']],
                    draw_cols,
                    agg_cols,
                    'sum')
        df = chunkdf.copy()
    df['location_id'] = parent_location_id
    if include_leaves:
        indf = pd.concat(indf)
        df = df.append(indf)
    df.drop('pop_scaled', axis=1, inplace=True)
    return df


def aclw_mp(mapargs):
    try:
        args, kwargs = mapargs
        (drawdir, lt, parent_loc,
            year, sex, index_cols, sgs, include_leaves, operator) = args
        aggdf = aggregate_child_locs(*args)
        if kwargs['single_file']:
            pass
        else:
            outfile = '%s/%s%s_%s_%s.h5' % (
                '', parent_loc, year, sex_map[sex])
            aggdf['location_id'] = parent_loc
            aggdf.to_hdf(
                    outfile, 'draws', mode='w', format='table',
                    data_columns=['measure_id', 'age_group_id'])
        return aggdf
    except Exception, e:
        print (
            '{ts} Uh oh, something went wrong trying to aggregate '
            'location_id: {lid}, year: {y}, sex: {s}. Error: {e}'.format(
                ts=pretty_now(), lid=parent_loc, y=year, s=sex, e=str(e)))
        return (500, str(e))


def aggregate_all_locations_mp(
        drawdir,
        stagedir,
        location_set_id,
        index_cols,
        years=[1990, 1995, 2000, 2005, 2010, 2015],
        sexes=[1, 2],
        include_leaves=False,
        operator='wtd_sum',
        custom_file_pattern=None,
        h5_tablename=None,
        single_file=True):

    from multiprocessing import Pool

    if custom_file_pattern:
        specs_to_try = [{
            'file_pattern': custom_file_pattern,
            'h5_tablename': h5_tablename}]
    else:
        specs_to_try = super_gopher.known_specs[0:2]
    sgs = []
    for s in specs_to_try:
        try:
            sgs.append(super_gopher.SuperGopher(s, drawdir))
        except Exception:
            pass
    assert len(sgs) > 0, (
        "%s Could not find files matching known file specs in %s" %
        (pretty_now(), drawdir))

    # Call get_pop once to cache result
    print '%s Caching population' % pretty_now()
    global pop
    pop = get_pop()
    print '%s Population cached' % pretty_now()
    lsvid = dbtrees.get_location_set_version_id(location_set_id)
    lt = dbtrees.loctree(lsvid)
    depth = lt.max_depth()-1
    pool = Pool(10)

    outfile = "%s/all_draws.h5" % stagedir
    while depth >= 0:
        maplist = []
        for parent_loc in lt.level_n_descendants(depth):
            this_include_leaves = include_leaves
            if len(parent_loc.children) > 0:
                for year in years:
                    for sex in sexes:
                        maplist.append(
                            ((
                                drawdir, lt,
                                parent_loc.id, year, sex, index_cols, sgs,
                                this_include_leaves, operator),
                                {'single_file': True}))
        res = pool.map(aclw_mp, maplist)
        if len([r for r in res if isinstance(r, tuple)]) > 0:
            print (
                "%s !!!! SAVE RESULTS FAILED !!!! Looks like there were "
                "errors in aggregation. See the 'uh ohs' above""" %
                pretty_now())
            if single_file:
                shutil.rmtree(stagedir)
            sys.exit()

        res = pd.concat(res)
        for col in [
                'measure_id', 'location_id', 'year_id', 'age_group_id',
                'sex_id']:
            res[col] = res[col].astype(int)
        print '%s Writing depth: %s' % (pretty_now(), depth)
        if single_file:
            if not os.path.isfile(outfile):
                res.to_hdf(
                    outfile, 'draws', mode='w', format='table',
                    data_columns=[
                        'measure_id', 'location_id', 'year_id', 'age_group_id',
                        'sex_id'])
                sgs.append(super_gopher.SuperGopher({
                    'file_pattern': 'all_draws.h5',
                    'h5_tablename': 'draws'}, stagedir))
            else:
                hdfs = pd.HDFStore(outfile)
                hdfs.append('draws', res)
                hdfs.close()
        else:
            for l in res.location_id.unique():
                for y in res.year_id.unique():
                    for s in res.sex_id.unique():
                        filepath = '{sd}/{l}_{y}_{s}.h5'.format(
                                sd=stagedir, l=l, y=y, s=s)
                        res.query(
                            "location_id=={l} & year_id=={y} & "
                            "sex_id=={s}".format(l=l, y=y, s=s)).to_hdf(
                                    filepath, 'draws', mode='w',
                                    format='table', complib='zlib',
                                    data_columns=[
                                        'measure_id', 'age_group_id'])
        depth = depth-1
    pool.close()
    pool.join()
    return lsvid


def aggregate_mvid(
        model_version_id, env='dev', custom_file_pattern='all_draws.h5',
        h5_tablename='draws', single_file=True, odbc_filepath='~/.odbc.ini',
        mark_best=False, best_description="auto-marked best"):
    try:
        if env == 'dev':
            db = EpiDB('epi-dev-custom', odbc_filepath=odbc_filepath)
        elif env == 'prod':
            db = EpiDB('epi', odbc_filepath=odbc_filepath)
        elif 'cascade' in env:
            db = EpiDB('epi-cascade', odbc_filepath=odbc_filepath)
            env = env.split("-")[1]
        else:
            raise Exception(
                    "Only dev/prod/cascade-dev/cascade-prod "
                    "environments are supported")
    except Exception, e:
        print """Could not initialize ODBC connection. Are you sure you
            have properly configured you ~/.odbc.ini file?"""
        raise e

    drawdir = '/ihme/epi/panda_cascade/%s/%s/full/draws' % (
            env, model_version_id)
    aggregate_all_locations_mp(
       drawdir, drawdir, 35,
       ['year_id', 'age_group_id', 'sex_id', 'measure_id'],
       custom_file_pattern=custom_file_pattern, h5_tablename=h5_tablename,
       single_file=single_file)

    # Summarize
    print "%s Creating summaries" % pretty_now()
    summarizers.launch_summaries(
        model_version_id, env, file_pattern=custom_file_pattern,
        h5_tablename=h5_tablename)

    print "%s Uploading summaries" % pretty_now()
    db.upload_summaries(
        "/ihme/epi/panda_cascade/%s/"
        "%s/full/summaries/model_estimate_final.csv" % (env, model_version_id),
        model_version_id)
    print "%s Upload complete" % pretty_now()

    # Mark complete
    db.update_status(model_version_id, 1)

    # Mark best
    if mark_best:
        meid = db.get_meid_from_mv(model_version_id)
        db.unmark_current_best(meid)
        db.mark_best(model_version_id, best_description)


def save_custom_results(
        meid,
        description,
        input_dir,
        years=[1990, 1995, 2000, 2005, 2010, 2015],
        sexes=[1, 2],
        mark_best=False,
        in_counts=False,
        env='dev',
        custom_file_pattern=None,
        h5_tablename=None):

    if in_counts:
        operator = 'sum'
    else:
        operator = 'wtd_sum'

    print "========================================="
    print "%s Beginning save_results" % pretty_now()
    try:
        if env == 'dev':
            db = EpiDB('epi-dev-custom')
        elif env == 'prod':
            db = EpiDB('epi')
        else:
            raise Exception("Only dev or prod environments are supported")
    except Exception, e:
        print """Could not initialize ODBC connection. Are you sure you
            have properly configured you ~/.odbc.ini file?"""
        raise e

    # Check quotas
    if db.get_model_quota_available(meid) <= 0:
        print (
            "%s FAILED! The model quota for this modelable_entity has already "
            "been reached. Please delete one of your existing models "
            "and try again." % pretty_now())
        print "========================================="
        sys.exit()

    # Setup directories
    drawdir = input_dir
    stagedir = str(uuid.uuid4())
    stagedir = '/ihme/centralcomp/scratch/save_results_stage/%s' % stagedir
    try:
        os.makedirs(stagedir)
    except:
        pass

    # Aggregate
    lsvid = aggregate_all_locations_mp(
       drawdir, stagedir, 35,
       ['year_id', 'age_group_id', 'sex_id', 'measure_id'], years, sexes, True,
       operator, custom_file_pattern=custom_file_pattern,
       h5_tablename=h5_tablename)

    # Create model_version
    print "%s Creating model_version" % pretty_now()
    mvid = db.create_model_version(
            meid,
            '%s' % description,
            lsvid)
    shutil.move(
        '%s/all_draws.h5' % stagedir,
        '/ihme/epi/panda_cascade/%s/%s/full/draws' % (env, mvid))
    os.rmdir(stagedir)

    # Summarize
    print "%s Creating summaries" % pretty_now()
    summarizers.launch_summaries(mvid, env, years)

    print "%s Uploading summaries" % pretty_now()
    db.upload_summaries(
        "/ihme/epi/panda_cascade/%s/"
        "%s/full/summaries/model_estimate_final.csv" % (env, mvid), mvid)
    print "%s Uploaded complete. New model_version_id=%s." % (
        pretty_now(), mvid)

    # Mark complete
    db.update_status(mvid, 1)

    # Mark best
    if mark_best:
        db.unmark_current_best(meid)
        db.mark_best(mvid, 'flagged to mark_best in save_results')

    print "%s save_results complete!" % pretty_now()
    print "========================================="


def qwriter(outq, outfile, h5key, data_cols):
    store = pd.HDFStore(outfile)
    for dftup in iter(outq.get, sentinel):
        store.put(
            h5key, dftup[0], format='table', append=True,
            data_columns=data_cols)
    store.close()


def qaggregator(inq):
    for params in iter(inq.get, sentinel):
        try:
            (stagedir, measure_id, drawdir, lt, parent_loc, year,
                sex, index_cols, sgs, this_include_leaves,
                operator, chunksize) = params
            df = aggregate_child_locs(
                    *params[2:-1],
                    force_lowmem=True,
                    draw_filters={'measure_id': measure_id},
                    chunksize=chunksize)
            sg = sgs[0]
            for meas_id in df.measure_id.unique():
                wdf = df[df.measure_id == meas_id]
                cols = list(set(wdf.columns) & set(sg.file_columns))
                wdf = wdf[cols]
                fn = '{sd}/{m}_{l}_{y}_{s}.h5'.format(
                    sd=stagedir, m=meas_id, l=parent_loc, y=year, s=sex)
                wdf.to_hdf(
                    fn,
                    'draws',
                    mode='w',
                    format='table',
                    data_columns=sg.index_cols)
            inq.task_done()
        except Exception as e:
            print e, params
            inq.task_done()


def agg_all_locs_mem_eff(
        drawdir,
        stagedir,
        location_set_id,
        index_cols,
        year,
        sex,
        measure_id,
        include_leaves=False,
        operator='wtd_sum',
        custom_file_pattern='{measure_id}_{location_id}_{year_id}_{sex_id}.h5',
        h5_tablename='draws'):

    from multiprocessing import Process, JoinableQueue

    if custom_file_pattern:
        specs_to_try = [{
            'file_pattern': custom_file_pattern,
            'h5_tablename': h5_tablename}]
    else:
        specs_to_try = super_gopher.known_specs[0:2]
    sgs = []
    for s in specs_to_try:
        try:
            sgs.append(super_gopher.SuperGopher(s, drawdir))
        except Exception:
            pass
    assert len(sgs) > 0, (
        "%s Could not find files matching known file specs in %s" %
        (pretty_now(), drawdir))

    # Call get_pop once to cache result
    print '%s Caching population' % pretty_now()
    global pop
    pop = get_pop()
    print '%s Population cached' % pretty_now()
    lsvid = dbtrees.get_location_set_version_id(location_set_id)

    try:
        lt = dbtrees.loctree(lsvid)
        lts = [lt]
        chunksize = 2
    except:
        lts = dbtrees.loctree(lsvid, return_many=True)
        chunksize = 30

    for lt in lts:
        depth = lt.max_depth()-1

        inq = JoinableQueue()
        pool = [Process(target=qaggregator, args=(inq,)) for i in range(21)]
        for p in pool:
            p.start()

        while depth >= 0:
            print '%s Aggregating depth: %s' % (pretty_now(), depth)
            for parent_loc in lt.level_n_descendants(depth):
                this_include_leaves = include_leaves
                if len(parent_loc.children) > 0:
                    inq.put((
                        stagedir, measure_id, drawdir, lt,
                        parent_loc.id, year, sex, index_cols, sgs,
                        this_include_leaves, operator, chunksize))
            inq.join()
            if depth == lt.max_depth()-1:
                sgs.append(super_gopher.SuperGopher({
                    'file_pattern': custom_file_pattern,
                    'h5_tablename': h5_tablename}, stagedir))
            depth = depth-1
        for p in pool:
            inq.put(sentinel)
    return lsvid
