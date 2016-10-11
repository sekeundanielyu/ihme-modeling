from adding_machine.super_gopher import SuperGopher
from adding_machine.summarizers import get_pop
from como.version import ComoVersion
import os
import pandas as pd
from hierarchies import dbtrees
from multiprocessing import Pool
import rpy2.robjects as robjects
from rpy2.robjects.packages import importr


def setup_env(como_version_id):
    global cv, simdir, pooldir, sg
    cv = ComoVersion(como_version_id)
    simdir = os.path.join(cv.root_dir, 'simulants')
    pooldir = os.path.join(cv.root_dir, 'locsims')
    try:
        os.makedirs(pooldir)
    except:
        pass
    sg = SuperGopher({
        'file_pattern': 'sims_{location_id}_{year_id}_{sex_id}.h5',
        'h5_tablename': 'draws'}, simdir)


def mix_age_sex(lid, yid, sample_size=100000):
    sims = sg.content(skip_refresh=True, location_id=lid, year_id=yid)
    sims = sims[[
        'location_id', 'year_id', 'age_group_id', 'sex_id', 'dw_mean']]
    ages = list(sims.age_group_id.unique())
    sexes = list(sims.sex_id.unique())
    pops = get_pop({
        'location_id': lid, 'year_id': yid, 'sex_id': sexes,
        'age_group_id': ages})
    pops['prop'] = pops.pop_scaled / pops.pop_scaled.sum()
    pops['nsamples'] = pops.prop.apply(
            lambda x: int(round(x*sample_size)))

    print 'Sims retrieved for %s' % lid
    subsample = []
    for i, row in pops.iterrows():
        nsims = row['nsamples']
        age = row['age_group_id']
        sex = row['sex_id']
        rsims = sims[
                (sims.age_group_id == age) &
                (sims.sex_id == sex)].sample(nsims, replace=True)
        subsample.append(rsims)
    subsample = pd.concat(subsample)
    subsample['age_group_id'] = 22
    subsample['sex_id'] = 3
    return subsample


def as_wrapper(args):
    nsims, l, yid, outdir = args
    try:
        print 'Sampling %s %s...' % (l, yid)
        ss = mix_age_sex(l, yid).sample(nsims, replace=True)
        ss.reset_index(drop=True, inplace=True)
        ss.to_hdf("{od}/{l}_{y}.h5".format(
            od=outdir, l=l, y=yid), 'sims', mode='w')
        print 'Sampled %s' % l
    except Exception, e:
        print e
        print 'Failed sampling %s' % l
        return None


def mix_locations(args):
    lid, yid, sample_size = args
    lt = dbtrees.loctree(None, 35)
    lids = [l.id for l in lt.get_node_by_id(lid).children]
    pops = get_pop({
        'location_id': lids, 'year_id': yid, 'sex_id': 3, 'age_group_id': 22})
    pops['prop'] = pops.pop_scaled / pops.pop_scaled.sum()
    pops['nsamples'] = pops.prop.apply(
            lambda x: int(round(x*sample_size)))

    subsample = []
    for i, row in pops.iterrows():
        l = int(row['location_id'])
        nsims = row['nsamples']
        try:
            ss = pd.read_hdf('{pd}/{l}_{y}.h5'.format(pd=pooldir, l=l, y=yid))
            ss = ss.sample(nsims, replace=True)
            subsample.append(ss)
        except:
            print 'issue with %s' % l
    subsample = pd.concat(subsample)
    subsample.reset_index(drop=True, inplace=True)
    subsample.to_hdf("{od}/{l}_{y}.h5".format(
        od=pooldir, l=lid, y=yid), 'sims', mode='w')


def write_agg_files(lid, cvid):
    setup_env(cvid)
    arglist = [(lid, y, 100000)
               for y in range(1990, 2016, 5)]
    pool = Pool(6)
    pool.map(mix_locations, arglist)
    pool.close()
    pool.join()


def write_leaf_files(lid, cvid):
    setup_env(cvid)
    arglist = [(100000, lid, y, pooldir)
               for y in range(1990, 2016, 5)]
    pool = Pool(6)
    pool.map(as_wrapper, arglist)
    pool.close()
    pool.join()


def calc_gini(cvid, lid, yid, invert=True):
    setup_env(cvid)
    ss = pd.read_hdf('{pd}/{l}_{y}.h5'.format(pd=pooldir, l=lid, y=yid))
    if invert:
        ss['dw_mean'] = 1 - ss.dw_mean
    importr('reldist')
    gini = robjects.r['gini']
    ss_dws = robjects.FloatVector(ss.dw_mean)
    gc = gini(ss_dws)[0]
    return gc
