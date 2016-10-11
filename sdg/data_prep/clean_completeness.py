import pandas as pd
import sys

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test


def assemble_china_df():
    """Get national china together to append"""
    chn_df = pd.read_csv(dw.COMPLETENESS_FILE_CHN)
    # extend to 2015
    chn_df2014 = chn_df.query('year==2013')
    chn_df2014.loc[:, 'year'] = 2014
    chn_df2015 = chn_df.query('year==2013')
    chn_df2015.loc[:, 'year'] = 2015
    chn_df = chn_df.append(
        chn_df2014, ignore_index=True).append(
        chn_df2015, ignore_index=True)
    chn_df = chn_df.rename(columns={
        'implied_comp': 'trunc_pred',
        'year': 'year_id'
    }
    )
    chn_df['sex_id'] = 3
    chn_df['source_type'] = "VR"
    return chn_df


def assemble_ind_df():
    """Get national china together to append"""
    df = pd.read_csv(dw.COMPLETENESS_FILE_IND)
    # extend to 2015
    df2014 = df.query('year_id==2013')
    df2014.loc[:, 'year_id'] = 2014
    df2015 = df.query('year_id==2013')
    df2015.loc[:, 'year_id'] = 2015
    df = df.append(
        df2014, ignore_index=True).append(
        df2015, ignore_index=True)
    df['trunc_pred'] = df['srs_deaths'] / df['env_mean']
    df['source_type'] = "VR"
    # add location_id
    df['location_id'] = 163
    df = df[['ihme_loc_id', 'year_id', 'sex_id',
             'location_id', 'source_type', 'trunc_pred']]
    return df


def add_england(df):
    """Duplicate GBR and make it England"""
    # copy UK and make it england
    eng_df = df.query('ihme_loc_id=="GBR"')
    eng_df['ihme_loc_id'] = "GBR_4749"
    eng_df['location_id'] = 4749
    df = df.append(eng_df, ignore_index=False)
    return df


# read in data
df = pd.read_csv(dw.COMPLETENESS_FILE)

# keep both sexes only
df = df.ix[df['sex'] == "both"]
df['sex_id'] = 3

# rename year to year_id
df = df.rename(columns={'year': 'year_id'})

# merge ihme_loc_id with location_id using loc set 35
locs_table = qry.queryToDF(qry.LOCATIONS.format(lsid=35))
loc_mapping = locs_table[['ihme_loc_id', 'location_id']]
# get rid of china without hong kong macau
df = df.query('ihme_loc_id != "CHN_44533"')
df = df.merge(loc_mapping, how='left')
# make sure there is a location_id for all observations
assert df.location_id.notnull().values.all(), 'merge failed'

# keep only VR and remove the ZAF duplicate VR
df = df.ix[df['source_type'].str.startswith("VR")]
df = df.query("~(ihme_loc_id=='ZAF' & source_type=='VR-SSA')")

# add China national estimate 
df = df.append(assemble_china_df(), ignore_index=True)
# add India national estimate after removing other india
df = df.query("ihme_loc_id != 'IND'")
df = df.append(assemble_ind_df(), ignore_index=True)
# add England as copy of UK
df = add_england(df)
# create square dataset of all sdg reporting locations and years, and fill in
# any missing completeness
years = range(1990, 2016, 1)
years = pd.DataFrame({'year_id': years})
years['key'] = 0
locs = qry.get_sdg_reporting_locations()[['location_id']]
locs['key'] = 0
sqr_df = years.merge(locs, on='key')
sqr_df = sqr_df.drop('key', axis=1)
sqr_df['sex_id'] = 3
df = sqr_df.merge(df, how='left')
df[dw.COMPLETENESS_DATA_COL] = df[dw.COMPLETENESS_DATA_COL].fillna(0)


# make a fake draws dataframe by copying trunc_pred (completeness)
#   into each draw, so there is no uncertainty
idx = df.index
draws = pd.DataFrame(index=df.index, columns=dw.DRAW_COLS)
draws = draws.apply(lambda x: x.fillna(df[dw.COMPLETENESS_DATA_COL]))

# add the draws to the dataframe, leveraging the shared index
df = pd.concat([df, draws], axis=1)
df['metric_id'] = 2
df['measure_id'] = 18
# make sure that we only have one observation per location year
assert not df[['location_id', 'year_id']].duplicated().values.any(), \
    'duplicates across location years'

df = df[dw.COMPLETENESS_GROUP_COLS + dw.DRAW_COLS]

sdg_test.all_sdg_locations(df)

out_file = dw.COMPLETENESS_OUT_DIR + "/completeness.h5"
df.to_hdf(out_file, key="data", format="table",
          data_columns=['location_id', 'year_id'])
