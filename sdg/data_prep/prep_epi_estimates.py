import pandas as pd
import os
import glob
import sys

sys.path.append("/home/j/WORK/10_gbd/00_library/transmogrifier/")
import transmogrifier.gopher as gopher


from getpass import getuser
if getuser() == 'kutz13':
    SDG_REPO = "/homes/kutz13/sdg-capstone-paper-2015"
if getuser() == 'mollieh':
    SDG_REPO = "/homes/mollieh/sdgs/sdg-capstone-paper-2015"
if getuser() == strUser
    SDG_REPO = ('/ihme/code/test/strUser/under_development'
                '/sdg-capstone-paper-2015')
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test


def collect_childhood_overweight(force_repull=True):
    """Either run gopher to get the data or pull cached

    TODO IF NECESSARY GENERALIZE TO ALL ME IDS
    """
    vdir = "/ihme/scratch/projects/sdg/temp/epi/{v}".format(
        v=dw.EPI_CHILD_OVRWGT_VERS)
    if not os.path.exists(vdir):
        os.mkdir(vdir)

    path = "{d}/gopher_pull.hdf".format(d=vdir)
    if force_repull or not os.path.exists(path):
        try:
            os.mkdir(vdir)
        except:
            pass
        #df = gopher.draws({'modelable_entity_ids': [9363]}, 'epi',
        #                  location_ids=[], year_ids=[],
        #                  age_group_ids=[5],
        #                  model_version_id=dw.EPI_CHILD_OVRWGT_VERS,
        #                  num_workers=9
        #                  )
        
        # Temporary draw extraction
        dfs = []
        for name in glob.glob('/home/j/temp/pj/bmi/st_gpr_outputs/optimal_datasets/overweight_child/*.csv'):#('/share/covariates/ubcov/model/output/149/draws_temp/*.csv'):
            print name
            d = pd.read_csv(name)
            dfs.append(d)
        df = pd.concat(dfs)
        df['modelable_entity_id'] = 9363
        df['model_version_id'] = 149
        df = df.loc[df.age_group_id == 5, :]

        df.to_hdf(path, format="f", key="data")
    else:
        df = pd.read_hdf(path, "data")
    return df


def collapse_sex(df):
    """Convert prevalence to cases"""
    pops = qry.get_pops(both_sexes=False)
    df = df.merge(pops, how = 'left', on = ['location_id','age_group_id','sex_id','year_id'])

    draws = [col for col in df.columns if 'draw_' in col]
    id_cols = dw.EPI_CHILD_OVRWGT_GROUP_COLS
    # make sex 3 to collapse to both
    df['sex_id'] = 3
    # make metric id 1 to represent cases (will change when converted back to
    # rates)
    df['metric_id'] = 1
    # convert to cases by multiplying each draw by the population value
    df = pd.concat([df[id_cols],
                    df[draws].apply(lambda x: x * df['mean_pop'])
                    ], axis=1
                   )
    # sum sexes together
    df = df.groupby(id_cols, as_index=False)[draws].sum()
    return df


def add_sdi_aggregates(df):
    """IMPLEMENT LATER"""
    return df


def convert_to_rates(df):
    """Convert back to rates by merging on pop"""
    pops = qry.get_pops(both_sexes=True)
    df = df.merge(pops, how = 'inner')#how='left')
    assert df.mean_pop.notnull().values.all(), 'pop merge failed'
    id_cols = dw.EPI_CHILD_OVRWGT_GROUP_COLS
    draws = [col for col in df.columns if 'draw_' in col]
    df = pd.concat([
        df[id_cols],
        df[draws].apply(lambda x: x / df['mean_pop'])
    ], axis=1
    )
    df['metric_id'] = 3
    return df


if __name__ == "__main__":
    df0 = collect_childhood_overweight(force_repull=True)
    df1 = collapse_sex(df0)
    df2 = add_sdi_aggregates(df1)
    df3 = convert_to_rates(df2)
    # test that locations are present
    sdg_test.all_sdg_locations(df3)
    # todo generalize this filepath
    out_path = "/ihme/scratch/projects/sdg/input_data/" \
               "epi/{v}/9363.h5".format(v=dw.EPI_CHILD_OVRWGT_VERS)
    df3.to_hdf(
        out_path,
        key="data",
        format="table", data_columns=['location_id', 'year_id'])
