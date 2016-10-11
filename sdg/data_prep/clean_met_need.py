import pandas as pd
import sys

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.tests as sdg_test


df = pd.read_csv(dw.MET_NEED_INFILE)

df['metric_id'] = 2

df = df[dw.MET_NEED_GROUP_COLS + dw.DRAW_COLS]

#sdg_test.all_sdg_locations(df)

df.to_hdf(dw.MET_NEED_OUTFILE, format="table", key="data",
          data_columns=['location_id', 'year_id'])
