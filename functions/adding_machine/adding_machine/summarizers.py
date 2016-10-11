from __future__ import division
import pandas as pd
import agg_engine as ae
import os
import super_gopher
from functools32 import lru_cache
try:
    from hierarchies import dbtrees
except:
    from hierarchies.hierarchies import dbtrees
import numpy as np
from scipy import stats
from multiprocessing import Pool
import itertools
from db import EpiDB

this_file = os.path.abspath(__file__)
this_path = os.path.dirname(this_file)


@lru_cache()
def get_age_weights():
    query = """
        SELECT age_group_id, age_group_weight_value
        FROM shared.age_group_weight
        WHERE gbd_round_id = 3"""
    db = EpiDB('epi')
    eng = db.get_engine(db.dsn_name)
    aws = pd.read_sql(query, eng)
    return aws


@lru_cache()
def get_age_spans():
    query = """
        SELECT age_group_id, age_group_years_start, age_group_years_end
        FROM shared.age_group"""
    db = EpiDB('epi')
    eng = db.get_engine(db.dsn_name)
    ags = pd.read_sql(query, eng)
    return ags


def get_pop(filters={}):
    query = """
        SELECT o.age_group_id, year_id, o.location_id, o.sex_id, pop_scaled
        FROM mortality.output o
        LEFT JOIN mortality.output_version ov using (output_version_id)
        LEFT JOIN shared.age_group a using (age_group_id)
        LEFT JOIN shared.location l using (location_id)
        LEFT JOIN shared.sex s using (sex_id)
        WHERE ov.is_best = 1
        AND year_id >= 1980 AND year_id <= 2015"""
    for k, v in filters.iteritems():
        v = np.atleast_1d(v)
        v = [str(i) for i in v]
        query = query + " AND {k} IN ({vlist})".format(
                k=k, vlist=",".join(v))
    db = EpiDB('cod')
    eng = db.get_engine(db.dsn_name)
    pop = pd.read_sql(query, eng)
    return pop


def combine_sexes_indf(df):
    draw_cols = list(df.filter(like='draw').columns)
    index_cols = list(set(df.columns) - set(draw_cols))
    index_cols.remove('sex_id')
    csdf = df.merge(
            pop,
            on=['location_id', 'year_id', 'age_group_id', 'sex_id'])
    # assert len(csdf) == len(df), "Uh oh, some pops are missing..."
    csdf = ae.aggregate(
            csdf[index_cols+draw_cols+['pop_scaled']],
            draw_cols,
            index_cols,
            'wtd_sum',
            weight_col='pop_scaled')
    csdf['sex_id'] = 3
    return csdf


def combine_ages(df, gbd_compare_ags=False):

    age_groups = {
        22: (0, 200),
        27: (0, 200)}
    if gbd_compare_ags:
        age_groups.update({
            1: (0, 5),
            23: (5, 15),
            24: (15, 50),
            25: (50, 70),
            26: (70, 200)})

    index_cols = ['location_id', 'year_id', 'measure_id', 'sex_id']
    if 'cause_id' in df.columns:
        index_cols.append('cause_id')
    if 'sequela_id' in df.columns:
        index_cols.append('sequela_id')
    if 'rei_id' in df.columns:
        index_cols.append('rei_id')
    draw_cols = list(df.filter(like='draw').columns)

    results = []
    for age_group_id, span in age_groups.items():

        if age_group_id in df.age_group_id.unique():
            continue

        # Get aggregate age cases
        if age_group_id != 27:
            wc = 'pop_scaled'
            aadf = df.merge(ags)
            aadf = aadf[
                    (span[0] <= aadf.age_group_years_start) &
                    (span[1] >= aadf.age_group_years_end)]
            aadf.drop(
                ['age_group_years_start', 'age_group_years_end'],
                axis=1,
                inplace=True)
            len_in = len(aadf)
            aadf = aadf.merge(
                pop,
                on=['location_id', 'year_id', 'age_group_id', 'sex_id'],
                how='left')
            assert len(aadf) == len_in, "Uh oh, some pops are missing..."
        else:
            wc = 'age_group_weight_value'
            aadf = df.merge(aw, on='age_group_id', how='left')
            assert len(aadf) == len(df), "Uh oh, some weights are missing..."
        aadf = ae.aggregate(
                aadf[index_cols+draw_cols+[wc]],
                draw_cols,
                index_cols,
                'wtd_sum',
                weight_col=wc)
        aadf['age_group_id'] = age_group_id
        results.append(aadf)
    results = pd.concat(results)
    return results


