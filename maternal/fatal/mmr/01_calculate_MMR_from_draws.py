import pandas as pd
import os
import sys
import fnmatch
import numpy as np
import concurrent.futures as cf
try:
    from db_tools import dbapis, query_tools
except:
    sys.path.append(str(os.getcwd()).rstrip('/mmr'))
    from db_tools import dbapis, query_tools

cause_id, year_id, process_v, out_dir = sys.argv[1:5]
year_id = int(year_id)
cause_id = int(cause_id)
process_v = int(process_v)

enginer = dbapis.engine_factory()
enginer.servers["gbd"] = {"prod": "modeling-gbd-db.ihme.washington.edu"}
enginer.define_engine(engine_name='gbd_prod', server_name="gbd",
                      default_schema='gbd', envr='prod',
                      user='USER', password='PASSWORD')
enginer.servers["mortality"] = {"prod":
                                "modeling-mortality-db.ihme.washington.edu"}
enginer.define_engine(engine_name='mort_prod', server_name="mortality",
                      default_schema='mortality', envr='prod',
                      user='USER', password='PASSWORD')
index_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
ages = range(7, 16) + [24, 169]


def add_cols(df):
    df['measure_id'] = 25
    df['metric_id'] = 3
    df['cause_id'] = cause_id
    return df

# get best dalynator version
query = ('SELECT  '
         'distinct(val) AS daly_id '
         'FROM '
         'gbd.gbd_process_version_metadata gpvm '
         'JOIN '
         'gbd.gbd_process_version USING (gbd_process_version_id) '
         'JOIN '
         'gbd.compare_version_output USING (compare_version_id) '
         'WHERE '
         'compare_version_id = (SELECT '
         'compare_version_id '
         'FROM '
         'gbd.compare_version '
         'WHERE '
         'compare_version_status_id = 1 '
         'AND gbd_round_id = 3) '
         'AND gpvm.metadata_type_id = 5')
model_vers = query_tools.query_2_df(
    query, engine=enginer.engines["gbd_prod"]).loc[0, 'daly_id']

# load dalynator draws for the appropriate cause
dalynator_dir = '/ihme/centralcomp/dalynator/%s/draws/hdfs/' % model_vers
files = []
for root, dirnames, filenames in os.walk('%s' % dalynator_dir):
    for filename in fnmatch.filter(filenames, '*%s.h5' % year_id):
        files.append(os.path.join(root, filename))


def read_file(f):
    return pd.read_hdf(f, 'data', where=[("'cause_id'==%d & 'measure_id'==1"
                                          "& 'metric_id'==1 & 'sex_id'==2"
                                          "& 'rei_id'==0") % cause_id])

draw_list = []
with cf.ProcessPoolExecutor(max_workers=14) as e:
    for df in e.map(read_file, files):
        draw_list.append(df)
draws = pd.concat(draw_list)

draws.reset_index(inplace=True)
draws = draws[draws.age_group_id.isin(ages)]
draws['location_id'] = draws['location_id'].astype('int')
draws['age_group_id'] = draws['age_group_id'].astype('int')
draws['sex_id'] = draws['sex_id'].astype('int')
draws['year_id'] = draws['year_id'].astype('int')

# aggregate and add a teenage death age group
teenage_deaths = draws.copy(deep=True)
teenage_deaths = teenage_deaths[teenage_deaths.age_group_id.isin(range(7, 9))]
teenage_deaths['age_group_id'] = 162  # 10to19
daly_idx = ['location_id', 'year_id', 'age_group_id', 'sex_id', 'cause_id',
            'rei_id', 'metric_id', 'measure_id']
teenage_deaths = (teenage_deaths.groupby(daly_idx).sum().reset_index())
draws = draws.append(teenage_deaths)

# load live births
print "loading live births"
query = ('SELECT '
         'model.location_id, model.year_id, model.age_group_id, model.sex_id, '
         'model.mean_value AS asfr FROM covariate.model '
         'JOIN covariate.model_version ON model.model_version_id=model_version'
         '.model_version_id JOIN covariate.data_version ON model_version'
         '.data_version_id=data_version.data_version_id JOIN shared.covariate '
         'ON data_version.covariate_id=covariate.covariate_id '
         'WHERE covariate.last_updated_action!="DELETE" AND is_best=1 '
         'AND covariate.covariate_id= 13 AND model.age_group_id '
         'BETWEEN 7 AND 15 AND model.year_id > 1989')
asfr = query_tools.query_2_df(query, engine=enginer.engines["cov_prod"])
asfr['sex_id'] = 2

query = ('SELECT location_id, year_id, age_group_id, sex_id, mean_pop '
         'FROM mortality.output '
         'WHERE output_version_id = '
         '(SELECT output_version_id FROM mortality.output_version WHERE '
         'is_best = 1)')
pop = query_tools.query_2_df(query, engine=enginer.engines["mort_prod"])

births = asfr.merge(pop, on=index_cols, how='inner')
births['births'] = births['asfr'] * births['mean_pop']
sds_births = births.copy(deep=True)


