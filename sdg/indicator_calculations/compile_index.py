import pandas as pd
import sys
import math
import numpy as np
import os
from scipy.stats import gmean
import time

from getpass import getuser
if getuser() == 'strUser':
    SDG_REPO = "/homes/strUser/sdg-capstone-paper-2015"
if getuser() == 'strUser':
    SDG_REPO = '/homes/strUser/sdgs/sdg-capstone-paper-2015'
if getuser() == 'strUser':
    SDG_REPO = ('/ihme/code/test/strUser/under_development'
                '/sdg-capstone-paper-2015')
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test

# move to qry
# get_indicator_table method

def fetch_input_file_dict():
    """Create a dictionary from indicator_id to a clean data file.

    Filters to only indicator status 1, those that are used to calculate the
    SDG Index.

       Returns
       .......
       input_file_dict : dict
           Dictionary from indicator_id to clean input data file.

    """
    indic_table = qry.get_indicator_table()
    # keep only status 1
    input_files = indic_table.query('indicator_status_id==1')
    # keep columns used for dictionary
    input_files = input_files[['indicator_id', 'clean_input_data_file']]
    # set the index as indicator_id so to_dict knows what the key is
    input_files = input_files.set_index('indicator_id').to_dict()
    # and then tell it what the values column is, and return
    input_file_dict = input_files['clean_input_data_file']
    return input_file_dict


def fetch_indicators(sdg_version, force_recompile=False):
    """Fetch all indicator data and save in shared scratch space.
    
    Uses dictionary from indicator_id to a filepath, which is 
    assumed to point to an hdf5 file that does exist. Loops over
    indicator ids in the dictionary keys and uses the key as the
    indicator id in the dataframe. Assigning indicator ids in 
    this way allows flexibility in the indicator id that any given
    dataset in the input data directory is assigned.

    Writes output to version specific directory so that if same version
    is rerun this is unnecessary.

    Parameters
    ----------
    sdg_version: int or str
        Determines where to look for data, and where to save compiled data.
    force_recompile: bool
        If version doesnt exist, will always recompile. If it does exist, this
        determines whether to recompile.

    Returns
    -------
    df : pandas DataFrame
        Compiled data with columns indicator_id, location_id, year_id, draw_0, 
        ..., draw_i, ..., draw_i+1, ... , draw_999 

    """
    # write/read output here
    version_dir = "{idd}/{v}".format(idd=dw.INDICATOR_DATA_DIR, v=sdg_version)
    out_file = version_dir + "/all_indicators.h5"
    if os.path.exists(out_file) and not force_recompile:
        print "reading from existing file"
        df = pd.read_hdf(out_file)
    else:
        print "recompiling"
        # get an input_file dict to determine where to read data for each 
        # indicator
        input_file_dict = fetch_input_file_dict()
        # list of dataframes for fast concatenation
        dfs = []
        for indicator_id in input_file_dict.keys():
            print "\t{}".format(indicator_id)
            # read indicator data file
            df = pd.read_hdf(input_file_dict[indicator_id])
            # set indicator id to the key in the dict
            df['indicator_id'] = indicator_id
            # keep & verify required columns
            df = df[dw.INDICATOR_ID_COLS + dw.DRAW_COLS]
            # append to dataframe list
            dfs.append(df)
        df = pd.concat(dfs, ignore_index=True)

        # make version directory if it doesnt exist yet (likely)
        if not os.path.exists(version_dir):
            os.mkdir(version_dir)
        # save the input dictionary as a pickle for convenience
        pd.to_pickle(input_file_dict, version_dir + "/input_file_dict.pickle")
        # write all the indicator data to the version directory
        df.to_hdf(version_dir + "/all_indicators.h5",
                  format="table",
                  key="data",
                  data_columns=dw.INDICATOR_ID_COLS)
    # return
    return df


