import pandas as pd
import sys

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry


# read asfr file
print 'reading input file...'
df = pd.read_csv("{d}/asfr_10_19.csv".format(d=dw.ASFR_DIR))


# DRAW NAME STANDARDS
# rename asfr_draw_X to draw_X like others
print 'cleaning...'
df = df.rename(columns=lambda x: x.replace('asfr_draw', 'draw'))
# shift from 1-1000 to 0-999
df = df.rename(columns={'draw_1000': 'draw_0'})

# AGE STANDARDIZE
weights = qry.get_age_weights(ref_pop=3)
weights = weights.ix[weights['age_group_id'].isin([7, 8])]
weights['age_group_weight_value'] = weights['age_group_weight_value'] / \
    weights.age_group_weight_value.sum()

df = df.merge(weights, how='left')
assert df.age_group_weight_value.notnull().values.all(), \
    'merge failed'
id_cols = ['location_id', 'year_id', 'sex_id',
           'age_group_id', 'measure_id', 'metric_id']
# just call this a continuous rate? idk
df['measure_id'] = 18
df['metric_id'] = 3
df['age_group_id'] = 27
df = pd.concat([df[id_cols], df[dw.DRAW_COLS].apply(
    lambda x: x * df['age_group_weight_value'])],
    axis=1)
df = df.groupby(id_cols, as_index=False)[dw.DRAW_COLS].sum()

print 'writing...'
df.to_hdf("{d}/asfr_clean.hdf".format(d=dw.ASFR_DIR),
          key="data", format="table",
          data_columns=['location_id', 'year_id'])
print 'done'
