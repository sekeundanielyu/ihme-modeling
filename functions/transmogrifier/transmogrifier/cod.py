import pandas as pd
import gopher
import epi
import maths
import os
from hierarchies import dbtrees


def filet(source_cause_id, cause_meid_map, location_id):
    """
    Splits the draws for source_cause_id to the target causes supplied
    in cause_meid_map by the proportions estimated in the meids. The
    split is applied for all years 1990-2015 for the specified
    location_id. The 'best' version of the source cause and meids
    will be used by default.

    Arguments:
        source_cause_id (int): cause_id for the draws to be split
        cause_meid_map (dict): dictionary whose keys are the target
                cause_ids and whose values are the meids for the
                corresponding proportion models
        location_id (int): location_id to operate on

    Returns:
        A DataFrame containing the draws for the target causes
    """

    start_year = 1980
    epi_start_year = 1990
    end_year = 2015
    rank_year = 2005

    # Retrieve epi draws and interpolate
    epi_draws = []
    for meid in cause_meid_map.values():
        for y in range(epi_start_year, end_year+1, 5):
            d = epi.draws(meid, yids=y, lids=location_id, meas_ids=18,
                          verbose=False)
            assert len(d) > 0, (
                "Uh oh, couldn't find epi draws. Make sure you have "
                "proportion estimates for the supplied meids")
            epi_draws.append(d)
    epi_draws = pd.concat(epi_draws)
    ip_epi_draws = []
    for y in range(epi_start_year, end_year, 5):
        sy = y
        ey = y+5
        ip_draws = maths.interpolate(
                epi_draws.query('year_id==%s' % sy),
                epi_draws.query('year_id==%s' % ey),
                ['age_group_id', 'model_version_id', 'sex_id'],
                'year_id',
                ['draw_%s' % i for i in range(1000)],
                sy,
                ey,
                rank_df=epi_draws.query('year_id==%s' % rank_year))
        if ey != end_year:
            ip_draws = ip_draws[ip_draws.year_id != ey]
        ip_epi_draws.append(ip_draws)
    ip_epi_draws = pd.concat(ip_epi_draws)
    extrap_draws = []
    for y in range(start_year, epi_start_year):
        esy_draws = ip_epi_draws.query('year_id==%s' % epi_start_year)
        esy_draws['year_id'] = y
        extrap_draws.append(esy_draws)
    epi_draws = pd.concat([ip_epi_draws]+extrap_draws)

    # Retrieve cod draws and split
    cd = gopher.cod_draws(
            source_cause_id, lids=location_id,
            yids=range(start_year, end_year+1))
    epi_draws = epi_draws[
            epi_draws.age_group_id.isin(cd.age_group_id.unique())]
    cout = maths.merge_split(
            cd, epi_draws,
            ['year_id', 'age_group_id', 'sex_id', 'location_id'],
            ['draw_%s' % i for i in range(1000)])

    cout = cout.merge(
            cd[['year_id', 'age_group_id', 'sex_id', 'location_id',
                'pop', 'envelope']],
            how='left')
    meid_cause_map = {v: k for k, v in cause_meid_map.iteritems()}
    cout['cause_id'] = cout.modelable_entity_id
    cout['cause_id'] = cout.cause_id.replace(meid_cause_map)
    return cout


def split_n_write(args):
    source, targets, loc, output_dir = args
    try:
        c = filet(source, targets, loc)
        for y in c.year_id.unique():
            for s in c.sex_id.unique():
                for cid in c.cause_id.unique():
                    cid_dir = '%s/%s' % (output_dir, cid)
                    cid_dir = cid_dir.replace("\r", "")
                    try:
                        os.makedirs(cid_dir)
                    except:
                        pass
                    fn = '%s/death_%s_%s_%s.csv' % (
                            cid_dir, loc, y, s)
                    c.query('''year_id==%s & sex_id==%s & cause_id==%s'''
                            % (y, s, cid)).to_csv(fn, index=False)
        return (loc, 0)
    except Exception, e:
        return (loc, str(e))


def launch_cod_splits(
        source_cause_id, target_cause_ids, target_meids, output_dir):

    from multiprocessing import Pool

    cme_map = dict(zip(target_cause_ids, target_meids))
    lt = dbtrees.loctree(None, location_set_id=35)
    leaf_ids = [l.id for l in lt.leaves()]

    params = []
    for lid in leaf_ids:
        params.append((source_cause_id, cme_map, lid, output_dir))

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
    parser = argparse.ArgumentParser(description='Split a parent cod model')
    parser.add_argument('source_cause_id', type=int)
    parser.add_argument('--target_cause_ids', type=all_parser, nargs="*")
    parser.add_argument('--target_meids', type=all_parser, nargs="*")
    parser.add_argument(
        '--output_dir',
        type=str,
        default="/ihme/gbd/WORK/10_gbd/00_library/cod_splits_sp")
    args = vars(parser.parse_args())

    try:
        os.makedirs(args['output_dir'])
    except:
        pass

    res = launch_cod_splits(
        args['source_cause_id'],
        args['target_cause_ids'],
        args['target_meids'],
        args['output_dir'])
    errors = [r for r in res if r[1] != 0]

    if len(errors) == 0:
        print 'Splits successful!'
    else:
        logfile = '%s/%s_errors.log' % (
                args['output_dir'], args['source_cause_id'])
        with open(logfile, 'w') as f:
            estr = "\n".join([str(r) for r in errors])
            f.write(estr)
        print (
            'Uh, oh. Something went wrong. Check the log file for details: '
            '%s' % logfile)
