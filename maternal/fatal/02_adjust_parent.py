import pandas as pd
import maternal_fns
from db_tools import dbapis, query_tools
import sys
import os
from PyJobTools import rlog


if os.path.isdir('J:/'):
    j = 'J:'
elif os.path.isdir('/home/j/'):
    j = '/home/j'
else:
    print 'Where am I supposed to go?'

log_dir, jobname, envelope_dir, out_dir = sys.argv[1:5]

# do all the prep work
enginer = dbapis.engine_factory()
dep_map = pd.read_csv(
    "dependency_map.csv", header=0).dropna(axis='columns', how='all')
step_df = dep_map.ix[dep_map.step == 2].reset_index()
index_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']

# logging
rlog.open('%s/%s.log' % (log_dir, jobname))
rlog.log("Correcting for the underreporting of Late Maternal deaths")
rlog.log('out_dir is %s' % out_dir)

# get list of locations
locs = maternal_fns.get_locations()

# get list of location/years that don't need correction
rlog.log('Pulling in adjustment csv')
adjust_df = pd.read_csv('%s/late_maternal_correction.csv' % (os.getcwd()))
adjust_df = adjust_df[['location_id', 'year_id', 'subnationals', 'adj_factor']]

# get the adjustment factor for most-detailed level, not just countries
only_subnats = adjust_df[adjust_df.subnationals == 1]
only_subnats.rename(columns={'location_id': 'parent_id'}, inplace=True)

query = '''SELECT
    location_id, parent_id
FROM
    shared.location_hierarchy_history
WHERE
    location_set_id = 35
        AND location_set_version_id = (SELECT
            location_set_version_id
        FROM
            shared.location_set_version
        WHERE
            location_set_id = 35 AND end_date IS NULL)'''
lhh = query_tools.query_2_df(query, engine=enginer.engines['cod_prod'])
only_subnats = only_subnats.merge(lhh, on='parent_id', how='inner')
only_subnats.drop('parent_id', axis=1, inplace=True)
adjust_df = adjust_df[adjust_df.subnationals == 0]
adjust_df = pd.concat([adjust_df, only_subnats])

# get original codem envelope
env_fname = '%s/deaths_female.h5' % envelope_dir
rlog.log('envelope is %s' % env_fname)
env = pd.read_hdf('%s' % env_fname, 'data')

# we only want maternal age groups and most-detailed locations
env = env[(env.age_group_id.isin(range(7, 16))) & (env.location_id.isin(locs))]

# get prop from Late dismod model
query = ('''SELECT
    location_id, year_id, age_group_id, sex_id, mean
FROM
    epi.model_estimate_final
WHERE
    model_version_id = (SELECT
        model_version_id
    FROM
        epi.model_version
    WHERE
        modelable_entity_id = %s AND is_best = 1)'''
         % int(step_df.ix[0, 'source_id']))
prop = query_tools.query_2_df(query, engine=enginer.engines['epi_prod'])
prop = prop[(prop.age_group_id.isin(range(7, 16))) &
            (prop.location_id.isin(locs))]
prop.set_index(index_cols, inplace=True)
prop['prop'] = 1 / (1 - prop['mean'])
prop.drop('mean', axis=1, inplace=True)

# multiply every location/year that doesn't already have a adj_factor of 1, by
# 1/(1-scaledmean_lateprop)
env = env.merge(adjust_df, on=['location_id', 'year_id'], how='left')
env = env.set_index(index_cols)

env_not_adjust = env[env.adj_factor == 1]
env_adjust = env[env.adj_factor.isnull()]
env_not_adjust = env_not_adjust[['draw_%s' % i for i in xrange(1000)]]
env_adjust = env_adjust[['draw_%s' % i for i in xrange(1000)]]

env_adjust = env_adjust.merge(prop, left_index=True, right_index=True)
for i in xrange(1000):
    env_adjust['draw_%s' % i] = env_adjust['draw_%s' % i] * env_adjust['prop']
env_adjust.drop('prop', axis=1, inplace=True)

env = pd.concat([env_not_adjust, env_adjust])
env.reset_index(inplace=True)
env['cause_id'] = 366

rlog.log("Exporting to %s" % out_dir)
env.to_csv('%s/late_corrected_maternal_envelope.csv' % out_dir, index=False)
