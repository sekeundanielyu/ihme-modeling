from db import query
import numpy as np
import pandas as pd
from config import settings
import os
from glob import glob
import gopher
import maths
from hierarchies import dbtrees
from risk_utils.draws import custom_draws


def _multi_file_draws(
        meid, mvid, draw_dir, lids=[], yids=[], sids=[],
        meas_ids=[], ag_ids=[], verbose=True):
    """
    Returns the draws for the given modelable_entity_id (meid),
    location_id (lid), year_id (yid), sex_id (sid), measure_ids
    (meas_ids), and age_group_ids (ag_ids)

    Arguments:
        meid (int): ID of the modelable entity to be retrieved
        mvid (int): model_version_id of the modelable entity to be retrieved
        draw_dir (int): draws directory of the modelable entity to be retrieved
        lids ([] or list of ints): A list of location_ids
        sids ([] or list of ints): A list of sex_ids
        meas_ids ([] or list of ints): A list of measure_ids to
                retrieve, or the empty list to return all available
                measure_ids
        ag_ids ([] or list of ints): A list of age_group_ids to
                retrieve, or the empty list to return all available
                age_group_ids
        verbose (boolean): Print progress updates

    Returns:
        Draws as a DataFrame
    """
    yids = list(np.atleast_1d(yids))
    lids = list(np.atleast_1d(lids))
    sids = list(np.atleast_1d(sids))
    meas_ids = list(np.atleast_1d(meas_ids))
    ag_ids = list(np.atleast_1d(ag_ids))

    if not lids:
        all_files = glob('%s/*.h5' % draw_dir)
        all_files = [os.path.basename(f) for f in all_files]
        lids = [int(l.split("_")[0]) for l in all_files]
        lids = list(set(lids))
    if not yids:
        yids = range(1990, 2016, 5)
    if not sids:
        sids = [1, 2]

    epi_measures = set([5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17,
                        18, 19, 20])
    epi_measures = set(meas_ids) & epi_measures

    # Define measure and age filters
    where = []
    if meas_ids:
        where.append('measure_id in [%s]' % ",".join(
            [str(m) for m in meas_ids]))
    if ag_ids:
        where.append('age_group_id in [%s]' % ",".join(
            [str(a) for a in ag_ids]))
    where = " & ".join(where)
    draws = []
    nfiles = len(lids)*len(yids)*len(sids)
    i = 0
    for lid in lids:
        for yid in yids:
            for sid in sids:
                i += 1
                f = '%s/%s_%s_%s.h5' % (draw_dir, lid, yid, sid)
                if verbose:
                    print 'Opening %s' % f
                    print '%s of %s files (%s)' % (
                        i, nfiles, "{:.1%}".format(i/nfiles))
                try:
                    if where == '':
                        this_draws = pd.read_hdf(f, 'draws')
                    else:
                        this_draws = pd.read_hdf(f, 'draws', where=where)
                except IOError as e:
                    this_draws = custom_draws(mvid, 'exposure', lids=[lid],
                                             yids=[yid], sids=[sid],
                                             ag_ids=ag_ids, meas_ids=meas_ids,
                                             verbose=False)
                draws.append(this_draws)

    draws = pd.concat(draws)
    draws['modelable_entity_id'] = meid
    draws['model_version_id'] = mvid
    return draws


def _single_file_draws(
        meid, mvid, draw_dir, lids=[], yids=[], sids=[],
        meas_ids=[], ag_ids=[]):
    """
    Returns the draws for the given modelable_entity_id (meid),
    location_id (lid), year_id (yid), sex_id (sid), measure_ids
    (meas_ids), and age_group_ids (ag_ids)

    Arguments:
        meid (int): ID of the modelable entity to be retrieved
        mvid (int): model_version_id of the modelable entity to be retrieved
        draw_dir (int): draws directory of the modelable entity to be retrieved
        lids ('all' or list of ints): A list of location_ids
        sids ('all' or list of ints): A list of sex_ids
        meas_ids ('all' or list of ints): A list of measure_ids to
                retrieve, or the string 'all' to return all available
                measure_ids
        ag_ids ('all' or list of ints): A list of age_group_ids to
                retrieve, or the string 'all' to return all available
                age_group_ids
        status ('best' or 'latest'): Defaults to 'best,' determines
                whether the best or most recent model is returned

    Returns:
        Draws as a DataFrame
    """
    yids = list(np.atleast_1d(yids))
    lids = list(np.atleast_1d(lids))
    sids = list(np.atleast_1d(sids))
    meas_ids = list(np.atleast_1d(meas_ids))
    ag_ids = list(np.atleast_1d(ag_ids))

    # Define measure and age filters
    where = []
    if lids:
        where.append('location_id in [%s]' % ",".join(
            [str(m) for m in lids]))
    if yids:
        where.append('year_id in [%s]' % ",".join(
            [str(m) for m in yids]))
    if sids:
        where.append('sex_id in [%s]' % ",".join(
            [str(m) for m in sids]))
    if meas_ids:
        where.append('measure_id in [%s]' % ",".join(
            [str(m) for m in meas_ids]))
    if ag_ids:
        where.append('age_group_id in [%s]' % ",".join(
            [str(a) for a in ag_ids]))
    where = " & ".join(where)

    f = '%s/all_draws.h5' % (draw_dir)
    if where == '':
        draws = pd.read_hdf(f, 'draws')
    else:
        draws = pd.read_hdf(f, 'draws', where=where)
    draws['modelable_entity_id'] = meid
    draws['model_version_id'] = mvid
    return draws