def format_births(df):
    index_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
    birth_column = ['births']
    keep_columns = index_cols + birth_column
    return df[keep_columns]

################################
# Aggregate up Cod and Outputs
################################
# get cod and outputs location hierarchy
print "getting location hierarchy"
query = ('SELECT '
         'location_id, level, parent_id, most_detailed, location_type_id '
         'FROM '
         'shared.location_hierarchy_history lhh '
         'JOIN '
         'shared.location_set_version lsv USING (location_set_version_id) '
         'WHERE '
         'lhh.location_set_id = 35 AND '
         'lsv.gbd_round = 2015 AND '
         'lsv.end_date IS NULL')
loc_df = query_tools.query_2_df(query, engine=enginer.engines["cod_prod"])

# load regional scalars for cod and outputs location aggregation
print "loading and reshaping regional scalars"
region_locs = loc_df[loc_df["location_type_id"] == 6]['location_id'].tolist()
scalar_list = []
root_dir = '/home/j/WORK/10_gbd/01_dalynator/02_inputs/region_scalars'
folders = os.listdir(root_dir)
folders = filter(lambda a: 'archive' not in a, folders)
folders.sort()
inner_folder = int(folders[-1])
scalar_dir = '%s/%d' % (root_dir, inner_folder)

for geo in region_locs:
    for year in range(1990, 2016):
        scalar_df = pd.read_stata('%s/%s_%s_scaling_pop.dta'
                                  % (scalar_dir, geo, year))
        scalar_list.append(scalar_df)
scalar = pd.concat(scalar_list)
scalar = scalar[scalar.age_group_id.isin(range(7, 16))]

# get most detailed locations
print "getting most-detailed locations"
most_detailed = (loc_df.ix[loc_df['most_detailed'] == 1]['location_id']
                 .drop_duplicates().tolist())

# check for missing locations
print "checking missing locations"
birth_locations = births.merge(loc_df,
                               on='location_id',
                               how='left')
birth_loc_list = (birth_locations[birth_locations.most_detailed == 1
                                  ]['location_id']
                  .drop_duplicates().tolist())
if len(set(most_detailed) - set(birth_loc_list)) > 0:
    print ("The following locations are missing from the draws %s"
           % (', '.join([str(x) for x in list(set(most_detailed) -
                                              set(birth_loc_list))])))
else:
    print "No missing locations!"

# merge on cod and outputs location hierarchy
print "merging on location hierarchy"
births = format_births(births)
data = births.copy(deep=True)
data = data.ix[data['location_id'].isin(most_detailed)]
data = pd.merge(data, loc_df,
                on='location_id',
                how='left')
max_level = data['level'].max()
print max_level

data = format_births(data)
# loop through cod and outputs levels and aggregate
for level in xrange(max_level, 0, -1):
    print "Level:", level
    data = pd.merge(data, loc_df[['location_id',
                                  'level',
                                  'parent_id']],
                    on='location_id',
                    how='left')
    temp = data.ix[data['level'] == level].copy(deep=True)
    if level == 2:  # if we're at the region level, use regional scalars
        temp = pd.merge(temp, scalar, on=['location_id',
                                          'year_id',
                                          'age_group_id',
                                          'sex_id'],
                        how='inner')
        temp['births'] = temp['births'] * temp['scaling_factor']
        temp.drop('scaling_factor', axis=1, inplace=True)
    temp['location_id'] = temp['parent_id']
    temp = format_births(temp)
    temp = temp.groupby(index_cols).sum().reset_index()
    data = pd.concat([format_births(data), temp]).reset_index(drop=True)
births = data.copy(deep=True)

################################
# Aggregate up SDS Comp Hierarchy
################################
# get sds computation hierarchy
print "getting sds location hierarchy"
query = ('SELECT '
         'location_id, level, parent_id, most_detailed, location_type_id '
         'FROM '
         'shared.location_hierarchy_history lhh '
         'JOIN '
         'shared.location_set_version lsv USING (location_set_version_id) '
         'WHERE '
         'lhh.location_set_id = 40 AND '
         'lsv.gbd_round = 2015 AND '
         'lsv.end_date IS NULL')
sds_loc_df = query_tools.query_2_df(query, engine=enginer.engines["cod_prod"])

sds_only = (sds_loc_df.ix[sds_loc_df['level'] == 0]['location_id']
            .drop_duplicates().tolist())
sds_most_detailed = (sds_loc_df.ix[sds_loc_df['most_detailed'] == 1]
                     ['location_id']
                     .drop_duplicates().tolist())

# check for missing locations
print "checking missing locations"
sds_locations = sds_births.merge(sds_loc_df,
                                 on='location_id',
                                 how='left')
sds_loc_list = (sds_locations[sds_locations.most_detailed == 1]['location_id']
                .drop_duplicates().tolist())
