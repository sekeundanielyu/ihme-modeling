from __future__ import division

import epi
import pandas as pd
import numpy as np
import maths
from db import query
from warnings import warn
from glob import glob
from config import settings
from risk import risk_draws
from dalynator import draws as daly_draws
from como import draws as como_draws


def split_model(meid_to_split, prop_meids, location_id, status='latest'):
    """
    Splits a given modelable_entity_id (meid) based on proportions
    given in a set of meids (prop_meids), returning the resulting
    DataFrame.

    Arguments:
        meid_to_split(int): The modelable_entity_id to be split.
        prop_meids(list): A list of integer modelable_entity_ids that
                contain the proportions to be applied.
        location_id (int): The location_id to be split. This function is
                intentially scoped to operate on one location at a time
                to keep memory usage down and provide an axis for
                paralellization.

    Returns:
        A DataFrame with prop_meids applied to the draws of meid_to_split

    Example:
        Split modelable entity #2137 based on proportions provided in
        modelable entities #2159 and #2145 for location_id 100:

        post_split = split_model(2137, [2159, 2145], 100)
    """
    to_split_df = draws(
        gbd_ids={'modelable_entity_ids': [meid_to_split]},
        location_ids=location_id,
        year_ids=range(1990, 2016, 5),
        sex_ids=[1, 2],
        status=status)

    proportion_df = draws(
        gbd_ids={'modelable_entity_ids': prop_meids},
        location_ids=location_id,
        year_ids=range(1990, 2016, 5),
        sex_ids=[1, 2],
        status=status)

    split = maths.merge_split(
        to_split_df, proportion_df,
        ['year_id', 'age_group_id', 'measure_id', 'sex_id'],
        ['draw_%s' % d for d in range(1000)])

    return split


def version_id(
        modelable_entity_id=None, cause_id=None, sequela_id=None,
        risk_id=None, covariate_id=None, status='best', draw_type=None):
    """ Returns the best/latest version id for the given GBD id """

    id_args = [modelable_entity_id, cause_id, sequela_id, risk_id,
               covariate_id]
    assert len([i for i in id_args if i is not None]) == 1, '''
        Must specificy one and only one of the id arguments: meid,
        cause_id, sequela_id, risk_id, or covariate_id'''

    if modelable_entity_id is not None:
        return epi.version_id(
            modelable_entity_id=modelable_entity_id,
            sequela_id=sequela_id,
            status=status)
    if cause_id is not None:
        server = 'cod'
        db = 'cod'
        filter_col = 'cause_id'
        sf = 'AND status = 1'
        id = cause_id
        if status == 'best':
            v_filter = 'AND is_best=1'
        elif status == 'latest':
            v_filter = '''
                AND status=1
                ORDER BY date_inserted DESC
                LIMIT 1'''

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


def acause(cause_id):
    ''' Utility for retrieving acause from cause_id '''
    s = 'cod'
    q = 'SELECT acause FROM shared.cause WHERE cause_id=%s' % cause_id
    acause = query(s, q)
    return acause['acause'].values[0]