def get_estimates(df):
    """ Compute summaries """
    summdf = df.copy()
    summdf['mean'] = summdf.filter(like='draw').mean(axis=1)
    summdf['median'] = np.median(
            summdf.filter(like='draw').values,
            axis=1)
    summdf['lower'] = stats.scoreatpercentile(
            summdf.filter(like='draw').values,
            per=2.5,
            axis=1)
    summdf['upper'] = stats.scoreatpercentile(
            summdf.filter(like='draw').values,
            per=97.5,
            axis=1)
    nondraw_cols = set(summdf.columns)-set(summdf.filter(like='draw').columns)
    return summdf[list(nondraw_cols)]


def pct_change(df, start_year, end_year, change_type='pct_change',
               index_cols=None):
    """ Compute pct change: either arc or regular pct_change (rate or num).
    For pct_change in rates or arc pass in a df in rate space.
    Otherwise, pass in a df in count space."""
    # set up the incoming df to be passed into the math part
    draw_cols = list(df.filter(like='draw').columns)
    if not index_cols:
        index_cols = list(set(df.columns) - set(draw_cols + ['year_id']))
    df_s = df[df.year_id == start_year]
    df_e = df[df.year_id == end_year]
    df_s.drop('year_id', axis=1, inplace=True)
    df_e.drop('year_id', axis=1, inplace=True)
    df_s = df_s.merge(
        df_e,
        on=index_cols,
        suffixes=(str(start_year), str(end_year)))
    sdraws = ['draw_%s%s' % (d, start_year) for d in range(1000)]
    edraws = ['draw_%s%s' % (d, end_year) for d in range(1000)]

    # do the math
    if change_type == 'pct_change':
        cdraws = ((df_s[edraws].values - df_s[sdraws].values) /
                  df_s[sdraws].values)
        emean = df_s[edraws].values.mean(axis=1)
        smean = df_s[sdraws].values.mean(axis=1)
        cmean = (emean - smean) / smean
        # when any start year values are 0, we get division by zero = NaN/inf
        cdraws[np.isnan(cdraws)] = 0
        cdraws[np.isinf(cdraws)] = 0
        cmean[np.isnan(cmean)] = 0
        cmean[np.isinf(cmean)] = 0
    elif change_type == 'arc':
        # can't take a log of 0, so replace 0 with a miniscule number
        adraws = sdraws + edraws
        if (df_s[adraws].values == 0).any():
            df_s[adraws] = df_s[adraws].replace(0, 1e-9)
        gap = end_year - start_year
        cdraws = np.log(df_s[edraws].values / df_s[sdraws].values) / gap
        emean = df_s[edraws].values.mean(axis=1)
        smean = df_s[sdraws].values.mean(axis=1)
        cmean = np.log(emean / smean) / gap
    else:
        raise ValueError("change_type must be 'pct_change' or 'arc'")

    # put the dataframes back together
    cdraws = pd.DataFrame(cdraws, index=df_s.index, columns=draw_cols)
    cdraws = cdraws.join(df_s[index_cols])
    cmean = pd.DataFrame(cmean, index=df_s.index, columns=['pct_change_means'])
    cdraws = cdraws.join(cmean)
    cdraws['year_start_id'] = start_year
    cdraws['year_end_id'] = end_year
    cdraws = cdraws[
                    index_cols +
                    ['year_start_id', 'year_end_id', 'pct_change_means'] +
                    draw_cols]

    # output
    return cdraws


