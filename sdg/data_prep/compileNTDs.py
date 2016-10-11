import pandas as pd
import sys
from scipy.stats import gmean

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw

INDICATOR_ID_COLS = ['location_id', 'year_id']

def compile_df_using_dict(input_file_dict):
    """Compile dataframe together using dictionary indicator_id-->file"""
    dfs = []
    for indicator_id in input_file_dict.keys():
        print indicator_id
        df = pd.read_hdf(input_file_dict[indicator_id])
        df = df[INDICATOR_ID_COLS + dw.DRAW_COLS]
        dfs.append(df)
    df = pd.concat(dfs, ignore_index=True)
    return df

def get_child_indicators(indic_table, parent_stamp):
    """Use indicator table filepaths to pull ntd data"""
    tbl_rows = indic_table.ix[
        (indic_table['indicator_stamp'].str.startswith(parent_stamp)) & \
        (indic_table['indicator_level']==3)
    ]
    input_file_dict = tbl_rows[
        ['indicator_id', 'clean_input_data_file']
    ].set_index('indicator_id').to_dict()['clean_input_data_file']
    df = compile_df_using_dict(input_file_dict)
    return df

def compile_sum(indic_table, parent_stamp,
                assert_0_1=False):
    """Sum together the children of the given parent.
    
    Optionally assert that values are between 0 and 1.
    """
    df = get_child_indicators(indic_table, parent_stamp)
    df = df.groupby(INDICATOR_ID_COLS)[dw.DRAW_COLS].sum()
    if assert_0_1:
        assert df.applymap(lambda x: x>0 and x<1).values.all(), \
            'sum produced rates outside of realistic bounds'
    df = df.reset_index()
    return df

def compile_ncds(indic_table):
    """Compile together aggregate indicators for NTDs and NCDs"""
    print 'NCDS'
    ncds = compile_sum(indic_table, 'i_341', assert_0_1=True)
    out_path = "/ihme/scratch/projects/sdg/input_data/dalynator/{}/ncds.h5".format(dw.DALY_VERS)
    ncds.to_hdf(out_path, key="data", format="table",
                data_columns=['location_id', 'year_id'])

def compile_ntds(indic_table):
    print 'NTDs'
    ntds = compile_sum(indic_table, 'i_335', assert_0_1=False)
    # cant assert that prevalence is below 1 because it might be above
    assert (ntds[dw.DRAW_COLS] > 0).values.all(), 'values below 0 in ntds'
    out_path = "/ihme/scratch/projects/sdg/input_data/como_prev/{}/ntds.h5".format(dw.COMO_VERS)
    ntds.to_hdf(out_path, key="data", format="table",
                data_columns=['location_id', 'year_id'])
    
def compile_tb(indic_table):
    print 'TB'
    tb = compile_sum(indic_table, 'i_332')
    out_path = "/ihme/scratch/projects/sdg/input_data/como_inc/{}/tb.h5".format(dw.COMO_VERS)
    tb.to_hdf(out_path, key="data", format="table",
                data_columns=['location_id', 'year_id'])

indic_table = pd.read_csv(
    "/home/j/WORK/10_gbd/04_journals/"
    "gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv"
)

compile_ntds(indic_table)
compile_tb(indic_table)