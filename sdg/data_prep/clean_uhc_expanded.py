import pandas as pd
import sys
import os

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.tests as sdg_test


version = '2016_08_12'
df = pd.read_csv(
    "/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_lancet_SDG/02_inputs/uhc_indicator/uhc_ind_var_post_sub.csv"
)
df = df.rename(columns=lambda x: x.replace('uhc_ind_var_', ''))
df['metric_id'] = 2
df['measure_id'] = 18
id_cols = ['location_id', 'year_id', 'age_group_id',
           'sex_id', 'metric_id', 'measure_id']
df = df[id_cols + dw.DRAW_COLS]

sdg_test.all_sdg_locations(df)

version_dir = "/ihme/scratch/projects/sdg/input_data/" \
              "uhc_clean/{v}".format(v=version)
if not os.path.exists(version_dir):
    os.mkdir(version_dir)

df.to_hdf(
    "{vd}/uhc_expanded_clean.h5".format(
        vd=version_dir),
    format="table",
    key="data",
    data_columns=['location_id', 'year_id']
)