def multi_year_avg(df, indicator_id, window=5):
    """Calculate a moving average for an indicator.

    Functionally used for the disaster indicator so that it can be less noisy.

    Replaces values for the given indicator with the five year moving average
    for that indicator. Requires all years from 1990-2015 to be present for
    that indicator.

    Parameters
    ----------
    df : pandas DataFrame
        Expected to contain dw.INDICATOR_ID_COLS and dw.DRAW_COLS

    Returns
    -------
    df : pandas DataFrame
        Contains the same columns, with less years for the given indicator.

    """
    avg_df = df.ix[df['indicator_id'] == indicator_id]
    # make sure single years are available for calculation or this is probably
    #  going to be worthless
    assert set(avg_df.year_id.unique()) == set(range(1990, 2016, 1)), \
        'Needed years for calculation are not present.'
    # calculate avg by setting year to be the same for all averaged years
    avg_df['year_id'] = avg_df['year_id'].apply(
        lambda year: (year + (window - (year % window))) \
        if year % window !=0 else year
    )
    # get the mean
    avg_df = avg_df.groupby(
        dw.INDICATOR_ID_COLS, 
        as_index=False
    )[dw.DRAW_COLS].mean()
    df = df.ix[df['indicator_id'] != indicator_id]
    df = df.append(avg_df, ignore_index=True)
    return df


def clean_compiled_indicators(df):
    """Merge with indicator metadata and filter to desired locations and years.

    Filters to SDG reporting locations and SDG reporting years.

    Parameters
    ----------
    df : pandas DataFrame
        Expected to contain dw.INDICATOR_ID_COLS and dw.DRAW_COLS

    Returns
    -------
    out : pandas DataFrame
        Contains additional columns invert and scale.
    """

    # replace disaster with multi year moving average
    df = multi_year_avg(df, 1019)

    indic_table = qry.get_indicator_table()
    df = df.merge(indic_table[['indicator_id', 'invert',
        'scale', 'indicator_stamp']], how='left')
    assert df.invert.notnull().values.all(), 'merge with indicator meta fail'

    # get sdg locations and filter to these
    sdg_locs = set(qry.get_sdg_reporting_locations().location_id)
    df = df.ix[df['location_id'].isin(sdg_locs)]

    # filter to sdg reporting years (move this to global in config file)
    sdg_years = range(1990, 2016, 5)
    df = df.ix[df['year_id'].isin(sdg_years)]

    # make sure each id column is an integer
    for id_col in dw.INDICATOR_ID_COLS:
        df[id_col] = df[id_col].astype(int)

    # return
    return df


def scale_infinite(df):
    """Scale infinitely scaled indicators"""
    df = df.copy()
    df.ix[:, dw.DRAW_COLS] = df.groupby('indicator_id')[dw.DRAW_COLS].transform(
        lambda x: (np.log(x) - np.log(x.min())) / ((np.log(x.max()) - np.log(x.min())))
    )
    df = df.reset_index()
    return df


def scale_proportions(df):
    """Scale proportionally scaled indicators."""
    df = df.copy()
    df.ix[:, dw.DRAW_COLS] = df.groupby('indicator_id')[dw.DRAW_COLS].transform(
        lambda x: (x - x.min()) / (x.max() - x.min())
    )
    df = df.reset_index()
    return df


def fill_zeros(df, zero_replace_method):
    """Fill zeros in rates"""
    df = df.copy()
    if zero_replace_method == 'fixed':
        # replace any value below or equal to zero with a very low number
        df.ix[:, dw.DRAW_COLS] = df.ix[:, dw.DRAW_COLS].applymap(
            lambda x: 1e-20 if x<=0 else x
        )
    elif zero_replace_method == 'min_by_indicator':
        t = df.applymap(lambda x: np.NaN if x<=0 else x)
        g = t.groupby('indicator_id')
        fill_vals = g[dw.DRAW_COLS].transform(
            lambda x: np.nanmin(x.values) / 2
        )
        df = t.fillna(fill_vals)
    else:
        raise ValueError(
            "Unimplemented zero replace method: {}".format(zero_replace_method)
        )
    return df


