from multiprocessing import Process, Queue
from data import ComoData
import numpy as np
import pandas as pd
import cython_modules.fast_random as fr
import os
from injuries import apply_NE_matrix
from aggregate import agg_cause_hierarchy
from impairment_splits.imp_splits import split_impairments
import residuals
import other_drug

sentinel = None

# Set default file mask to readable-for all users
os.umask(0o0002)


class MPGlobals(object):
    pass


def get_distribution(dws, num_bins):
    bins = np.linspace(0, 1, num_bins+1)
    binned = np.digitize(dws, bins)
    true_zeros = [len(dws[dws == 0])]

    """ Digitize start its bin count at 1, so when using the subsequent
    bincount function, skip the 0th bin. Also make sure minimum length
    (again, omitting the 0th bincount) is equal to the number of bins"""
    distribution = np.bincount(binned, minlength=num_bins+1)[1:]

    true_zeros.extend(distribution)
    distribution = true_zeros
    bin_labels = [-1]
    bin_labels.extend(bins[0:num_bins])
    distribution = pd.DataFrame({
        'bin_id': range(len(bin_labels)),
        'bin_lower': bin_labels,
        'count': distribution})
    return distribution


def simulate_qable(aq, outq, args, kwargs):
    for aid in iter(aq.get, sentinel):
        try:
            result = simulate(aid, *args, **kwargs)
            outq.put(result)
        except Exception, e:
            outq.put(('Error', 'Age: %s' % aid, str(e)))
    outq.put(sentinel)


def get_agg_cause_prev(mat, slu, draw_lab):
    acm = MPGlobals.cv.agg_cause_map
    cp = []
    for cause_id, cframe in acm.groupby('cause_id'):
        cmask = slu.isin(cframe.sequela_id).astype(int)
        cbool = np.where(cmask == 1)[0]
        prev = (np.count_nonzero(mat[:, cbool].sum(axis=1)) /
                float(mat.shape[0]))
        cp.append(pd.DataFrame({'draw_%s' % draw_lab: prev}, index=[cause_id]))
    return pd.concat(cp)