def version_id(modelable_entity_id=None, sequela_id=None, status='best'):
    """ Returns the best/latest version id for the given epi id """

    id_args = [modelable_entity_id, sequela_id]
    assert len([i for i in id_args if i is not None]) == 1, '''
        Must specificy one and only one of the id arguments: meid or
        sequela_id'''

    if modelable_entity_id is not None:
        server = 'epi'
        db = 'epi'
        filter_col = 'modelable_entity_id'
        id = modelable_entity_id
        sf = 'AND model_version_status_id=1'
        if status == 'best':
            v_filter = 'AND is_best=1'
        elif status == 'latest':
            v_filter = 'ORDER BY date_inserted DESC LIMIT 1'

    table = 'model_version'
    q = '''
        SELECT model_version_id FROM {db}.{t}
        WHERE {fc}={id}
        {sf}
        {vf}'''.format(db=db, t=table, fc=filter_col, id=id, sf=sf,
                       vf=v_filter)
    version_id = query(server, q)
    if len(version_id) > 0:
        return version_id.model_version_id.tolist()
    else:
        return None


def draws(
        meid, lids=[], yids=[], sids=[], meas_ids=[], ag_ids=[],
        status='best', verbose=True):
    """
    Returns the draws for the given modelable_entity_id (meid),
    location_id (lid), year_id (yid), sex_id (sid), measure_ids
    (meas_ids), and age_group_ids (ag_ids)

    Arguments:
        meid (int): ID of the modelable entity to be retrieved
        lids ([] or list of ints): A list of location_ids
        sids ([] or list of ints): A list of sex_ids
        meas_ids ([] or list of ints): A list of measure_ids to
                retrieve, or the empty list to return all available
                measure_ids
        ag_ids ([] or list of ints): A list of age_group_ids to
                retrieve, or the empty list to return all available
                age_group_ids
        status ('best', 'latest', or integer): Defaults to 'best,'
                determines whether the best, most recent,
                or an explicit model version is returned
        verbose (boolean): Print progress updates

    Returns:
        Draws as a DataFrame
    """
    if isinstance(status, (int, long)):
        mvid = status
    else:
        mvid = version_id(modelable_entity_id=meid, status=status)[0]
    assert mvid is not None, '''No %s model for meid:%s and
        mvid:%s''' % (status, meid, mvid)
    draw_dir = '%s/%s/full/draws' % (settings['epi_root_dir'], mvid)
    if os.path.isfile('%s/all_draws.h5' % draw_dir):
        return _single_file_draws(
                meid, mvid, draw_dir, lids=lids, yids=yids, sids=sids,
                meas_ids=meas_ids, ag_ids=ag_ids)
    else:
        return _multi_file_draws(
                meid, mvid, draw_dir, lids=lids, yids=yids, sids=sids,
                meas_ids=meas_ids, ag_ids=ag_ids, verbose=verbose)


