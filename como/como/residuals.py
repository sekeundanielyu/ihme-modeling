from adding_machine.db import EpiDB
from adding_machine.super_gopher import SuperGopher
import pandas as pd
import numpy as np
import os

this_path = os.path.abspath(os.path.dirname(__file__))
drawcols = ['draw_%s' % i for i in range(1000)]


def calc(lid, yid, sid, cause_ylds, seq_ylds):
    db = EpiDB('cod')
    eng = db.get_engine(db.dsn_name)
    ccv = pd.read_sql("""
            SELECT output_version_id FROM cod.output_version
            WHERE code_version=3 AND is_best=1""", eng).squeeze()
    rkey = pd.read_excel(
        '%s/config/residual_key.xlsx' % this_path)
    sg = SuperGopher({
        'file_pattern': 'death_{location_id}.h5',
        'h5_tablename': 'draws'},
        '/ihme/centralcomp/codcorrect/{ccv}/draws'.format(ccv=ccv))
    ylls = sg.content(location_id=lid, year_id=yid, sex_id=sid)
    ylls = to_rates(ylls)
    ylls = to_ylls(ylls)

    cresids = []
    sresids = []
    for resid_cid, yldmap in rkey.groupby('input_cause_id'):
        these_ylls = ylls[ylls.cause_id == resid_cid]
        ratio_ylls = ylls[ylls.cause_id.isin(yldmap.ratio_cause_id.unique())]
        if yldmap.ratio_level.unique().squeeze() == 'cause':
            ylds = cause_ylds[cause_ylds.cause_id.isin(
                yldmap.ratio_cause_id.unique())]
            ylds['ratio_cause_id'] = ylds.cause_id
        else:
            ylds = seq_ylds[seq_ylds.sequela_id.isin(
                yldmap.ratio_sequela_id.unique())]
            ylds = ylds.merge(
                yldmap[['ratio_cause_id', 'ratio_sequela_id']],
                left_on='sequela_id', right_on='ratio_sequela_id')
        ylds = ylds.groupby(['age_group_id'])
        ylds = ylds.sum().reset_index()
        ratio = these_ylls[drawcols].sum()/ratio_ylls[drawcols].sum()
        ratio = ratio.replace(np.inf, 1)
        ylds.ix[:, drawcols] = (ylds[drawcols].values*ratio.values)
        ylds['location_id'] = lid
        ylds['year_id'] = yid
        ylds['sex_id'] = sid
        ylds = ylds[
                ['location_id', 'year_id', 'age_group_id', 'sex_id']+drawcols]
        if yldmap.output_id_type.unique().squeeze() == 'cause_id':
            ylds['cause_id'] = yldmap.output_id.unique().squeeze()
            cresids.append(ylds)
        elif yldmap.output_id_type.unique().squeeze() == 'sequela_id':
            ylds['sequela_id'] = yldmap.output_id.unique().squeeze()
            sresids.append(ylds)
    return pd.concat(cresids), pd.concat(sresids)


def to_rates(df):
    thisdf = df.copy()
    thisdf.ix[:, drawcols] = (
            thisdf[drawcols].values / thisdf[['pop']].values)
    return thisdf


def to_ylls(df):
    predex = pd.read_stata(
        '/ihme/gbd/WORK/02_mortality/03_models/5_lifetables/products/'
        'yll_exp.dta')
    thisdf = df.merge(predex)
    thisdf.ix[:, drawcols] = (
            thisdf[drawcols].values * thisdf[['pred_ex']].values)
    return thisdf