def transform_metric(df, to_id, from_id):
    """Given a df, it's current metric_id (from_id)
       and it's desired metric_id (to_id), transform metric space!"""
    to_id = int(to_id)
    from_id = int(from_id)

    # TODO: Expand this for the other metrics too.
    # Right not just doing number and rate for the get_pct_change shared fn.
    valid_to = [1, 3]
    assert to_id in valid_to, "Pass either 1 or 3 for the 'to_id' arg"
    valid_from = [1, 3]
    assert from_id in valid_from, "Pass either 1 or 3 for the 'from_id' arg"

    merge_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
    if not df.index.is_integer:
        df.reset_index(inplace=True)
    for col in merge_cols:
        assert col in df.columns, "Df must contain %s" % col

    # find years and sexes in the df
    years = df.year_id.unique()
    sexes = df.sex_id.unique()
    ages = df.age_group_id.unique()
    locations = df.location_id.unique()

    # get populations for those years and sexes
    pop = get_pop({'year_id': years, 'sex_id': sexes,
                   'age_group_id': ages, 'location_id': locations})

    # transform
    draw_cols = list(df.filter(like='draw').columns)
    new_df = df.merge(pop, on=merge_cols, how='inner')
    if (to_id == 3 and from_id == 1):
        for i in draw_cols:
            new_df['%s' % i] = new_df['%s' % i] / new_df['pop_scaled']
    elif (to_id == 1 and from_id == 3):
        for i in draw_cols:
            new_df['%s' % i] = new_df['%s' % i] * new_df['pop_scaled']
    else:
        raise ValueError("'to_id' and 'from_id' must be two unique numbers")

    # put the dfs back together
    if 'metric_id' in new_df.columns:
        new_df['metric_id'].replace(from_id, to_id, axis=1, inplace=True)
    else:
        new_df['metric_id'] = to_id
    new_df.drop('pop_scaled', axis=1, inplace=True)
    return new_df


def summarize_location(
        location_id,
        drawdir,
        sg=None,
        years=[1990, 1995, 2000, 2005, 2010, 2015],
        change_intervals=None,
        combine_sexes=False,
        force_age=False,
        draw_filters={},
        calc_counts=False,
        gbd_compare_ags=False):
    drawcols = ['draw_%s' % i for i in range(1000)]
    if sg is None:
        spec = super_gopher.known_specs[2]
        sg = super_gopher.SuperGopher(spec, drawdir)

    if change_intervals:
        change_years = [i for i in itertools.chain(*change_intervals)]
    else:
        change_years = []
    change_df = []
    summary = []
    for y in years:
        df = sg.content(
                location_id=location_id, year_id=y, sex_id=[1, 2],
                **draw_filters)
        if force_age:
            df = df[df.age_group_id.isin(range(2, 22))]
        if combine_sexes:
            df = df[df.sex_id != 3]
            cs = combine_sexes_indf(df)
            df = df.append(cs)
        df = df.append(combine_ages(df, gbd_compare_ags))
        df['metric_id'] = 3
        if ('cause_id' in df.columns) and ('rei_id' not in df.columns):
            denom = df.ix[df.cause_id == 294].drop('cause_id', axis=1)
            if len(denom) > 0:
                mcols = list(set(denom.columns)-set(drawcols))
                pctdf = df.merge(denom, on=mcols, suffixes=('_num', '_dnm'))
                num = pctdf.filter(like="_num").values
                dnm = pctdf.filter(like="_dnm").values
                pctdf = pctdf.reset_index(drop=True)
                pctdf = pctdf.join(pd.DataFrame(
                    data=num/dnm, index=pctdf.index, columns=drawcols))
                pctdf = pctdf[mcols+['cause_id']+drawcols]
                pctdf['metric_id'] = 2
                df = pd.concat([df, pctdf])
        if calc_counts:
            popdf = df[df.metric_id == 3].merge(pop)
            popdf['metric_id'] = 1
            popdf.ix[:, drawcols] = (
                    popdf[drawcols].values.T * popdf.pop_scaled.values).T
            popdf.drop('pop_scaled', axis=1, inplace=True)
            summary.append(get_estimates(popdf))

        summary.append(get_estimates(df))
        if y in change_years:
            change_df.append(df)
            if calc_counts:
                change_df.append(popdf)
    summary = pd.concat(summary)

    if change_intervals is not None:
        change_df = pd.concat(change_df)
        changesumms = []
        for ci in change_intervals:
            changedf = pct_change(change_df, ci[0], ci[1])
            changesumms.append(get_estimates(changedf))
        changesumms = pd.concat(changesumms)
        changesumms['median'] = changesumms['pct_change_means']
    else:
        changesumms = pd.DataFrame()
    return summary, changesumms


