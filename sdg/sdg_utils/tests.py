import numpy as np
import pandas as pd
from getpass import getuser
import sys

sys.path.append(SDG_REPO)
import sdg_utils.queries as qry

# Run tests to assert things that should be true about each indicator


def means_are_equal(sdg_mean, gbd_mean):
    """Make sure that the sdg mean is the same as the gbd mean.

    If this is true across all strata, I'm not sure what could be broken
    """
    assert np.allclose(sdg_mean, gbd_mean, rtol=.001), \
        "SDG mean was: {} while GBD mean was: {}".format(sdg_mean, gbd_mean)


def only_estimate_age_group_ids(age_group_ids):
    """Assert that the list of age group ids are only 2-21"""
    assert set(age_group_ids) == set(range(2, 22))


def all_sdg_locations(df):
    """Test that all level three locations are present in df"""
    sdg_locs = set(qry.get_sdg_reporting_locations().location_id)
    missing_locs = sdg_locs - set(df.location_id)
    if len(missing_locs) > 0:
        raise ValueError(
            "Found {n} missing locations: {l}".format(
                n=len(missing_locs),
                l=missing_locs
            )
        )
    else:
        return True


def _get_indicator_table():
    """Fetch the table of indicator metadata"""
    indic_table = pd.read_csv(
        "/home/j/WORK/10_gbd/04_journals/"
        "gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv"
    )
    return indic_table


def df_is_square_on_indicator_location_year(df, return_fail_df=False):
    """Test that the dataframe has all combos of indicator-location-year"""
    # construct square dataframe that contains level 3 locations, all years in
    #   five year increments of 1990-2015, and all status 1 indicators
    indic_table = _get_indicator_table()
    locs_table = qry.get_sdg_reporting_locations()
    sdg_locs = list(set(locs_table.location_id))
    locs = pd.DataFrame({'location_id': sdg_locs})
    stat1indic = indic_table.query(
        'indicator_status_id==1').indicator_id.unique()
    indicators = pd.DataFrame({'indicator_id': stat1indic})
    years5inc = range(1990, 2016, 5)
    years = pd.DataFrame({'year_id': years5inc})
    for sdf in [locs, indicators, years]:
        sdf['key'] = 0
    square_df = locs.merge(indicators, on='key')
    square_df = square_df.merge(years, on='key')
    square_df = square_df.drop('key', axis=1)

    # store dataframe of missing values from the square dataframe
    df['in_data'] = 1
    square_df['in_square'] = 1
    mdf = square_df.merge(df, how='outer')
    mdf = mdf.ix[(mdf['in_data'].isnull()) | (mdf['in_square'].isnull())]
    mdf = mdf.ix[~((mdf['in_data']==1) & \
             (mdf['indicator_id'].isin([1054, 1055, 1060])))]

    if len(mdf) > 0:
        # pretty print the missing stuff
        mdf = mdf[['location_id', 'year_id', 'indicator_id',
                   'in_data', 'in_square']]
        mdf = mdf.merge(locs_table[['location_id', 'location_name']])
        mdf = mdf.merge(indic_table[['indicator_id', 'indicator_short']])
        mdf = mdf[['location_name', 'indicator_short', 'year_id',
                   'in_data', 'in_square']]
        if return_fail_df:
            return mdf
        else:
            raise ValueError(
                    "Mismatch in the following: \n{df}".format(df=mdf)
            )
    else:
        return True

