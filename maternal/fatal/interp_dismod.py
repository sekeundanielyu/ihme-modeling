##########################################################################
# Description: We need to interpolate dismod values between years to get a full
# time series. Given a start year t1 and an end year t2, with
# corresponding values v1 and v2, and a year t* for which you want
# to interpolate the value v*, you have:
# a = log(v2/v1) / (t2-t1) #log change
# v* = v1 * exp((t* - t1) * a) # interpolated value
# 'a' here refers to the (observed) log change over time for the
# two years for which you have data. Assuming that 'a' stays
# constant, you can get a new estimated value for any year using
# the second equation.
# This script performs this arithmetic by country-age.
# Input: log_dir: directory for where you want log files to be saved
# jobname: to be used to name the current logging file
# source_dir: directory containing the dismod outputs for your start
# and end years
# out_dir: directory where you want the interpolated files to be saved
# start_year_str: first year of interpolation data
# end_year_str: last year of interpolation data
# Output: A .csv saved to the location specified, with the interpolated
# datasets for the years and countries specified.
##########################################################################

from __future__ import division
import pandas as pd
import sys
from math import log, exp
import os
import maternal_fns
from PyJobTools import rlog

if os.path.isdir('J:/'):
    j = 'J:'
elif os.path.isdir('/home/j/'):
    j = '/home/j'
else:
    print 'Where am I supposed to go?'

log_dir, jobname, source_dir, out_dir, start_year_str, end_year_str = sys.argv[
    1:7]

start_year = int(start_year_str)
end_year = int(end_year_str)

# logging
rlog.open('%s/%s.log' % (log_dir, jobname))
rlog.log('source_dir is %s' % source_dir)
rlog.log('out_dir is %s' % out_dir)

# get list of locations
locations = maternal_fns.get_locations()

# set up columns we want to subset
columns = maternal_fns.filter_cols()

for geo_idx, geo in enumerate(locations):

    rlog.log('interpolating for place %s' % geo)
    rlog.log('place is number %s of %s' % (geo_idx, len(locations)))

    rlog.log('getting data')
    start_dir = '%s/%s_%s_2.h5' % (source_dir, geo, start_year)
    end_dir = '%s/%s_%s_2.h5' % (source_dir, geo, end_year)

    start = pd.read_hdf(start_dir, 'draws')
    # we only want age_group_id and draws as columns, with age_group_id as
    # index
    start = start[columns].set_index('age_group_id').sort()

    end = pd.read_hdf(end_dir, 'draws')
    # we only want age_group_id and draws as columns, with age_group_id as
    # index
    end = end[columns].set_index('age_group_id').sort()

    year_diff = end_year - start_year

    rlog.log('getting mean rate of change')
    meanstart = start.mean(axis=1)
    meanstart.replace(0, 1e-9, inplace=True)
    meanend = end.mean(axis=1)
    meanend.replace(0, 1e-9, inplace=True)

    # log change: this is assumed to stay constant for years being estimated
    # (we refer to this as 'a' in the documentation above)
    ln_change = (meanend / meanstart).apply(lambda x: log(x) / year_diff)

    # since we need estimates back to 1980, we use the 1990-1995 years to
    # back-calculate for 1980-1989
    if start_year == 1990:
        yearlist = range(1980, 1990) + range(1991, 1995)
    else:
        yearlist = range(start_year + 1, end_year)

    for year in yearlist:
        rlog.log('calculating interpolation for geo %s & year %s' %
                 (geo, year))
        # calculate interpolated estimates for each year
        exponent = ln_change.apply(lambda x: exp((year - start_year) * x))
        new_df = start.apply(lambda x: x * exponent, axis=0)

        # save files
        new_fname = '%s_%s_2' % (geo, year)
        year_out_dir = '%s/%s.csv' % (out_dir, new_fname)
        print "exporting to %s" % year_out_dir
        rlog.log('saving geo %s & year %s to %s' % (geo, year, year_out_dir))
        new_df.to_csv(year_out_dir, encoding='utf-8')
        print "exported"

rlog.log('Finished!')
