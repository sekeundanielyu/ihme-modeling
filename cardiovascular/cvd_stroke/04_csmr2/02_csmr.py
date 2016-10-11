import pandas as pd
import sys
import stroke_fns
from epi_uploader.db_tools import dbapis, query_tools
import glob

# bring in args
dismod_dir, out_dir, year, acute_mv1, acute_mv2, chronic_mv = sys.argv[1:7]

# get ready for loop
sexes = [1, 2]
locations = stroke_fns.get_locations()
enginer = dbapis.engine_factory()
enginer.define_engine(
    engine_name='mortality_prod', host_key='mortality_prod',
    default_schema='mortality')
enginer.define_engine(
    engine_name='cod_prod', host_key='cod_prod',
    default_schema='shared')
keep_cols = (['draw_%s' % i for i in range(0, 1000)])
index_cols = ['location_id', 'sex_id', 'age_group_id']
all_cols = keep_cols + index_cols

all_acute_hem_list = []
all_acute_isch_list = []
all_chronic_list = []
for geo in locations:
    for sex in sexes:
        # get acute
        csmr_isch = pd.read_hdf(
            '%s/%s/full/draws/%s_%s_%s.h5' %
            (dismod_dir, acute_mv1, geo, year, sex),
            'draws', where=["'measure_id'==15 & 'age_group_id' != 27"])
        csmr_isch = csmr_isch[all_cols]
        csmr_hem = pd.read_hdf(
            '%s/%s/full/draws/%s_%s_%s.h5' %
            (dismod_dir, acute_mv2, geo, year, sex),
            'draws', where=["'measure_id'==15 & 'age_group_id' != 27"])
        csmr_hem = csmr_hem[all_cols]

        # get chronic
        chronic = pd.read_hdf(
            '%s/%s/full/draws/%s_%s_%s.h5' %
            (dismod_dir, chronic_mv, geo, year, sex),
            'draws', where=["'measure_id'==15 & 'age_group_id' != 27"])
        chronic = chronic[all_cols]

        # THIS SHOULDN'T BE NEEDED. KEEPING IT HERE JUST IN CASE
        # make new age group of 0-1
        # acute = acute.replace({'age_group_id': {2: 0, 3: 0, 4: 0}})
        # chronic = chronic.replace({'age_group_id': {2: 0, 3: 0, 4: 0}})
        # pop = pop.replace({'age_group_id': {2: 0, 3: 0, 4: 0}})
        # acute = acute.groupby('age_group_id').sum().reset_index()
        # chronic = chronic.groupby('age_group_id').sum().reset_index()
        # pop = pop.groupby('age_group_id').sum().reset_index()

        # append together all the lcations
        all_acute_hem_list.append(csmr_hem)
        all_acute_isch_list.append(csmr_isch)
        all_chronic_list.append(chronic)
all_acute_hem = pd.concat(all_acute_hem_list)
all_acute_isch = pd.concat(all_acute_isch_list)
all_chronic = pd.concat(all_chronic_list)

# get populations
query = ('SELECT location_id, age_group_id, sex_id, mean_pop '
         'FROM mortality.output '
         'WHERE output_version_id = '
         '(SELECT output_version_id '
         'FROM mortality.output_version '
         'WHERE is_best = 1 and best_end IS NULL) AND year_id = %s' % year)
all_pop = query_tools.query_2_df(query,
                                 engine=enginer.engines["mortality_prod"])
# turn rates to deaths
all_acute_hem = all_acute_hem.merge(all_pop, on=index_cols, how='inner')
all_acute_isch = all_acute_isch.merge(all_pop, on=index_cols, how='inner')
all_chronic = all_chronic.merge(all_pop, on=index_cols, how='inner')
for i in range(0, 1000):
    all_acute_hem['draw_%s' % i] = (all_acute_hem['draw_%s' % i] *
                                    all_acute_hem['mean_pop'])
    all_acute_isch['draw_%s' % i] = (all_acute_isch['draw_%s' % i] *
                                     all_acute_isch['mean_pop'])
    all_chronic['draw_%s' % i] = (all_chronic['draw_%s' % i] *
                                  all_chronic['mean_pop'])

# collapse to global
all_acute_hem.drop('mean_pop', axis=1, inplace=True)
all_acute_isch.drop('mean_pop', axis=1, inplace=True)
all_chronic.drop('mean_pop', axis=1, inplace=True)
all_acute_hem_global = all_acute_hem.groupby(
    ['sex_id', 'age_group_id']).sum().reset_index()
all_acute_isch_global = all_acute_isch.groupby(
    ['sex_id', 'age_group_id']).sum().reset_index()
all_chronic_global = all_chronic.groupby(
    ['sex_id', 'age_group_id']).sum().reset_index()