def simulate(
        aid, n_simulants, n_draws=1000, n_sim_draws_to_save=10,
        n_ac_draws=100):
    age = MPGlobals.data.age_lu[aid]
    drawcols = ['draw_%s' % d for d in range(n_draws)]

    # Set random seed
    np.random.seed()

    # Setup output dataframe
    prevs_to_como = MPGlobals.data.prevalence.query('age_group_id == %s' % aid)
    prevs_to_como = prevs_to_como.reset_index(drop=True).reset_index()

    prevs_to_como['mean'] = prevs_to_como[drawcols].mean(axis=1)

    prevs_skip_como = prevs_to_como[prevs_to_como['mean'] < (
        2./(n_simulants))]
    prevs_skip_como = prevs_skip_como.reset_index(drop=True).reset_index()
    prevs_skip_draws = prevs_skip_como[drawcols].as_matrix()

    prevs_to_como = prevs_to_como[prevs_to_como['mean'] >= (
        2./(n_simulants))]
    prevs_to_como = prevs_to_como.reset_index(drop=True).reset_index()

    sequela_id_lookup = prevs_to_como['sequela_id']
    prev_draws = prevs_to_como[drawcols+['mean']].as_matrix()

    # Add another merge for the ID age-specific DWs
    id_dws = MPGlobals.data.id_dws
    age_specific_id_dws = id_dws.ix[
        (id_dws.age_start <= float(age['age_group_years_start'])) &
        (id_dws.age_end >= float(age['age_group_years_end'])), :]
    age_specific_dws = age_specific_id_dws.append(MPGlobals.data.dws)

    # Get DW draws (in the same order as the prevalences)
    dws = prevs_to_como[['index', 'healthstate_id']].merge(
            age_specific_dws,
            on='healthstate_id',
            how='left',
            sort=False).sort('index')
    dws['mean'] = dws[drawcols].mean(axis=1)
    dw_draws = dws[drawcols+['mean']].as_matrix()

    # Simulate comorbidities for each draw
    comos = []
    ylds = []
    dw_counts = []
    sim_people = []
    agg_causes = []
    for draw_num in range(n_draws+1):

        if draw_num == n_draws:
            draw_lab = 'mean'
        else:
            draw_lab = draw_num

        print 'Attempting age %s draw %s' % (aid, draw_num)

        # Create simulants
        simulants = fr.bernoulli(n_simulants, prev_draws[:, draw_num])
        num_diseases_each = np.sum(simulants, axis=1, dtype=np.uint32)

        # Keep track of # of comorbidities for diagnostic purposes
        comorbidities = np.zeros(100)
        disease_counts = np.bincount(num_diseases_each)
        for i in range(len(disease_counts)):
            comorbidities[i] = disease_counts[i]
        comos.append(pd.DataFrame(
            data={'num_people_'+str(draw_lab): comorbidities}))

        """
        Calculate combined disability weight of each simulant as:
            1 - (the product of (1 - each dw)).
        """
        dw_sim = dw_draws[:, draw_num] * simulants
        combined_dw = 1-np.prod((1-dw_sim), axis=1)

        # Calculate the distribution of disability weights
        dist = get_distribution(combined_dw, 20)
        dw_counts.append(dist.rename(
            columns={'count': 'draw_%s' % draw_lab}))

        # Attribute the combined dw back to each constituent disease
        denom = np.sum(dw_sim, axis=1)
        denom[denom == 0] = 1
        yld_sim = (
                (dw_sim/denom.reshape(denom.shape[0], 1)) *
                combined_dw.reshape(combined_dw.shape[0], 1))
        yld_rate = np.sum(yld_sim, axis=0)/n_simulants
        if draw_num != n_draws:
            ylds.append(pd.DataFrame(data={'draw_'+str(draw_lab): yld_rate}))

        # Store the sequela that each simulant has... storage requirements are
        # quite high
        if (draw_num < n_sim_draws_to_save) or (draw_num == n_draws):
            ss = simulants * sequela_id_lookup.values
            simulant_sequelae = [
                ";".join(np.nonzero(row)[0].astype('str')) for row in ss]
            sim_people.append(pd.DataFrame(
                    data={
                        'sequelae_'+str(draw_lab): simulant_sequelae,
                        'dw_'+str(draw_lab): combined_dw}))

        if (draw_num < n_ac_draws) or (draw_num == n_draws):
            acp = get_agg_cause_prev(simulants, sequela_id_lookup, draw_lab)
            agg_causes.append(acp)

    sim_people = pd.concat(sim_people, axis=1)
    sim_people['age_group_id'] = aid

    agg_causes = pd.concat(agg_causes, axis=1)
    agg_causes['age_group_id'] = aid

    # Initialize age-specific output dataframe
    ylds_out = prevs_to_como[['sequela_id', 'age_group_id']]
    ylds_out = ylds_out.join(pd.concat(ylds, axis=1))

    skips_out = prevs_skip_como[['sequela_id', 'age_group_id']]

    # Get DW draws (in the same order as the prevalences)
    dws = prevs_skip_como[['index', 'healthstate_id']].merge(
            age_specific_dws,
            on='healthstate_id',
            how='left',
            sort=False).sort('index')
    dws = dws[drawcols].as_matrix()
    skip_ylds = prevs_skip_draws * dws
    skips_out = skips_out.join(pd.DataFrame(data=skip_ylds, columns=drawcols))

    ylds_out = ylds_out.append(skips_out)

    comos_out = pd.DataFrame({'age_group_id': aid, 'num_diseases': range(100)})
    comos_out = comos_out.join(pd.concat(comos, axis=1))

    # Append dw counts draws into single data frame
    dw_counts = (
            [dw_counts[0]] + [dw.filter(like='draw') for dw in dw_counts[1:]])
    dw_counts_out = pd.concat(dw_counts, axis=1)
    dw_counts_out['age_group_id'] = aid

    return comos_out, ylds_out, dw_counts_out, sim_people, agg_causes


