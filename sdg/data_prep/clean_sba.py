
import pandas as pd
import sys

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.tests as sdg_test

# read
df = pd.read_csv(
    dw.SBA_PATH
)
# set metric to proportion
df['metric_id'] = 2
# save id columns
id_cols = ['location_id', 'year_id', 'age_group_id',
           'sex_id', 'metric_id', 'measure_id']
# keep necessary variables
df = df[id_cols + dw.DRAW_COLS]
# test
sdg_test.all_sdg_locations(gbd_id_df)
# convert to hdf
df.to_hdf(
    dw.SBA_OUT_PATH,
    format="table", key="data",
    data_columns=['location_id', 'year_id']
)
