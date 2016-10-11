import pandas as pd
import sqlalchemy
from hierarchies import dbtrees
from transmogrifier import gopher, maths
from multiprocessing import Pool

drawcols = ['draw_%s' % d for d in range(1000)]


def get_props(args):
    location, year = args
    print location, year
    prev_dfs = gopher.draws(
            {'modelable_entity_ids': [1951, 1952, 1953]}, source='dismod',
            location_ids=location, year_ids=year)
    prev_dfs['location_id'] = prev_dfs.location_id.astype(int)
    prev_dfs['year_id'] = prev_dfs.year_id.astype(int)

    # Extract proportions
    index_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
    props = maths.scale(
        prev_dfs,
        drawcols,
        index_cols,
        scalar=1)
    props = props.groupby(
            ['location_id', 'year_id', 'modelable_entity_id'])
    props = props.mean().reset_index()
    props = props[
            ['location_id', 'year_id', 'modelable_entity_id']+drawcols]
    return props


def epilepsy_any(cvid):
    standard_dws = pd.read_csv(
        "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv")
    eng = sqlalchemy.create_engine("strDir")
    healthstates = pd.read_sql(
            "SELECT modelable_entity_id, healthstate_id FROM epi.sequela", eng)

    # Get country-year specific prevalences for back-calculation
    lt = dbtrees.loctree(None, 35)
    locations = [l.id for l in lt.leaves()]
    years = range(1990, 2016, 5)
    prop_dfs = []
    args = [(l, y) for l in locations for y in years]

    pool = Pool(20)
    prop_dfs = pool.map(get_props, args)
    pool.close()
    pool.join()
    prop_dfs = pd.concat(prop_dfs)
    prop_dfs = prop_dfs.merge(healthstates)
    renames = {'draw_%s' % i: 'dw_prop_%s' % i for i in range(1000)}
    prop_dfs.rename(columns=renames, inplace=True)

    # Combine DWs
    dws_to_weight = prop_dfs.merge(
            standard_dws, on='healthstate_id', how='left')
    dws_to_weight = dws_to_weight.join(pd.DataFrame(
            data=(
                dws_to_weight.filter(like='draw').values *
                dws_to_weight.filter(like='dw_prop_').values),
            index=dws_to_weight.index,
            columns=drawcols))

    def combine_dws(df):
        draws_to_combine = df.filter(like='draw')
        combined_draws = 1 - (1 - draws_to_combine).prod()
        return combined_draws

    combined_dws = dws_to_weight.groupby(['location_id', 'year_id']).apply(
            combine_dws).reset_index()
    combined_dws['healthstate_id'] = 772

    col_order = ['location_id', 'year_id', 'healthstate_id']+drawcols
    combined_dws = combined_dws[col_order]
    combined_dws.to_hdf(
            "/ihme/centralcomp/como/%s/info/epilepsy_any_dws.h5" % cvid,
            'draws',
            mode='w',
            format='table',
            data_columns=['location_id', 'year_id'])