if len(set(sds_most_detailed) - set(sds_loc_list)) > 0:
    print ("The following locations are missing from the draws %s"
           % (', '.join([str(x) for x in list(set(sds_most_detailed) -
                                              set(sds_loc_list))])))
else:
    print "No missing locations!"

# merge on sds location hierarchy
print "merging on location hierarchy"
sds_births = format_births(sds_births)
sds_data = sds_births.copy(deep=True)
sds_data = sds_data.ix[sds_data['location_id'].isin(sds_most_detailed)]
sds_data = pd.merge(sds_data, sds_loc_df,
                    on='location_id',
                    how='left')
max_level = sds_data['level'].max()
print max_level

# loop through sds hierarchy levels and aggregate
sds_data = format_births(sds_data)
for level in xrange(max_level, 0, -1):
    print "Level:", level
    sds_data = pd.merge(sds_data, sds_loc_df[['location_id',
                                              'level',
                                              'parent_id']],
                        on='location_id',
                        how='left')
    temp = sds_data.ix[sds_data['level'] == level].copy(deep=True)
    temp['location_id'] = temp['parent_id']
    temp = format_births(temp)
    temp = temp.groupby(index_cols).sum().reset_index()
    sds_data = (pd.concat([format_births(sds_data), temp])
                .reset_index(drop=True))
sds_births = sds_data.copy(deep=True)
sds_births = sds_births[sds_births.location_id.isin(sds_only)]

################################
# Add on SDS to other locs
################################
births_all = pd.concat([births, sds_births])
births = births_all.copy(deep=True)

################################
# Aggregating ages and appending
################################
# aggregate births for all maternal-ages
print "aggregating births for all-ages"
all_ages = births.copy(deep=True)
who_ages = births.copy(deep=True)
teen_ages = births.copy(deep=True)
who_ages = who_ages[who_ages.age_group_id.isin(range(8, 15))]
teen_ages = teen_ages[teen_ages.age_group_id.isin(range(7, 9))]
all_ages['age_group_id'] = 169  # 10to54
who_ages['age_group_id'] = 24  # 15to49
teen_ages['age_group_id'] = 162  # 10to19
all_ages = (all_ages.groupby(index_cols).sum().reset_index())
who_ages = (who_ages.groupby(index_cols).sum().reset_index())
teen_ages = (teen_ages.groupby(index_cols).sum().reset_index())
births = births.append(all_ages)
births = births.append(who_ages)
births = births.append(teen_ages)
births = format_births(births)

################################
# Save live births flat file for
# tables and figures, but do this
# just once, not for every
# parallelized job
################################
if cause_id == 366 and year_id == 2015:
    births_csv = births.copy(deep=True)
    journal_dir = ('/home/j/WORK/10_gbd/04_journals/gbd2015_capstone_'
                   'lancet_maternal/02_inputs/live_births')
    births_csv.to_csv('%s/live_births_mmr%s.csv'
                      % (journal_dir, process_v), index=False)

################################
# Merge births and deaths
################################
print "merging births and deaths"
draws = draws.merge(births, on=index_cols, how='inner')
draws.drop(['cause_id', 'rei_id', 'metric_id', 'measure_id'],
           axis=1, inplace=True)
arc_draws = draws.copy(deep=True)
arc_out_dir = out_dir.rstrip("/single_year")
arc_draws.to_csv('%s/arc_draws_raw_%s_%s.csv'
                 % (arc_out_dir, cause_id, year_id),
                 index=False)

################################
# Output MMR
################################
# get mean, upper, lower deaths
print "getting mean, upper, lower"
draws.set_index(index_cols, inplace=True)
summary = draws.filter(like='draw_', axis=1)
summary = summary.transpose().describe(
    percentiles=[.025, .975]).transpose()[['mean', '2.5%', '97.5%']]
summary.rename(
    columns={'2.5%': 'lower', '97.5%': 'upper'}, inplace=True)
summary.index.rename(['location_id', 'year_id', 'age_group_id', 'sex_id'],
                     inplace=True)
summary.reset_index(inplace=True)
final_draws = draws[['births']]
final_draws.reset_index(inplace=True)
final_draws = final_draws.merge(summary, how='inner', on=index_cols)

# calculate mean, upper, lower mmr from mean, upper, lower deaths + births
stats = ['mean', 'upper', 'lower']
for stat in stats:
    final_draws['MMR_%s' % stat] = ((final_draws['%s' % stat] /
                                     final_draws['births']) * 100000)
final_draws.drop(['births', 'mean', 'upper', 'lower'], axis=1, inplace=True)
final_draws.rename(columns={'MMR_mean': 'val',
                            'MMR_upper': 'upper',
                            'MMR_lower': 'lower'}, inplace=True)

# export
print "exporting"
final_draws = add_cols(final_draws)
final_draws.replace([np.inf, -np.inf, np.nan], 0, inplace=True)
final_draws.to_csv('%s/mmr_from_draws_%s_%s.csv'
                   % (out_dir, cause_id, year_id),
                   encoding='utf-8', index=False)