def scale_indicators(df, zero_replace_method='fixed'):
    """Scale indicators, differently for proportion vs infinite."""
    
    props = df.query('scale=="proportion"')
    rates = df.query('scale=="infinite"')
    
    rates = fill_zeros(rates, zero_replace_method)

    inf_scaled = scale_infinite(rates)
    props_scaled = scale_proportions(props)
    df = pd.concat([inf_scaled, props_scaled], ignore_index=True)
    max_val = df[dw.DRAW_COLS].values.max()
    min_val = df[dw.DRAW_COLS].values.min()
    assert max_val <= 1, \
        'The scaled values should not be greater than 1: {}'.format(max_val)
    assert df[dw.DRAW_COLS].values.min() >= 0, \
        'The scaled values should not be less than 0: {}'.format(min_val)
        
    # invert so that 1 is good, 0 is bad
    df.ix[:, dw.DRAW_COLS] = df.ix[:, dw.DRAW_COLS].apply(lambda x: abs(df['invert'] - x))
    
    # get rid of invert column cause its WORTHLESS NOW
    df = df[dw.INDICATOR_ID_COLS + dw.DRAW_COLS]
    
    return df
    

def add_composite_index(df, indicator_ids, index_id, floor=0.01,
                        method='geom_by_target'):
    """Calculate and append an index, using given method
    
    Parameters
    ----------
        df: pandas DataFrame
            has given structure:
            [id_cols] : [value_cols]
            [dw.INDICATOR_ID_COLS] : [dw.DRAW_COLS]
        indicator_ids : array-like
            A collection of indicator_ids that can be transformed into a set.
            All of these must be present in df, and these will be combined
            using the given method.
           index_id : int
               The indicator_id to assign to the new composite.
        method : str
            method to use, with the following accepted values:
                geom_by_indicator: geometric mean of all indicators
                geom_by_target: hierarchical geometric mean of
                    indicators then targets
                arith_by_indicator: arithmetic mean of all indicators
        floor : float
            Replace any values lower than this with this floor before
            calculating the index.
    
    Returns
    -------
        out: pandas DataFrame
            all original data and new observations
            that contain the index value by location-year
    """

    # filter to the given indicator ids to calculate index from
    ids_missing_from_data = set(indicator_ids) - set(df.indicator_id)
    assert len(ids_missing_from_data) == 0, \
        'need these to calculate: {}'.format(ids_missing_from_data)
    idx_df = df.copy().ix[df['indicator_id'].isin(indicator_ids)]

    # add the targets if method is geom_by_target
    if method == 'geom_by_target':
        indic_table = qry.get_indicator_table()
        indicator_targets = indic_table[['indicator_id', 'indicator_target']]
        idx_df = idx_df.merge(indicator_targets, how='left')
        assert idx_df.indicator_target.notnull().values.all(), \
            'indicator target merge fail'

    # set the indicator_id
    idx_df['indicator_id'] = index_id
    
    # Establish a floor for calculation purposes
    idx_df.ix[:, dw.DRAW_COLS] = idx_df.ix[:, dw.DRAW_COLS].applymap(
        lambda x: floor if x<=floor else x
    )
    
    # calculate the index based on method
    if method == 'geom_by_indicator':
        idx_df = idx_df.groupby(
            dw.INDICATOR_ID_COLS, as_index=False
        ).agg(gmean)
    elif method == 'geom_by_target':
        # first get geometric means within the targets
        idx_df = idx_df.groupby(
            dw.INDICATOR_ID_COLS + ['indicator_target'], as_index=False
        ).agg(gmean)
        idx_df = idx_df.drop('indicator_target', axis=1)
        # then calculate the geometric means of those targets
        idx_df = idx_df.groupby(
            dw.INDICATOR_ID_COLS, as_index=False
        ).agg(gmean)
    elif method == 'arith_by_indicator':
        idx_df = idx_df.groupby(
            dw.INDICATOR_ID_COLS, as_index=False
        ).mean()
    else:
        raise ValueError(
            'unimplemented index calculation method: {}'.format(method)
        )
    df = df.append(idx_df, ignore_index=True)
    return df[dw.INDICATOR_ID_COLS + dw.DRAW_COLS]