def upsample(df, ndraws=1000):
    dcs = list(df.filter(regex='draw_.*[0-9]$').columns)
    ndraws_in = len([int(dc.split("_")[1]) for dc in dcs])
    rdraws = np.random.choice(dcs, size=(ndraws-ndraws_in))
    uscs = ['draw_%s' % d for d in range(ndraws_in, ndraws)]
    usdf = df.join(pd.DataFrame(
        df.ix[:, rdraws].values,
        index=df.index,
        columns=uscs))
    return usdf


class ComoSimulator(object):

    def __init__(self, como_version, location_id, year_id, sex_id, env='dev'):
        self.cv = como_version
        self.env = env
        self.lid = location_id
        self.yid = year_id
        self.sid = sex_id

        self.demcols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
        self.causecols = ['cause_id']
        self.seqcols = ['sequela_id']
        self.reicols = ['cause_id', 'rei_id']
        self.drawcols = ['draw_%s' % i for i in range(1000)]

        self.data = ComoData(self.cv, self.lid, self.yid, self.sid, env)
        MPGlobals.data = self.data
        MPGlobals.cv = self.cv

    def simulate_all(self, nsims=40000, nprocs=20):
        aq = Queue()
        outq = Queue()

        sprocs = []
        for n in range(nprocs):
            p = Process(target=simulate_qable, args=(aq, outq, [nsims], {}))
            sprocs.append(p)
            p.start()

        for a in range(2, 22):
            aq.put(a)

        for p in sprocs:
            aq.put(sentinel)

        result = []
        proc_fin_count = 0
        while proc_fin_count < nprocs:
            pres = outq.get()
            if pres == sentinel:
                proc_fin_count += 1
            else:
                result.append(pres)
        errors = [r for r in result if isinstance(r[0], str)]
        print errors
        result = [r for r in result if not isinstance(r[0], str)]
        como_counts = pd.concat([r[0] for r in result])
        ylds = pd.concat([r[1] for r in result])
        dw_counts = pd.concat([r[2] for r in result])
        sims = pd.concat([r[3] for r in result])
        acs = pd.concat([r[4] for r in result])
        return como_counts, ylds, dw_counts, sims, acs

    def simulate_all_sp(
            self, ndraws=1000, nsims=10000, age_group_ids=range(2, 22)):
        x = map(
                lambda a: simulate(a[0], a[1], a[2]),
                [(i, nsims, ndraws) for i in age_group_ids])
        return x

    def calc_impairments(self, ylds_out):
        # Impairment YLDs
        ylds_out = ylds_out.merge(self.cv.seq_map[['cause_id', 'sequela_id']])
        ylds_out['measure_id'] = 3
        ylds_out = ylds_out[[
            'age_group_id', 'cause_id', 'sequela_id', 'measure_id'] +
            self.drawcols]
        imps = split_impairments(ylds_out)
        imps['location_id'] = self.lid
        imps['year_id'] = self.yid
        imps['sex_id'] = self.sid
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=3, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'rei', 'total', fn)
        imps = imps[self.demcols + self.reicols + self.drawcols]
        imps = agg_cause_hierarchy(imps)
        dcs = self.demcols + self.reicols
        imps.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=dcs)

        # Impairment prevalence
        prev_out = self.data.prevalence.merge(
                self.cv.seq_map[['cause_id', 'sequela_id']])
        prev_out['measure_id'] = 5
        prev_out = prev_out[[
            'age_group_id', 'cause_id', 'sequela_id', 'measure_id'] +
            self.drawcols]
        imps = split_impairments(prev_out)
        imps['location_id'] = self.lid
        imps['year_id'] = self.yid
        imps['sex_id'] = self.sid
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=5, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'rei', 'total', fn)
        imps = imps[self.demcols + self.reicols + self.drawcols]
        imps = agg_cause_hierarchy(imps)
        dcs = self.demcols + self.reicols
        imps.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=dcs)

    def write_results(self, nsims=40000):
        comos_out, ylds_out, dw_counts_out, sim_people, agg_causes = (
            self.simulate_all(nsims=nsims))

        # Write DW counts, simulants, and agg causes
        fn = "dw_bins_{lid}_{yid}_{sid}.h5".format(
                lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'simulants', fn)
        dw_counts_out.reset_index(drop=True, inplace=True)
        dw_counts_out.sort_values(['age_group_id', 'bin_id'], inplace=True)
        dw_counts_out.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=['age_group_id', 'bin_id'])

        fn = "sims_{lid}_{yid}_{sid}.h5".format(
                lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'simulants', fn)
        sim_people.reset_index(drop=True, inplace=True)
        sim_people.sort_values(['age_group_id'], inplace=True)
        sim_people.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=['age_group_id'])

        # Add aggregate cause prevalence to other prevalence
        agg_causes.index.name = 'cause_id'
        agg_causes = agg_causes.reset_index()
        agg_causes['location_id'] = self.lid
        agg_causes['year_id'] = self.yid
        agg_causes['sex_id'] = self.sid
        agg_causes = upsample(agg_causes)

        # Include injury prevs
        inj_prevs = agg_cause_hierarchy(self.data.inj_cprev)
        inj_prevs = inj_prevs[
                ~inj_prevs.cause_id.isin(agg_causes.cause_id.unique())]
        agg_causes = agg_causes.append(inj_prevs)
        self.data.write_cause_prevalence(agg_causes)

        ylds_out['location_id'] = self.lid
        ylds_out['year_id'] = self.yid
        ylds_out['sex_id'] = self.sid

        # Set aside cause-level injury ylds for later...
        inj_ylds = apply_NE_matrix(
                self.cv, ylds_out, self.lid, self.yid, self.sid)

        # Include short term injuries
        ylds_out = ylds_out.append(self.data.st_inj_by_seq)
        ylds_out = ylds_out[self.demcols+self.seqcols+self.drawcols]
        ylds_out = ylds_out.groupby(self.demcols+self.seqcols).sum()
        ylds_out = ylds_out.reset_index()

        # Include short term YLDs in cause-level injuries
        inj_ylds = inj_ylds.append(self.data.st_inj_by_cause)
        inj_ylds = inj_ylds[self.demcols+self.causecols+self.drawcols]
        inj_ylds = inj_ylds.groupby(self.demcols+self.causecols).sum()
        inj_ylds = inj_ylds.reset_index()

        # Cause YLDs
        cause_ylds = ylds_out.merge(self.cv.seq_map, on='sequela_id')
        cause_ylds = cause_ylds.groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_ylds = cause_ylds[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.data.drawcols]
        cause_ylds = cause_ylds[self.demcols + self.causecols + self.drawcols]
        cause_ylds = cause_ylds[cause_ylds.cause_id > 0]
        cause_ylds = pd.concat([cause_ylds, inj_ylds])

        # Calculate residuals
        cresids, sresids = residuals.calc(
                self.lid, self.yid, self.sid, cause_ylds, ylds_out)
        cause_ylds = pd.concat([cause_ylds, cresids])
        ylds_out = pd.concat([ylds_out, sresids])

        # Write sequela YLDs
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=3, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'sequela', 'total', fn)
        ylds_out = ylds_out[self.demcols + self.seqcols + self.drawcols]
        dcs = self.demcols + self.seqcols
        ylds_out.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=dcs)

        # Calculate other drug
        cause_ylds = cause_ylds.append(other_drug.calc(
                self.lid, self.yid, self.sid, cause_ylds))

        # Aggregate and write to file
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=3, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'total', fn)
        cause_ylds = agg_cause_hierarchy(cause_ylds)
        dcs = self.demcols + self.causecols
        cause_ylds.to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=dcs)
        fn = "{mid}_{lid}_{yid}_{sid}.csv".format(
                mid=3, lid=self.lid, yid=self.yid, sid=self.sid)
        fpcsv = os.path.join(
                self.cv.root_dir, 'draws', 'cause', 'total_csvs', fn)
        cause_ylds.to_csv(fpcsv, index=False)

        # Impairments
        self.calc_impairments(ylds_out)