def cod_draws(
        cause_id, lids=[], yids=[], sids=[], meas_ids=[],
        ag_ids=[], status='best', verbose=True):
    """
    Returns the draws for the given model_version_id (mvid),
    location_id (lid), year_id (yid), sex_id (sid), measure_ids
    (meas_ids), and age_group_ids (ag_ids)

    Arguments:
        cause_id (int): ID of the cause to be retrieved
        lids ([] or list of ints): List of location_ids to retrieve
        sids ([] or list of ints): List of sex_ids to retrieve
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
    lids = list(np.atleast_1d(lids))
    yids = list(np.atleast_1d(yids))
    sids = list(np.atleast_1d(sids))
    meas_ids = list(np.atleast_1d(meas_ids))
    ag_ids = list(np.atleast_1d(ag_ids))

    ac = acause(cause_id)
    drawdir = '%s/%s' % (settings['cod_root_dir'], ac)

    # Define sex filter
    if (1 in sids and 2 in sids) or (not sids):
        sex_filter = "*"
    elif 1 in sids:
        sex_filter = "*_male"
    elif 2 in sids:
        sex_filter = "*_female"

    # Define location, year, age, and measure filters
    where = []
    if lids:
        where.append('location_id in [%s]' % ",".join(
            [str(l) for l in lids]))
    if yids:
        where.append('year_id in [%s]' % ",".join(
            [str(y) for y in yids]))
    if meas_ids:
        where.append('measure_id in [%s]' % ",".join(
            [str(m) for m in meas_ids]))
    if ag_ids:
        where.append('age_group_id in [%s]' % ",".join(
            [str(a) for a in ag_ids]))
    where = " & ".join(where)

    if isinstance(status, (int, long)):
        vids = [status]
    else:
        vids = version_id(cause_id=cause_id, status=status)
    draws = []
    for vid in vids:
        f = glob('%s/%s/draws/%s.h5' % (drawdir, vid, sex_filter))
        if len(f) > 0:
            if where == '':
                this_draws = pd.read_hdf(f[0], 'data')
            else:
                this_draws = pd.read_hdf(f[0], 'data', where=where)
            this_draws['model_version_id'] = vid
            draws.append(this_draws)
    draws = pd.concat(draws)
    return draws


def draws(
        gbd_ids, source, measure_ids=[], location_ids=[],
        year_ids=[], age_group_ids=[], sex_ids=[], status='best',
        verbose=False, include_risks=False, **kwargs):
    """
    Returns the best/latest draws for the given arguments

    Arguments:
        gbd_ids (dict): A dictionary whose keys are the names of the
                GBD ID fields to be queried, and whose values are lists of ids
                within each estimation area. If the list of ids
                is empty, the key:value pair can be omitted altogether.

                gbd_ids = {
                    'cause_ids': [1,2,3],
                    'sequela_ids': [1,2],
                    'modelable_entity_ids': [4],
                    'covariate_ids': [6],
                    'rei_ids': [7]}

        source: if 'dalynator', will pull causes/reis from dalynator draws
        measure_ids (empty list or list of ints):
        location_ids (empty list or list of ints):
        year_ids (empty list or list of ints):
        age_group_ids (empty list or list of ints):
        sex_ids (empty list or list of ints):
        status ('best', 'latest', or integer): Defaults to 'best,'
                determines whether draws from the best, most recent,
                or an explicit model version are returned

    Returns:
        A single DataFrame containing all requested draws.

    Examples:
        Retrieve draws for multiple modelable entities for select demgoraphics:
        d = draws(
            gbd_ids={'modelable_entity_ids': [2137, 2159, 2145]},
            measure_ids=[5],
            location_ids=100,
            year_ids=2000,
            age_group_ids=[20],
            sex_ids=[1, 2],
            status='latest',
            verbose=True)

        Retrieve all prevalence draws for one modelable entity id:
        d = draws(
            gbd_ids={'modelable_entity_ids': [2137]},
            measure_ids=[5],
            status='latest',
            verbose=True)

        Retrieve best codem death draws for one cause id for select
        demographics:
        d = draws(
            gbd_ids={'cause_ids': [302]},
            location_ids=[7, 86, 87, 88],
            year_ids=[1990, 1992, 1994, 2003])

        Retrieve best dalynator death draws for one cause id for select
        demographics:
        d = draws(
            source='dalynator',
            gbd_ids={'cause_ids': [302]},
            location_ids=[7, 86, 87, 88],
            year_ids=[1990, 1992, 1994, 2003])

    """
    source = source.lower()
    valid_sources = ['codem', 'dismod', 'epi', 'dalynator', 'risk', 'como']
    assert source in valid_sources, ('source must be one of {}'.format(
        str(valid_sources)))
    if source not in ['dalynator', 'como']:
        draws = []
        if 'modelable_entity_ids' in gbd_ids.keys():
            for meid in gbd_ids['modelable_entity_ids']:
                this_draws = epi.draws(meid, location_ids, year_ids, sex_ids,
                                       measure_ids, age_group_ids, status,
                                       verbose)
                draws.append(this_draws)
        if 'cause_ids' in gbd_ids.keys():
            for cause_id in gbd_ids['cause_ids']:
                this_draws = cod_draws(cause_id, location_ids, year_ids,
                                       sex_ids, measure_ids, age_group_ids,
                                       status, verbose)
                draws.append(this_draws)
        if 'risk_ids' in gbd_ids.keys() or 'rei_ids' in gbd_ids.keys():
            assert kwargs.get('draw_type') is not None, ('draw_type must be '
                                                         'specified for risks')
            draw_type = kwargs.pop('draw_type').lower()
            valid_types = ['exposure', 'rr', 'tmrel', 'paf']
            assert draw_type in valid_types, 'invalid draw type'
            # Not sure if user requested risk or rei ids, so combine them
            all_ids = gbd_ids.get('risk_ids', []) + gbd_ids.get('rei_ids', [])
            for risk_id in all_ids:
                this_draws = risk_draws(risk_id, draw_type, location_ids,
                                        year_ids, sex_ids, measure_ids,
                                        age_group_ids, status, verbose,
                                        **kwargs)
                draws.append(this_draws)
        if not draws:
            raise RuntimeError('No draws found. Check validity of arguments')
        draws = pd.concat(draws)
        draws = draws.reset_index(drop=True)
    elif source == 'dalynator':
        # dalynator only contains reis and causes
        if 'cause_ids' in gbd_ids.keys():
            cause_ids = gbd_ids['cause_ids']
        else:
            cause_ids = []
        if 'rei_ids' in gbd_ids.keys():
            rei_ids = gbd_ids['rei_ids']
        else:
            rei_ids = []
        draws = daly_draws(cause_ids=cause_ids,
                           rei_ids=rei_ids,
                           location_ids=location_ids,
                           year_ids=year_ids,
                           sex_ids=sex_ids,
                           measure_ids=measure_ids,
                           age_group_ids=age_group_ids,
                           status=status,
                           include_risks=include_risks,
                           verbose=verbose,
                           metric_ids=kwargs.pop('metric_ids', []),
                           **kwargs)

    elif source == 'como':
        draws = como_draws(cause_ids=gbd_ids.get('cause_ids', []),
                           rei_ids=gbd_ids.get('rei_ids', []),
                           sequela_ids=gbd_ids.get('sequela_ids', []),
                           location_ids=location_ids,
                           year_ids=year_ids,
                           sex_ids=sex_ids,
                           measure_ids=measure_ids,
                           age_group_ids=age_group_ids,
                           status=status,
                           include_risks=include_risks,
                           verbose=verbose,
                           **kwargs)

        draws = draws.reset_index(drop=True)

    for col in draws.columns:
        if col.endswith('id') and draws[col].dtype == 'O':
            if draws[col].isnull().any():  # IE modelable entity resid category
                draws[col] = draws[col].astype(float)
            else:
                draws[col] = draws[col].astype(int)

    return draws


def estimates(
        gbd_team, gbd_id=None, measure_ids='all', location_ids='all',
        year_ids='all', age_group_ids='all', sex_ids='all', status='best',
        model_version_id=None):
    """
    Returns the best/latest/version_id-specific estimates for the given
    arguments

    Arguments:
        gbd_team (str): A string specifying either 'cod' or 'epi' estimates
        gbd_id (int): The cause_id (for 'cod') or modelable_entity_id (for
                'epi') to be retrieved. This setting is ignored if a
                model_version_id is explicitly provided.
        model_version_id (int): The model_version_id to be retrieved.
        measure_ids ('all' or list of ints):
        location_ids ('all' or list of ints):
        year_ids ('all' or list of ints):
        age_group_ids ('all' or list of ints):
        sex_ids ('all' or list of ints):
        status (str): Either 'best' (default) or 'latest,' specifies
                which version of the estimates to be returned. This setting
                is ignored if a model_version_id is explicitly provided.

    Returns:
        A single DataFrame containing all requested estimates.

    Examples:
        Retrieve draws for multiple modelable entities for select demgoraphics:
        d = estimates(
            'cod',
            model_version_id=[27833],
            location_ids=100,
            year_ids=2000,
            age_group_ids=[19,20],
            sex_ids=[1, 2])

        Retrieve all prevalence draws for one modelable entity id:
        d = estimates(
            'epi',
            gbd_id=2137,
            measure_ids=5,
            status='latest')
    """

    assert not (gbd_id is None and model_version_id is None), """
        Either gbd_id or model_version_id must be specified."""

    assert status in ['best', 'latest'], """
        Status can only be 'best' or 'latest'"""

    if gbd_id is not None and model_version_id is not None:
        warn(
            "Both gbd_id and model_version_id have been specified. By default "
            "the model_version_id will be used and the gbd_id/status "
            "combination will be disregarded.")

    # Handle filter arguments
    filter_str = []
    measure_ids = np.atleast_1d(measure_ids)
    location_ids = np.atleast_1d(location_ids)
    year_ids = np.atleast_1d(year_ids)
    age_group_ids = np.atleast_1d(age_group_ids)
    sex_ids = np.atleast_1d(sex_ids)
    if year_ids != ['all']:
        year_ids = list(np.atleast_1d(year_ids))
        year_ids = ",".join([str(e) for e in year_ids])
        filter_str.append('AND year_id IN (%s)' % year_ids)
    if location_ids != ['all']:
        location_ids = list(np.atleast_1d(location_ids))
        location_ids = ",".join([str(e) for e in location_ids])
        filter_str.append('AND location_id IN (%s)' % location_ids)
    if sex_ids != ['all']:
        sex_ids = list(np.atleast_1d(sex_ids))
        sex_ids = ",".join([str(e) for e in sex_ids])
        filter_str.append('AND sex_id IN (%s)' % sex_ids)
    if gbd_team == "epi":
        if measure_ids != ['all']:
            measure_ids = list(np.atleast_1d(measure_ids))
            measure_ids = ",".join([str(e) for e in measure_ids])
            filter_str.append('AND measure_id IN (%s)' % measure_ids)
    if age_group_ids != ['all']:
        age_group_ids = list(np.atleast_1d(age_group_ids))
        age_group_ids = ",".join([str(e) for e in age_group_ids])
        filter_str.append('AND age_group_id IN (%s)' % age_group_ids)
    filter_str = " ".join(filter_str)

    if gbd_team == "cod":
        if model_version_id is None:
            mvids = version_id(cause_id=gbd_id, status=status)
        else:
            mvids = [model_version_id]
        res = []
        for mvid in mvids:
            q = """
                SELECT model_version_id, cm.location_id, cm.year_id,
                    cm.age_group_id, cm.sex_id, mean_cf, lower_cf, upper_cf,
                    env_version_id, mean_env_hivdeleted, pop_scaled
                FROM cod.model cm
                LEFT JOIN (
                    SELECT output_version_id as env_version_id, location_id as
                        mlocation_id, year_id as myear_id, age_group_id as
                        mage_group_id, sex_id as msex_id, mean_env_hivdeleted,
                        pop_scaled
                    FROM mortality.output
                    WHERE output_version_id=(
                        SELECT output_version_id
                        FROM mortality.output_version
                        WHERE is_best=1)
                    {filters}) mo
                ON (
                    mo.mlocation_id=cm.location_id AND
                    mo.myear_id=cm.year_id AND
                    mo.mage_group_id=cm.age_group_id AND
                    mo.msex_id=cm.sex_id)
                WHERE model_version_id = {mvid}
                {filters}""".format(mvid=mvid, filters=filter_str)
            res.append(query("cod", q))
        res = pd.concat(res)
        res['mean_death'] = res.mean_cf*res.mean_env_hivdeleted
        res['mean_death_rate'] = res.mean_death/res.pop_scaled
    elif gbd_team == "epi":
        if model_version_id is None:
            mvid = version_id(modelable_entity_id=gbd_id, status=status)[0]
        else:
            mvid = model_version_id
        q = """
            SELECT model_version_id, location_id, year_id, age_group_id,
            sex_id, measure_id, measure, mean, lower, upper
            FROM epi.model_estimate_final
            JOIN shared.measure USING(measure_id)
            WHERE model_version_id = %s
            %s """ % (mvid, filter_str)
        res = query("epi", q)
    return res