def collapse_to_means(df):
    """Replace all draws in the df with the mean & confidence intervals.

    Parameters
    ----------
    df : pandas DataFrame
        Contains all INDICATOR_ID_COLS & DRAW_COLS as definted in config
        script, dw.

    Returns
    -------
    df : pandas DataFrame
        Contains all INDICATOR_ID_COLS, and DRAW_COLS are 
        collapsed to mean_val, upper, and lower.
    """
    df = df[dw.INDICATOR_ID_COLS + dw.DRAW_COLS].set_index(dw.INDICATOR_ID_COLS)
    # calculate mean & 95% confidence interval bounds with shared index
    mean_val = df.mean(axis=1)
    mean_val.name = "mean_val"
    upper_val = df.quantile(q=0.975, axis=1)
    upper_val.name = "upper"
    lower_val = df.quantile(q=0.025, axis=1)
    lower_val.name = "lower"
    # concatenate using shared index
    idf = pd.concat([mean_val, upper_val, lower_val], axis=1).reset_index()
    return idf


def compile_output(df, add_rank = False, collapse_means=True):
    """Compile output for writing.

    Calculates means, adds metadata, and orders columns.
    Optionally calculates rank by sdg index.

    Parameters
    ----------
    df : pandas DataFrame
        Contains dw.INDICATOR_ID_COLS and dw.DRAW_COLS
    add_rank : bool
        Determines whether to add rank calculation. Needs SDG index.

    Returns
    -------
    df : pandas DataFrame
        dataframe with draws collapsed and lots more metadata

    """
    # collapse draws to means
    if collapse_means:
        df = collapse_to_means(df)

    # test that the data is square
    #sdg_test.df_is_square_on_indicator_location_year(df)

    # add indicator metadata
    indic_table = qry.get_indicator_table()
    indic_table = indic_table[['indicator_id', 'indicator_short',
                                'indicator_stamp', 'indicator_paperorder']]
    df = df.merge(indic_table, how='left')
    assert df.indicator_stamp.notnull().values.all(), \
        'merge with indic table failed'

    # add location metadata
    locs = qry.get_sdg_reporting_locations()
    locs = locs[['location_id', 'location_name', 'ihme_loc_id']]
    df = df.merge(locs, how='left')
    assert df.location_name.notnull().values.all(), \
        'merge with locations failed'
    print 'Number of locations: {}'.format(len(df.location_id.unique()))

    # make sure its just reporting years
    df = df.ix[df.year_id.isin(range(1990, 2016, 5))]

    # set column order
    col_order = ['indicator_id', 'location_id', 'year_id', 'indicator_short',
                 'indicator_stamp', 'indicator_paperorder', 
                 'ihme_loc_id', 'location_name',
                 'rank', 'mean_val', 'upper', 'lower']

    # optionally add rank by sdg index
    if add_rank:
        # keep sdg index
        sdg_index = df.query('indicator_id==1054')
        # calculate rank
        sdg_index['rank'] = sdg_index.groupby('year_id').mean_val.transform(
            lambda x: pd.Series.rank(x, method='first', ascending=False)
        )
        # add it to the data
        df = df.merge(
            sdg_index[['location_id', 'year_id', 'rank']].drop_duplicates(),
            how='left'
        )
        assert df['rank'].notnull().values.all(), 'merge failed'
        return df[col_order]
    else:
        col_order.remove('rank')
        return df[col_order]

def write_output(df, sdg_version, scale_type, overwrite_current=False):
    """Write output for the sdg version."""
    df.to_csv(
        "{dir}/indicator_values/" \
        "indicators_{t}_{v}.csv".format(
            dir=dw.PAPER_OUTPUTS_DIR, t=scale_type, v=sdg_version
        ),
        index=False
    )
    if overwrite_current:
        df.to_csv("{dir}/indicators_{t}.csv".format(
            dir=dw.PAPER_OUTPUTS_DIR, t=scale_type
            ),
            index=False
        )


