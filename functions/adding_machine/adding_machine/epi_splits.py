from hierarchies import dbtrees
from transmogrifier import gopher, maths
import pandas as pd
import numpy as np
from itertools import cycle
from db import EpiDB
from multiprocessing import Queue, Process
from . import git_info


edb = EpiDB()
engine = edb.get_engine('epi')
sentinel = None


class SevSplitter(object):

    def __init__(self, parent_meid, prop_drawfile=None):
        self.parent_meid = parent_meid
        self.lt = dbtrees.loctree(None, location_set_id=35)
        self.ags = self.age_groups()
        self.child_meids = self.get_children()
        if prop_drawfile is None:
            self.props = self.get_split_proportions()
            self.props = self.gen_proportion_draws()
        else:
            self.props = pd.read_csv(prop_drawfile)

    def get_children(self):
        q = """
            SELECT parent_meid, child_meid
            FROM severity_splits.hierarchy h
            JOIN severity_splits.hierarchy_version hv
                ON (h.hierarchy_version_id = hv.id)
            WHERE is_best=1 AND parent_meid=%s""" % self.parent_meid
        return pd.read_sql(q, engine)

    def get_split_proportions(self):
        q = """
            SELECT hierarchy_version_id, proportion_version_id, parent_meid,
                child_meid, draw_generation_seed, location_id, year_start,
                year_end, age_start, age_end, sex_id, distribution_type, mean,
                lower, upper
            FROM severity_splits.proportion p
            JOIN severity_splits.proportion_version pv
                ON (p.proportion_version_id = pv.id)
            JOIN severity_splits.hierarchy h
                ON (p.hierarchy_id = h.id)
            JOIN severity_splits.hierarchy_version hv
                ON (h.hierarchy_version_id = hv.id)
            WHERE hv.is_best=1
            AND pv.is_best=1
            AND parent_meid=%s""" % self.parent_meid
        return pd.read_sql(q, engine)

    def gen_proportion_draws(self):
        return self.draw_beta()

    def draw_beta(self):
        seed = self.props.draw_generation_seed.unique()[0]
        np.random.seed(seed)
        sd = (self.props['upper']-self.props['lower'])/(2*1.96)
        sample_size = self.props['mean']*(1-self.props['mean'])/sd**2
        alpha = self.props['mean']*sample_size
        alpha = alpha.replace({0: np.nan})
        beta = (1-self.props['mean'])*sample_size
        beta = beta.replace({0: np.nan})
        draws = np.random.beta(alpha, beta, size=(1000, len(alpha)))
        draws = pd.DataFrame(
                draws.T,
                index=self.props.index,
                columns=['draw_%s' % i for i in range(1000)])
        draws = draws.fillna({
            'draw_%s' % i: self.props['mean'] for i in range(1000)})
        return self.props.join(draws)

    def draw_normal():
        pass

    def age_groups(self):
        q = """
            SELECT age_group_id, age_group_years_start, age_group_years_end
            FROM shared.age_group
            JOIN shared.age_group_set_list USING(age_group_id)
            WHERE age_group_set_id=1"""
        return pd.read_sql(q, engine)

    def gbdize_proportions(self, location_id):
        valid_locids = (
            [location_id] + self.lt.get_node_by_id(location_id).ancestors())
        for lid in valid_locids:
            lprops = self.props.query('location_id == %s' % lid)
            if len(lprops) > 0:
                break

        # Expand sexes
        ss_props = lprops.query('sex_id != 3')
        bs_props = lprops.query('sex_id == 3')
        ss_props = ss_props.append(bs_props.replace({'sex_id': {3: 1}}))
        ss_props = ss_props.append(bs_props.replace({'sex_id': {3: 2}}))
        lprops = ss_props

        # Expand age_groups and years
        gbdprops = []
        for y in range(1990, 2016, 5):
            for i, ag in self.ags.iterrows():
                for s in [1, 2]:
                    q = ("(age_start <= {ast}) & "
                         "(age_end >= {ae}) & "
                         "(year_start <= {ys}) & "
                         "(year_end > {ye}) & "
                         "(sex_id == {s})".format(
                             ast=ag['age_group_years_start'],
                             ae=min(99, ag['age_group_years_end']-1),
                             ys=y,
                             ye=y,
                             s=s))
                    ya_props = lprops.query(q)
                    assert len(ya_props) == len(self.child_meids), """
                        Proportions must be unique to a location_id, year_id,
                        age_group_id, sex combination"""
                    ya_props = ya_props.assign(age_group_id=ag['age_group_id'])
                    ya_props = ya_props.assign(year_id=y)
                    ya_props = ya_props.assign(location_id=location_id)
                    gbdprops.append(ya_props)
        gbdprops = pd.concat(gbdprops)
        return gbdprops.reset_index(drop=True)