def slw(args):
    try:
        s, cs = summarize_location(*args[0], **args[1])
        return s, cs
    except Exception, e:
        print args
        print e
        return None


def launch_summaries(
        model_version_id,
        env='dev',
        years=[1990, 1995, 2000, 2005, 2010, 2015],
        file_pattern='all_draws.h5',
        h5_tablename='draws'):

    global pop, aw, ags
    pop = get_pop()
    aw = get_age_weights()
    ags = get_age_spans()
    drawdir = '/ihme/epi/panda_cascade/%s/%s/full/draws' % (
            env, model_version_id)
    outdir = '/ihme/epi/panda_cascade/%s/%s/full/summaries' % (
            env, model_version_id)
    try:
        os.makedirs(outdir)
        os.chmod(outdir, 0o775)
        os.chmod(os.path.join(outdir, '..'), 0o775)
        os.chmod(os.path.join(outdir, '..', '..'), 0o775)
    except:
        pass
    lt = dbtrees.loctree(None, location_set_id=35)
    locs = [l.id for l in lt.nodes]
    sg = super_gopher.SuperGopher({
            'file_pattern': file_pattern,
            'h5_tablename': h5_tablename},
            drawdir)
    pool = Pool(10)
    res = pool.map(slw, [(
        (l, drawdir, sg, years), {}) for l in locs])
    pool.close()
    pool.join()
    res = [r for r in res if isinstance(r, tuple)]
    res = zip(*res)
    summ = pd.concat([r for r in res[0] if r is not None])
    summ = summ[[
        'location_id', 'year_id', 'age_group_id', 'sex_id',
        'measure_id', 'mean', 'lower', 'upper']]
    summfile = "%s/model_estimate_final.csv" % outdir
    summ.to_csv(summfile, index=False)
    os.chmod(summfile, 0o775)
    csumm = pd.concat(res[1])
    if len(csumm) > 0:
        csumm = csumm[[
            'location_id', 'year_start', 'year_end', 'age_group_id', 'sex_id',
            'measure_id', 'median', 'lower', 'upper']]
        csummfile = "%s/change_summaries.csv" % outdir
        csumm.to_csv(csummfile, index=False)
        os.chmod(csummfile, 0o775)