all_acute_hem_global.set_index(['sex_id', 'age_group_id'], inplace=True)
all_acute_isch_global.set_index(['sex_id', 'age_group_id'], inplace=True)
all_chronic_global.set_index(['sex_id', 'age_group_id'], inplace=True)

acute_hem_prop = all_acute_hem_global / (all_acute_hem_global +
                                         all_acute_isch_global +
                                         all_chronic_global)
acute_isch_prop = all_acute_isch_global / (all_acute_hem_global +
                                           all_acute_isch_global +
                                           all_chronic_global)
chronic_prop = all_chronic_global / (all_acute_hem_global +
                                     all_acute_isch_global +
                                     all_chronic_global)

acute_hem_prop.drop('location_id', axis=1, inplace=True)
acute_isch_prop.drop('location_id', axis=1, inplace=True)
chronic_prop.drop('location_id', axis=1, inplace=True)

# get codcorrect
query = ('SELECT output_version_id '
         'FROM cod.output_version WHERE is_best = 1 '
         'and best_end IS NULL')
cc_vers = query_tools.query_2_df(
    query, engine=enginer.engines["cod_prod"]).loc[0, 'output_version_id']
codcorrect_dir = '/strPath/%s/draws/' % cc_vers
codcorrect_list = []
for f in glob.glob(codcorrect_dir + '*.h5'):
    loc = int(f.split("_")[1].replace('.h5', ""))
    df = pd.read_hdf(f, 'draws',
                     where=["'cause_id'==494 & 'year_id'==%s" % year])
    df['location_id'] = loc
    codcorrect_list.append(df)
codcorrect = pd.concat(codcorrect_list)
codcorrect = codcorrect[all_cols]

# THIS SHOULDN'T BE NEEDED. KEEPING IT HERE JUST IN CASE
# make new age-group 0-1
# codcorrect = codcorrect.replace({'age_group_id': {2: 0, 3: 0, 4: 0}})
# codcorrect = codcorrect.groupby(index_cols).sum().reset_index()

# turn cod deaths into rates
codcorrect = codcorrect.merge(all_pop, on=index_cols, how='inner')
for i in range(0, 1000):
    codcorrect['draw_%s' % i] = (codcorrect['draw_%s' % i] /
                                 codcorrect['mean_pop'])
codcorrect.drop('mean_pop', axis=1, inplace=True)

# get rate chronic and rate acute
chronic_prop.reset_index(inplace=True)
acute_hem_prop.reset_index(inplace=True)
acute_isch_prop.reset_index(inplace=True)
rate_chronic = codcorrect.merge(chronic_prop, on=['sex_id', 'age_group_id'],
                                how='left')
rate_acute_hem = codcorrect.merge(acute_hem_prop,
                                  on=['sex_id', 'age_group_id'], how='left')
rate_acute_isch = codcorrect.merge(acute_isch_prop,
                                   on=['sex_id', 'age_group_id'], how='left')
for i in range(0, 1000):
    rate_chronic['rate_%s' % i] = (rate_chronic['draw_%s_x' % i] *
                                   rate_chronic['draw_%s_y' % i])
    rate_acute_hem['rate_%s' % i] = (rate_acute_hem['draw_%s_x' % i] *
                                     rate_acute_hem['draw_%s_y' % i])
    rate_acute_isch['rate_%s' % i] = (rate_acute_isch['draw_%s_x' % i] *
                                      rate_acute_isch['draw_%s_y' % i])
keep_cols = (['rate_%s' % i for i in range(0, 1000)])
all_cols = keep_cols + index_cols
rate_chronic = rate_chronic[all_cols].set_index(index_cols)
rate_acute_hem = rate_acute_hem[all_cols].set_index(index_cols)
rate_acute_isch = rate_acute_isch[all_cols].set_index(index_cols)

# get mean, upper, lower
rate_chronic = stroke_fns.get_summary_stats(rate_chronic, index_cols, 'mean')
rate_chronic.reset_index(inplace=True)
rate_acute_hem = stroke_fns.get_summary_stats(rate_acute_hem, index_cols,
                                              'mean')
rate_acute_hem.reset_index(inplace=True)
rate_acute_isch = stroke_fns.get_summary_stats(rate_acute_isch, index_cols,
                                               'mean')
rate_acute_isch.reset_index(inplace=True)

# save output by year
rate_chronic.to_csv('%s/rate_chronic_%s.csv' % (out_dir, year),
                    index=False, encoding='utf-8')
rate_acute_hem.to_csv('%s/rate_acute_hem_%s.csv' % (out_dir, year),
                      index=False, encoding='utf-8')
rate_acute_isch.to_csv('%s/rate_acute_isch_%s.csv' % (out_dir, year),
                       index=False, encoding='utf-8')
