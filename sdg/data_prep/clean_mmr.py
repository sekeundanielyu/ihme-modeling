# Do minimal cleaning necessary for MMR draws
# Save to input_data folder

import pandas as pd
import sys

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw

years = range(1990, 2016)
dfs = []
# draws are saved by year, 
# so pull each year and keep the 15-49 age group
for year in years:
    if year % 5 == 0:
        print year
    df = pd.read_csv(dw.MMR_DIR + "/draws_%s.csv" % year)
    df = df.query('age_group_id==24')
    dfs.append(df)
df = pd.concat(dfs, ignore_index=True)

# make sure it looks like we expect
assert set(df.cause_id) == {366}, 'unexpected cause ids'
assert set(df.sex_id) == {2}, 'unexpected sex ids'
assert set(df.age_group_id) == {24}, 'unexpected age group ids'
assert set(df.year_id) == set(range(1990, 2016)), 'unexpected year_ids'

# standardize columns
df['metric_id'] = 3
df['measure_id'] = 25
df = df[dw.MMR_ID_COLS + dw.DRAW_COLS]

df.to_hdf("{d}/366.h5".format(d=dw.MMR_OUTDIR), key="data",
          format="table",
          data_columns=['location_id', 'year_id'])
