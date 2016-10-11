
##########################################################################
# Description: This code simply takes a cause fraction file and takes an
# envelope file, and multiplies them together to come up with
# estimated deaths to each subtype.
# Input: year: year of interest
# log_dir: directory for where you want log files to be saved
# jobname: to be used to name the current logging file
# envelope_dir: directory of envelope files from codem or
# codcorrect
# prop_dir: directory of cause fractions
# out_dir: directory for where to save final death count datasets
# Output: A .csv saved to the directory specified, with final death count
# datasets for the year and location specified.
##########################################################################

from __future__ import division
import pandas as pd
import os
import fnmatch
import sys
import maternal_fns
import concurrent.futures as cf
from PyJobTools import rlog

if os.path.isdir('J:/'):
    j = 'J:'
elif os.path.isdir('/home/j/'):
    j = '/home/j'
else:
    print 'Where am I supposed to go?'

log_dir, jobname, envelope_dir, prop_dir, out_dir = sys.argv[1:6]

# get list of locations
locations = maternal_fns.get_locations()

# logging
rlog.open('%s/%s.log' % (log_dir, jobname))
rlog.log('out_dir is %s' % out_dir)

# set up columns we want to subset
columns = maternal_fns.filter_cols()
columns.append('year_id')
index_cols = ['year_id', 'age_group_id']

# concatenate dalynator draws into one df, if we're doing timings
if "timing" in jobname:
    files = []
    for root, dirnames, filenames in os.walk('%s' % envelope_dir):
        for filename in fnmatch.filter(filenames, '*.h5'):
            files.append(os.path.join(root, filename))

    def read_file(f):
        return pd.read_hdf(f, 'data', where=[("'cause_id'==366"
                                              "& 'measure_id'==1"
                                              "& 'metric_id'==1 & 'sex_id'==2"
                                              "& 'rei_id'==0")])

    draw_list = []
    with cf.ProcessPoolExecutor(max_workers=14) as e:
        for df in e.map(read_file, files):
            draw_list.append(df)
    daly_draws = pd.concat(draw_list)
    daly_draws.reset_index(inplace=True)

for geo in locations:

    # envelope
    # CAUSES get multiplied by the Late corrected env from codem,
    # which is saved by save-results as cause_id/deaths_female.h5,
    # with location_id, year_id inside
    # TIMINGS get multiplied by the dalynator env, which is saved as
    # draws_{loc}_{year}.h5, with cause_ids, measure_ids, metric_ids, and even
    # rei_id inside, along with age_group_ids and sex_ids. I loaded it above.
    if "timing" in jobname:
        env = daly_draws.query("location_id==%s" % geo)
    else:
        env_fname = '%s/deaths_female.h5' % envelope_dir
        env = pd.read_hdf('%s' % env_fname, 'data',
                          where=[("'location_id'==%d" % geo)])
    # we only want maternal age groups
    env = env[env.age_group_id.isin(range(7, 16))]
    # we only want index cols & draws as columns, w multiindex
    env = env[columns].set_index(index_cols).sort()

    # cfs
    cf_fname = '%s/all_draws.h5' % prop_dir
    rlog.log('cf file is %s' % cf_fname)
    try:
        cfs = pd.read_hdf('%s' % cf_fname, 'draws',
                          where=["'location_id'==%s" % geo])
    except IOError:  # sometimes the system gets overloaded and can't read
        cfs = pd.read_hdf('%s' % cf_fname, 'draws',
                          where=["'location_id'==%s" % geo])
    # we only want maternal age groups
    cfs = cfs[cfs.age_group_id.isin(range(7, 16))]
    # we only want index cols & draws as columns, w multiindex
    cfs = cfs[columns].set_index(index_cols).sort()

    # multiply to get final deaths
    final_deaths = cfs * env
    final_deaths.reset_index(inplace=True)

    # add in necessary columns for save_results
    final_deaths['location_id'] = geo
    final_deaths['sex_id'] = 2
    final_deaths['measure_id'] = 1
    # gbd_id = int(jobname.split("_")[-1])
    # if "timing" in jobname:
    #     final_deaths['modelable_entity_id'] = gbd_id
    # else:
    #     final_deaths['cause_id'] = gbd_id

    # save
    yearvals = final_deaths.year_id.unique()
    # dfs = []
    # for year in yearvals:
    #     dfs.append(final_deaths.loc[final_deaths.year == year]
    #                .copy(deep=True))

    # def write_file(df):
    #     year = df.year_id.unique()
    #     df.to_hdf('%s/%s_%s_2.h5' % (out_dir, geo, year),
    #               'draws', format='table', mode='w', data_columns=[
    #               'measure_id', 'location_id', 'year_id', 'age_group_id',
    #               'sex_id'])

    # with cf.ProcessPoolExecutor(max_workers=14) as e:
    #     e.map(write_file, dfs)

    for year in yearvals:
        single_y = final_deaths.query("year_id==%s" % year)
        if "timing" in jobname:
            single_y.to_hdf('%s/%s_%s_2.h5' % (out_dir, geo, year),
                            'draws', format='table', mode='w', data_columns=[
                            'measure_id', 'location_id', 'year_id',
                            'age_group_id', 'sex_id'])
        else:
            single_y.to_csv('%s/death_%s_%s_2.csv' % (out_dir, geo, year),
                            index=False, encoding='utf-8')

rlog.log('Finished!')