def compile_unscaled(sdg_version, write_compiled=True):
    """Do everything for SDG index calculation"""
    # get the sdg data
    print "Reading indicator data for version {}".format(sdg_version)
    df = fetch_indicators(sdg_version, force_recompile=True)
    # clean the indicator data
    print "cleaning data"
    df = clean_compiled_indicators(df)

    # Filter to 188 GBD nationals only by removing UK subnats
    UK_subnats = set([433, 434, 4749, 4636])
    keep = list(set(df.location_id.unique()) - UK_subnats)
    df = df.loc[df.location_id.isin(keep), :]

    # done with unscaled values, can write these
    print "compiling unscaled output"
    draw_outfile= "{d}/indicators_unscaled_draws_{v}.h5".format(
            d=dw.SUMMARY_DATA_DIR,
            v=sdg_version
            )
    df.to_hdf(draw_outfile,
              format="table",
              key="data",
              data_columns=['indicator_id', 'location_id', 'year_id']
    )
    df.to_csv("/home/j/temp/strUser/"\
              "for_r_scaling_{v}.csv".format(v=sdg_version),
              index=False)
    if write_compiled:
        unscaled_output = compile_output(df)
        write_output(unscaled_output, sdg_version, "unscaled")
    return df

def compile_scaled(sdg_version):
    """Scaled unscaled data (eventually with boxcox transformation)"""

    print "Scaling data"
    df = scale_indicators(df)

    print "Calculating SDG index"
    indic_table = qry.get_indicator_table()
    sdg_ids = set(indic_table.query('indicator_status_id==1').indicator_id)
    df = add_composite_index(df, sdg_ids, 1054, method='geom_by_target')

    print "Calculating MDG Index"
    mdg_ids = set(indic_table.query(
        'indicator_status_id==1 & mdg_agenda==1'
        ).indicator_id)
    df = add_composite_index(df, mdg_ids, 1055, method='geom_by_target')

    print "Calculating Non-MDG Index"
    non_mdg_ids = set(indic_table.query(
        'indicator_status_id==1 & mdg_agenda==0'
        ).indicator_id)
    df = add_composite_index(df, non_mdg_ids, 1060, method='geom_by_target')

    print "Compiling scaled output"
    draw_outfile= "{d}/indicators_scaled_draws_{v}.h5".format(
            d=dw.SUMMARY_DATA_DIR,
            v=sdg_version
            )
    df.to_hdf(draw_outfile,
              format="table",
              key="data",
              data_columns=['indicator_id', 'location_id', 'year_id']
    )
    return df


def read_scaled_from_r(sdg_version):
    """Get the scaled data from r, which was run on Windows"""
    # wait for R to finish
    r_out_path = "/home/j/temp/strUser/" \
                 "indicators_scaled_draws_{v}.csv".format(v=sdg_version)
    while not os.path.exists(r_out_path):
        print "No R output: {}, checking again in 60 seconds".format(r_out_path)
        time.sleep(60)
    time.sleep(60) # Wait another minute to make sure file has time to finish saving

    print "output found and reading from R"
    df = pd.read_csv(r_out_path)
    draw_outfile= "{d}/indicators_scaled_draws_{v}.h5".format(
            d=dw.SUMMARY_DATA_DIR,
            v=sdg_version
            )
    print "writing output from r"
    df.to_hdf(draw_outfile,
              format="table",
              key="data",
              data_columns=['indicator_id', 'location_id', 'year_id']
    )
    return df
    

def main(sdg_version, r_doing_scaling=True, skip_unscaled=True):
    
    # get unscaled data together for the version
    if not skip_unscaled:
        compile_unscaled(sdg_version)
    
    if r_doing_scaling:
        df = read_scaled_from_r(sdg_version)
    else:
        df = compile_scaled(sdg_version)
    print "compiling, writing output"
    scaled_output = compile_output(df, add_rank = True)
    print scaled_output.indicator_id.unique()
    write_output(scaled_output, sdg_version, "scaled")
    return scaled_output
    print "Done"


if __name__ == "__main__":
    sdg_version = sys.argv[1]
    main(sdg_version)
