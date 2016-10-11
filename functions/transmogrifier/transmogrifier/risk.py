import numpy as np
import pandas as pd
import maths
import gopher
import epi
from risk_utils.classes import risk
from risk_utils.draws import custom_draws, add_columns, column_names, \
    fill_resid_category_label


def risk_draws(
        risk_id, draw_type, lids=[], yids=[], sids=[], meas_ids=[],
        ag_ids=[], status='best', verbose=True, scale=False, **kwargs):
    """
    Returns the draws for the given rei id (risk_id),
    draw_type (ie exposure, rr) location_id (lid), year_id (yid), measure_id
    (meas_id) sex_id (sid),  and age_group_ids (ag_ids)

    If exposure draws are requested, this function will automatically calculate
    the residual category. And if scale=True, the sum of all categories will
    equal 1

    Arguments:
        risk_id (int): ID of the risk to be retrieved
        draw_type (str): type of risk draws to retrieve
                         (exposure, rr, tmrel, paf)
        lids (empty list or list of ints): A list of location_ids
        sids (empty list or list of ints): A list of sex_ids
        meas_ids (empty list or list of ints): a list of measure ids
        ag_ids (empty list or list of ints): A list of age_group_ids to
                retrieve, or the empty list to return all available
                age_group_ids
        status ('best' or 'latest'): Defaults to 'best,' determines
                whether the best or most recent model is returned
        verbose (boolean): Print progress updates
        kwargs: any other optional arguments (ie for pafs, paf_type)

    Returns:
        Draws as a DataFrame
    """
    yids = list(np.atleast_1d(yids))
    lids = list(np.atleast_1d(lids))
    sids = list(np.atleast_1d(sids))
    ag_ids = list(np.atleast_1d(ag_ids))
    meas_ids = list(np.atleast_1d(meas_ids))

    # create risk object to get ME ids. Verify a model exists for each
    this_risk = risk(risk_id=risk_id)
    me_ids = this_risk.get_me_list(draw_type=draw_type)
    if not me_ids:
        raise RuntimeError('No {} {} MEs found'.format(this_risk.risk,
                                                       draw_type))
    try:
        mv_ids = [gopher.version_id(modelable_entity_id=me_id, status=status)[0]
                  for me_id in me_ids]
    except TypeError:
        raise RuntimeError('At least one model not found (ie, not marked best)')
    me_mv_ids = zip(me_ids, mv_ids)
    for (me_id, mv_id) in me_mv_ids:
        assert mv_id is not None, '''No {} model for meid:{} and
        mvid:{}'''.format(status, me_id, mv_id)

    # subset the df of MEs to just the ones we're getting draws for
    subset_df = this_risk.me_df[this_risk.me_df.me_id.isin(me_ids)]

    # if all MEs are dismod MEs, we can just epi_draws function
    all_dismod = (len(subset_df.model_type.unique()) == 1 and
                  subset_df.model_type.unique().item() == 'dismod')
    if all_dismod:
        draws = [epi.draws(me_id, lids=lids, sids=sids, yids=yids,
                           meas_ids=meas_ids, ag_ids=ag_ids, status=status,
                           verbose=verbose) for me_id in me_ids]

    # otherwise, draws are custom csvs that save_results copied. We'll need to
    # parse the csvs instead of using epi_draws
    else:
        try:
            draws = [custom_draws(mv_id, draw_type=draw_type, lids=lids,
                                  sids=sids, ag_ids=ag_ids, meas_ids=meas_ids,
                                  yids=yids, verbose=verbose) for mv_id in
                     mv_ids]
        except OSError:
            draws = [epi.draws(me_id, lids=lids, sids=sids, yids=yids,
                               meas_ids=meas_ids, ag_ids=ag_ids, status=status,
                               verbose=verbose) for me_id in me_ids]

    # add me and mv id cols to each draw file
    draws = [add_columns(df,
                         {'modelable_entity_id': me_id,
                          'model_version_id': mv_id})
             for (df, (me_id, mv_id)) in zip(draws, me_mv_ids)]

    # if draws are polytomous exposures, add categories/parameter column
    if draw_type == 'exposure' and this_risk.polytomous:
        draws = [add_columns(df,
                             {'parameter': subset_df[subset_df.me_id ==
                                                     me_id].parameter.item()})
                 for (df, (me_id, mv_id)) in zip(draws, me_mv_ids)]

    draws = pd.concat(draws)

    # if draws are exposure and the risk is either dichotomous or continuous,
    # add a parameter column with either 'cat1' or 'continuous'
    # (if the risk is polytomous, categories are already assigned)
    if draw_type == 'exposure' and not this_risk.polytomous:
        if this_risk.dichotomous:
            draws['parameter'] = 'cat1'
        elif this_risk.continuous:
            draws['parameter'] = 'continuous'

    # some id columns are string when they should be int
    for col in draws.columns:
        if col.endswith('id') and draws[col].dtype == 'O':
            if draws[col].isnull().any():  # IE modelable entity resid category
                draws[col] = draws[col].astype(float)
            else:
                draws[col] = draws[col].astype(int)

    # calculate residual category for categorical exposure draws
    is_categorical = this_risk.risk_type == 1
    if is_categorical and draw_type == 'exposure':
        value_cols = column_names('exposure', 'draw')
        # We will group by all id columns except modelable_entity,
        # model_version_id, and parameter
        group_cols = [c for c in column_names('exposure', 'id')
                      if 'model' not in c and 'parameter' not in c]
        resid_df = 1-draws.groupby(group_cols)[value_cols].sum()
        resid_df = resid_df.where(resid_df >= 0, 0).reset_index()
        draws = pd.concat([draws, resid_df])
        draws = fill_resid_category_label(draws)

        # optionally squeeze all categories to 1
        if scale:
            draws = maths.scale(draws, value_cols=value_cols,
                                group_cols=group_cols, scalar=1)


    return draws
