import pandas as pd
import sys
import numpy as np

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test


def add_china_aggregate(df):
    """Append china aggregate to the dataframe.

    Take the pop-weighted mean, by draw, of each china subnational.
    """

    # subset to just china
    chn = df.ix[df['ihme_loc_id'].str.startswith("CHN")]

    # merge with populations
    pops = qry.get_pops()
    pops = pops.query('sex_id==3 & age_group_id == 22')
    pops = pops[['location_id', 'year_id', 'mean_pop']]
    chn = chn.merge(pops, how='left')
    assert chn.mean_pop.notnull().values.all(), 'merge with pops failed'

    # calculate the pop-weighted average of each draw column
    # lambda within a lambda! because x is a dataframe.
    # And y are series that use x columns.
    # 'chn' only has year & draws afterwards so add ihme_loc_id, location_id
    g = chn.groupby(['year_id'])
    chn = g.apply(lambda x: x[dw.DRAW_COLS].apply(
        lambda y: np.average(y, weights=x['mean_pop'])
    )
    ).reset_index()
    chn['ihme_loc_id'] = "CHN"
    chn['location_id'] = 6

    # add the national observation to df
    df = df.append(chn, ignore_index=True)
    return df


def add_location_id(df):
    """Add location_id to the df using ihme_loc_id"""

    # pull all locations
    locs = qry.queryToDF(qry.LOCATIONS.format(lsid=35))
    locs = locs[['ihme_loc_id', 'location_id', 'level']]

    df = df.merge(locs, how='outer')
    assert df.location_id.notnull().values.all(), \
        'merge failed to get location_id'
    assert df.ix[
        (df['level'] >= 3) &
        (df['ihme_loc_id'] != "CHN")
    ].year_id.notnull().values.all(), \
        'data doesnt have all expected locations ' \
        '(should only be missing regions & china)'
    df = df.drop('level', axis=1)
    df = df.ix[df.year_id.notnull()]
    return df


def main():
    """read, standardize columns, add location id, add china aggregate"""
    df = pd.read_csv(dw.MEAN_PM25_INFILE)
    assert not df[['iso3', 'year']].duplicated().any(), \
        'unexpected id columns, should be iso3 and year'
    df = df.rename(columns={'iso3': 'ihme_loc_id', 'year': 'year_id'})
    df = df.rename(columns={'draw_1000': 'draw_0'})
    df = df[['ihme_loc_id', 'year_id'] + dw.DRAW_COLS]
    df = add_location_id(df)
    df = add_china_aggregate(df)

    # standardize column structure again
    # (thought age and sex would be confusing, that doesnt make sense here)
    df['metric_id'] = 3
    df['measure_id'] = 19
    df = df[dw.MEAN_PM25_GROUP_COLS + dw.DRAW_COLS]

    sdg_test.all_sdg_locations(df)
    # save
    df.to_hdf(dw.MEAN_PM25_OUTFILE,
              format="table", key="data",
              data_columns=['location_id', 'year_id'])

if __name__ == "__main__":
    main()