def split_location(location_id):
    draws = gopher.draws(
                {'modelable_entity_ids': [ss.parent_meid]},
                source='dismod',
                location_ids=location_id,
                measure_ids=[5, 6])
    draws['measure_id'] = draws.measure_id.astype(int)
    gprops = ss.gbdize_proportions(location_id)
    gprops = gprops.assign(measure_id=5)
    gprops = gprops.append(gprops.replace({'measure_id': {5: 6}}))
    gprops = gprops[gprops.measure_id.isin(draws.measure_id.unique())]
    gprops = gprops[gprops.age_group_id.isin(draws.age_group_id.unique())]
    gprops = gprops[gprops.sex_id.isin(draws.sex_id.unique())]
    dcs = ['draw_%s' % i for i in range(1000)]
    splits = maths.merge_split(
        draws,
        gprops,
        group_cols=['location_id', 'year_id', 'age_group_id', 'sex_id',
                    'measure_id'],
        value_cols=dcs)
    splits = splits.assign(modelable_entity_id=splits['child_meid'])
    return splits


def split_locationq(inqueue, oq_meta):
    for location_id in iter(inqueue.get, sentinel):
        try:
            print 'Splitting %s' % location_id
            splits = split_location(location_id)
            for child_meid in splits.child_meid.unique():
                oq = [v['outqueue'] for k, v in oq_meta.iteritems()
                      if child_meid in v['child_meids']][0]
                oq.put(splits[splits.child_meid == child_meid])
        except Exception as e:
            print 'Error splitting %s: %s' % (location_id, e)
            for oqid, oq in oq_meta.iteritems():
                for meid in oq['child_meids']:
                    oq['outqueue'].put(
                            'Uh oh, something wrong in %s %s' % (
                                meid, location_id))
    print 'Got sentinel. Exiting.'


def write_me(nwait, nmeids, outqueue, mvid_q):
    if envi == 'dev':
        db = EpiDB('epi-dev-custom')
    elif envi == 'prod':
        db = EpiDB('epi')
    get_count = 0
    me_mv = {}
    while get_count < nwait:
        try:
            df = outqueue.get()
            meid = df.modelable_entity_id.unique()[0]
            if meid not in me_mv:
                print 'Creating mvid for meid %s' % (meid)
                mvid = db.create_model_version(
                        meid,
                        'Central severity split: parent %s' % ss.parent_meid,
                        75)
                print 'Created mvid %s for meid %s' % (mvid, meid)
                me_mv[meid] = mvid
            else:
                mvid = me_mv[meid]
            outfile = (
                '/ihme/epi/panda_cascade/%s/%s/full/draws/all_draws.h5' % (
                    envi, mvid))
            for col in [
                    'location_id', 'year_id', 'age_group_id', 'sex_id',
                    'measure_id']:
                df[col] = df[col].astype(int)
            df = df[[
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id']+['draw_%s' % i for i in range(1000)]]
            store = pd.HDFStore(outfile)
            store.append(
                    'draws',
                    df,
                    data_columns=[
                        'measure_id', 'location_id', 'year_id',
                        'age_group_id', 'sex_id'],
                    index=False)
            store.close()
            get_count += 1
        except Exception as e:
            print str(e)
            get_count += 1

    try:
        for meid, mvid in me_mv.iteritems():
            outfile = (
                '/ihme/epi/panda_cascade/%s/%s/full/draws/all_draws.h5' % (
                    envi, mvid))
            store = pd.HDFStore(outfile)
            print 'Creating index for mv %s for meid %s' % (mvid, meid)
            store.create_table_index(
                    'draws',
                    columns=[
                        'measure_id', 'location_id', 'year_id',
                        'age_group_id', 'sex_id'],
                    optlevel=9,
                    kind='full')
            store.close()
            print 'Closing file for mv %s for meid %s' % (mvid, meid)
            mvid_q.put(mvid)
            nmeids = nmeids-1
    except Exception as e:
        print 'Uh oh, hit a writing error %s' % e
        for i in range(nmeids):
            mvid_q.put((500, str(e)))


def split_me(parent_meid, env='dev', prop_drawfile=None):
    global ss, envi
    envi = env
    ss = SevSplitter(parent_meid, prop_drawfile=prop_drawfile)
    locs = [l.id for l in ss.lt.leaves()]
    nlocs = len(locs)

    inqueue = Queue()
    mvid_queue = Queue()

    num_writers = min(4, len(ss.child_meids.child_meid))
    oq_meta = {i: {'child_meids': [], 'outqueue': None}
               for i in range(num_writers)}

    wo_pool = cycle(range(num_writers))
    for child_meid in ss.child_meids.child_meid:
        oq_meta[wo_pool.next()]['child_meids'].append(child_meid)

    print git_info
    for n in range(num_writers):
        outqueue = Queue()
        nmeids = len(oq_meta[n]['child_meids'])
        writer = Process(
                target=write_me,
                args=(nlocs*nmeids, nmeids, outqueue, mvid_queue))
        writer.start()
        oq_meta[n]['outqueue'] = outqueue

    num_processes = 20
    split_jobs = []
    for i in range(num_processes):
        p = Process(target=split_locationq, args=(inqueue, oq_meta))
        split_jobs.append(p)
        p.start()
    for l in locs:
        inqueue.put(l)
    for l in range(num_processes):
        inqueue.put(sentinel)
    mvids = []
    while len(mvids) < len(ss.child_meids.child_meid):
        mvid = mvid_queue.get()
        print mvid
        mvids.append(mvid)
        print len(mvids), len(ss.child_meids.child_meid)
    return mvids
