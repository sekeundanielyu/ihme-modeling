import pandas as pd
from transmogrifier import maths
from hierarchies import dbtrees
from multiprocessing import Pool
import os


def interpolate_ls(cvid, lid, sid):
    modys = range(1990, 2016, 5)
    iplys = [y for y in range(1990, 2016) if y not in modys]
    idir = '/ihme/centralcomp/como/{cv}/draws/cause/total_interp/'.format(
            cv=cvid)
    try:
        os.makedirs(idir)
    except:
        pass

    moddfs = []
    for y in modys:
        moddfs.append(pd.read_hdf(
            '/ihme/centralcomp/como/{cv}/draws/cause/total/'
            '3_{l}_{y}_{s}.h5'.format(cv=cvid, l=lid, y=y, s=sid)))
    moddfs = pd.concat(moddfs)

    for i in range(len(modys)-1):
        sy = modys[i]
        ey = modys[i+1]
        print 'interpolating %s %s %s %s' % (lid, sid, sy, ey)
        id_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id',
                   'cause_id']
        time_col = 'year_id'
        value_cols = ['draw_%s' % d for d in range(1000)]

        x = maths.interpolate(
                moddfs.query('year_id == %s' % sy),
                moddfs.query('year_id == %s' % ey),
                id_cols,
                time_col,
                value_cols,
                sy,
                ey,
                rank_df=moddfs.query('year_id == 2005'))
        x = x[x.year_id.isin(iplys)]
        for y in x.year_id.unique():
            fn = '{id}/3_{l}_{y}_{s}.h5'.format(id=idir, l=lid, y=y, s=sid)
            x.query('year_id == %s' % y).to_hdf(
                fn,
                'draws',
                mode='w',
                format='table',
                data_columns=id_cols)


def iwrap(args):
    try:
        interpolate_ls(*args)
    except Exception, e:
        print e


if __name__ == "__main__":
    import sys
    cvid = sys.argv[1]
    locs = [n.id for n in dbtrees.loctree(None, 35).nodes]
    args = [(cvid, l, s) for l in locs for s in [1, 2]]
    pool = Pool(20)
    pool.map(iwrap, args)
    pool.close()
    pool.join()