def summ_lvl_meas(args):
    drawdir, outdir, location_id, measure_id = args
    try:
        os.makedirs(outdir)
        os.chmod(outdir, 0o775)
        os.chmod(os.path.join(outdir, '..'), 0o775)
        os.chmod(os.path.join(outdir, '..', '..'), 0o775)
    except:
        pass
    try:
        sg = super_gopher.SuperGopher({
            'file_pattern': '{measure_id}_{location_id}_{year_id}_{sex_id}.h5',
            'h5_tablename': 'draws'},
            drawdir)
        print 'Combining summaries %s %s...' % (drawdir, measure_id)
        summ, csumm = summarize_location(
            location_id,
            drawdir,
            sg,
            change_intervals=[(2005, 2015), (1990, 2015), (1990, 2005)],
            combine_sexes=True,
            force_age=True,
            calc_counts=True,
            draw_filters={'measure_id': measure_id},
            gbd_compare_ags=True)
        if 'cause' in drawdir:
            summ = summ[[
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id', 'metric_id', 'cause_id', 'mean', 'lower',
                'upper']]
            summ = summ.sort_values([
                'measure_id', 'year_id', 'location_id', 'sex_id',
                'age_group_id', 'cause_id', 'metric_id'])
        elif 'sequela' in drawdir:
            summ = summ[[
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id', 'metric_id', 'sequela_id', 'mean', 'lower',
                'upper']]
            summ = summ.sort_values([
                'measure_id', 'year_id', 'location_id', 'sex_id',
                'age_group_id', 'sequela_id', 'metric_id'])
        elif 'rei' in drawdir:
            summ = summ[[
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id', 'metric_id', 'rei_id', 'cause_id', 'mean',
                'lower', 'upper']]
            summ = summ.sort_values([
                'measure_id', 'year_id', 'location_id', 'sex_id',
                'age_group_id', 'rei_id', 'cause_id', 'metric_id'])
        summfile = "%s/%s_%s_single_year.csv" % (
                outdir, measure_id, location_id)
        print 'Writing to file...'
        summ = summ[summ['mean'].notnull()]
        summ.to_csv(summfile, index=False)
        os.chmod(summfile, 0o775)
        if len(csumm) > 0:
            if 'cause' in drawdir:
                csumm = csumm[[
                    'location_id', 'year_start_id', 'year_end_id',
                    'age_group_id', 'sex_id', 'measure_id', 'cause_id',
                    'metric_id', 'median', 'lower', 'upper']]
                csumm = csumm.sort_values([
                    'measure_id', 'year_start_id', 'year_end_id',
                    'location_id', 'sex_id', 'age_group_id', 'cause_id',
                    'metric_id'])
            elif 'sequela' in drawdir:
                csumm = csumm[[
                    'location_id', 'year_start_id', 'year_end_id',
                    'age_group_id', 'sex_id', 'measure_id', 'sequela_id',
                    'metric_id', 'median', 'lower', 'upper']]
                csumm = csumm.sort_values([
                    'measure_id', 'year_start_id', 'year_end_id',
                    'location_id', 'sex_id', 'age_group_id', 'sequela_id',
                    'metric_id'])
            elif 'rei' in drawdir:
                csumm = csumm[[
                    'location_id', 'year_start_id', 'year_end_id',
                    'age_group_id', 'sex_id', 'measure_id', 'rei_id',
                    'cause_id', 'metric_id', 'median', 'lower', 'upper']]
                csumm = csumm.sort_values([
                    'measure_id', 'year_start_id', 'year_end_id',
                    'location_id', 'sex_id', 'age_group_id', 'rei_id',
                    'cause_id', 'metric_id'])
            csummfile = "%s/%s_%s_multi_year.csv" % (
                    outdir, measure_id, location_id)
            csumm = csumm[
                (csumm['median'].notnull()) & np.isfinite(csumm['median']) &
                (csumm['lower'].notnull()) & np.isfinite(csumm['lower']) &
                (csumm['upper'].notnull()) & np.isfinite(csumm['upper'])]
            csumm.to_csv(csummfile, index=False)
            os.chmod(csummfile, 0o775)
    except Exception as e:
        print e


def launch_summaries_como(draw_out_dirmap, location_id):

    global pop, aw, ags
    pop = get_pop({'location_id': location_id})
    aw = get_age_weights()
    ags = get_age_spans()
    arglist = [(d, o, location_id, measure_id)
               for d, o in draw_out_dirmap.iteritems()
               for measure_id in [3, 5, 6, 22, 23, 24]]
    pool = Pool(len(draw_out_dirmap)*3)
    pool.map(summ_lvl_meas, arglist, chunksize=1)
    pool.close()
    pool.join()