def filet(source_meid, target_prop_map, location_id, split_meas_ids=[5, 6],
          prop_meas_id=18):
    """
    Splits the draws for source_meid to the target meids supplied
    in target_prop_map by the proportions estimated in the prop_meids. The
    split is applied for all GBD years 1990-2015 for the specified
    location_id. The 'best' version of the meids will be used by default.

    Arguments:
        source_meid (int): meid for the draws to be split
        target_prop_map (dict): dictionary whose keys are the target
                meids and whose values are the meids for the
                corresponding proportion models
        location_id (int): location_id to operate on

    Returns:
        A DataFrame containing the draws for the target meids
    """

    drawcols = ['draw_%s' % i for i in range(1000)]
    splits = []
    props = gopher.draws(
                {'modelable_entity_ids': target_prop_map.values()},
                'dismod',
                measure_ids=prop_meas_id,
                location_ids=location_id,
                status='best',
                verbose=True)
    props['target_modelable_entity_id'] = (
            props.modelable_entity_id.replace(
                {v: k for k, v in target_prop_map.iteritems()}))
    for measure_id in split_meas_ids:
        source = gopher.draws(
                    {'modelable_entity_ids': [source_meid]},
                    'dismod',
                    measure_ids=[measure_id],
                    location_ids=location_id,
                    status='best',
                    verbose=True)
        props['measure_id'] = measure_id
        props = props[props.age_group_id.isin(source.age_group_id.unique())]
        props = props[props.sex_id.isin(source.sex_id.unique())]

        if len(source) > 0 and len(props) > 0:
            if len(target_prop_map) > 1:
                force_scale = True
            else:
                force_scale = False
            split = maths.merge_split(
                    source,
                    props,
                    ['year_id', 'age_group_id', 'sex_id', 'location_id'],
                    drawcols,
                    force_scale=force_scale)
            splits.append(split)
        else:
            pass
    splits = pd.concat(splits)
    splits = splits[[
        'location_id', 'year_id', 'age_group_id', 'sex_id', 'measure_id',
        'target_modelable_entity_id']+drawcols]
    splits.rename(
            columns={'target_modelable_entity_id': 'modelable_entity_id'},
            inplace=True)
    return splits


def split_n_write(args):
    source, targets, loc, split_meas_ids, prop_meas_id, output_dir = args
    try:
        res = filet(source, targets, loc, split_meas_ids, prop_meas_id)
        drawcols = ['draw_%s' % d for d in range(1000)]
        idxcols = ['location_id', 'year_id', 'age_group_id', 'sex_id',
                   'measure_id']
        for meid in res.modelable_entity_id.unique():
            meid_dir = '%s/%s' % (output_dir, meid)
            meid_dir = meid_dir.replace("\r", "")
            try:
                os.makedirs(meid_dir)
            except:
                pass
            fn = '%s/%s.h5' % (meid_dir, loc)
            tw = res.query("modelable_entity_id==%s" % meid)[idxcols+drawcols]
            tw.to_hdf(fn, 'draws', mode='w', format='table',
                      data_columns=idxcols)
        return (loc, 0)
    except Exception, e:
        return (loc, str(e))


def launch_epi_splits(
        source_meid, target_meids, prop_meids, split_meas_ids, prop_meas_id,
        output_dir):

    from multiprocessing import Pool

    meme_map = dict(zip(target_meids, prop_meids))
    lt = dbtrees.loctree(None, location_set_id=35)
    leaf_ids = [l.id for l in lt.leaves()]

    params = []
    for lid in leaf_ids:
        params.append((source_meid, meme_map, lid, split_meas_ids,
                       prop_meas_id, output_dir))

    pool = Pool(30)
    res = pool.map(split_n_write, params)
    pool.close()
    return res


if __name__ == "__main__":
    import argparse

    def all_parser(s):
        try:
            s = int(s)
            return s
        except:
            return s
    parser = argparse.ArgumentParser(description='Split a parent epi model')
    parser.add_argument('source_meid', type=int)
    parser.add_argument('--target_meids', type=all_parser, nargs="*")
    parser.add_argument('--prop_meids', type=all_parser, nargs="*")
    parser.add_argument(
            '--split_meas_ids',
            type=all_parser,
            nargs="*",
            default=[5, 6])
    parser.add_argument('--prop_meas_id', type=int, default=18)
    parser.add_argument(
        '--output_dir',
        type=str,
        default="/ihme/gbd/WORK/10_gbd/00_library/epi_splits_sp")
    args = vars(parser.parse_args())

    try:
        os.makedirs(args['output_dir'])
    except:
        pass

    res = launch_epi_splits(
        args['source_meid'],
        args['target_meids'],
        args['prop_meids'],
        args['split_meas_ids'],
        args['prop_meas_id'],
        args['output_dir'])
    errors = [r for r in res if r[1] != 0]

    if len(errors) == 0:
        print 'Splits successful!'
    else:
        logfile = '%s/%s_errors.log' % (
                args['output_dir'], args['source_meid'])
        with open(logfile, 'w') as f:
            estr = "\n".join([str(r) for r in errors])
            f.write(estr)
        print (
            'Uh, oh. Something went wrong. Check the log file for details: '
            '%s' % logfile)
