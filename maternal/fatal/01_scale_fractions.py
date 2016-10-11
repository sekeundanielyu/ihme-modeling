##########################################################################
# Description: We need to make sure that cause fractions sum to one, both
# across sub-causes and across sub-times. Here, we proportionately
# rescale cause fractions for each country-age-year so they sum
# correctly.
# Note: Since 'late' is both a sub-cause and a sub-time, we first
# rescale subcauses, then 'freeze' the late cause fractions when
# we scale the sub-times (which is after codcorrect is run).
# Input: log_dir: directory for where you want log files to be saved
# jobname: to be used to name the current logging file
# dismod_dir: parent directory where all dismod draw files are stored
# cluster_dir: parent directory where scaled output files will be stored
# year: year of interest
# Output: A .csv saved to the directory specified, with scaled datasets for the
# year and location specified.
##########################################################################

import sys
import pandas as pd
import os
import maternal_fns
from PyJobTools import rlog
from db_tools import dbapis
from python_emailer import server, emailer

if os.path.isdir('J:/'):
    j = 'J:'
elif os.path.isdir('/home/j/'):
    j = '/home/j'
else:
    print 'Where am I supposed to go?'

##############################################
# PREP WORK:
# set directories and other preliminary data
##############################################

print 'starting job!'

log_dir, jobname, dismod_dir, cluster_dir, year = sys.argv[1:6]

year = int(year)

# logging
rlog.open('%s/%s.log' % (log_dir, jobname))
rlog.log('Starting scale fractions step')

# get list of locations
locations = maternal_fns.get_locations()
geo_length = len(locations)

# set up database
enginer = dbapis.engine_factory()

# set up columns we want to subset
columns = maternal_fns.filter_cols()

# get dependency_map
dep_map = pd.read_csv(
    "dependency_map.csv", header=0).dropna(axis='columns', how='all')

# subset dep_map for the step that we're on
if "timing" in jobname:
    step_df = dep_map[(dep_map.step == 4) &
                      (dep_map.source_id != 'codcorrect')]
else:
    step_df = dep_map.ix[dep_map.step == 1]

###############################################################################
# SET WHERE CAUSE FRACTIONS COME FROM
# dismod_dir: data for all dismod years, for all subcauses/timings
# cluster_dir: data for all interpolated years, for all subcauses/timings
#    exceptions: step 4 outputs Late timing for ALL years including Dismod
#                years) into the cluster_dir. AND COD uploads ALL years of
#                HIV into the dismod directory, so no need to interpolate
###############################################################################

rlog.log("setting where cause fractions come from")
for index, row in step_df.iterrows():
    # official dismod years: get data from dismod output
    if year in range(1990, 2020, 5):
        if row['source_type'] != 'process':  # everything except late
            dismod_me_id = row['source_id']
            dismod_model_vers = maternal_fns.get_model_vers(
                'dismod', dismod_me_id)
            cf_in_dir = '%s/%s/full/draws' % (dismod_dir, dismod_model_vers)
        else:
            cf_in_dir = '%s/%s' % (cluster_dir, row['source_id'])  # late
    # interpolated years: get data from where I've saved them in interpolation
    else:
        if row['source_id'] == '9015':  # hiv was never interpolated.
            dismod_me_id = row['source_id']
            dismod_model_vers = maternal_fns.get_model_vers(
                'dismod', dismod_me_id)
            cf_in_dir = '%s/%s/full/draws' % (dismod_dir, dismod_model_vers)
        else:
            cf_in_dir = '%s/%s' % (cluster_dir, row['source_id'])
    step_df.loc[index, 'in_dir'] = cf_in_dir
    cf_out_dir = '%s/%s' % (cluster_dir, row['target_id'])
    step_df.loc[index, 'out_dir'] = cf_out_dir

for geo_idx, geo in enumerate(locations):

    rlog.log('running analysis for location_id %s' % geo)
    rlog.log('%s is country number %s of %s' % (geo, geo_idx, geo_length))

    #######################################################################
    # STEP 1: FOR EACH CAUSE, EXTRACT FILES, GET SUM BY GROUP + TOTAL SUM
    #######################################################################

    all_data = {}

    summed_idx = 0

    rlog.log('getting data')

    for index, row in step_df.iterrows():

        cf_in_dir = row['in_dir']
        target_id = row['target_id']
        if dismod_dir in cf_in_dir:
            filetype = 'hdf'
        else:
            filetype = 'csv'

        # the same subtype, 'Late', is used both as a subcause and a subtime.
        # To make the cause fractions (and thus, the total # of deaths) in this
        # group the same across methods of stratification, we squeeze the '
        # subcause' cause fractions to 1 as usual, then, after codcorrect, take
        # those squeezed values of 'Late' and hold them as fixed in the 'time'
        # analysis, squeezing the others around them.

        # similarly HIV is held constant in the scaling for subcauses

        fname = '%s_%s_2' % (geo, year)
        # if we're on the 'late' timing
        if len(step_df) == 4 and row['source_type'] == 'process':
            get_late_dir = '%s/%s.csv' % (cf_in_dir, fname)
            Late_df = pd.read_csv(get_late_dir)

            # we only want maternal age groups
            Late_df = Late_df[Late_df.age_group_id.isin(range(7, 16))]

            # we only want age_group_id and draws as columns; age as index
            Late_df = Late_df[columns].set_index('age_group_id').sort()
        # if we're on the 'hiv' cause
        elif row['source_id'] == '9015':
            get_hiv_dir = '%s/all_draws' % (cf_in_dir)
            hiv_df = pd.read_hdf("%s.h5" % get_hiv_dir, 'draws',
                                 where=[('location_id == %s & year_id == %s'
                                         '& sex_id == 2') % (geo, year)])

            # we only want maternal age groups
            hiv_df = hiv_df[hiv_df.age_group_id.isin(range(7, 16))]

            # we only want age_group_id and draws as columns; age as index
            hiv_df = hiv_df[columns].set_index('age_group_id').sort()
        else:
            subtype_fname = '%s/%s' % (cf_in_dir, fname)

            if filetype == 'csv':
                subtype_df = pd.read_csv("%s.csv" % subtype_fname)
            else:
                subtype_df = pd.read_hdf("%s.h5" % subtype_fname, 'draws')

            # we only want maternal age groups
            subtype_df = subtype_df[subtype_df.age_group_id.isin(range(7, 16))]

            # we only want age_group_id and draws as columns; age as index
            subtype_df = subtype_df[columns].set_index('age_group_id').sort()

            # save this dataframe, and also sum it to all other subtypes
            all_data[target_id] = subtype_df

            # note that we do not include Late_df in the sum of subtimes,
            # of hiv_df in the sum of subcauses to ease calculation later
            if summed_idx == 0:
                all_data['Summed_Subtypes'] = subtype_df
            else:
                all_data['Summed_Subtypes'] = (all_data['Summed_Subtypes'] +
                                               subtype_df)

            summed_idx += 1
    print all_data.keys()
    #######################################################################
    # STEP 2: DIVIDE EACH DATASET BY THE TOTAL SUM TO GET PROPORTIONS
    #######################################################################

    rlog.log('dividing to get proportions')
    final_data = {}

    # for the 'by time' analysis, we want:
    # (Ante + Intra + Post)/Q + Late = 1,
    # So Q = (Ante + Intra + Post)/(1-Late).
    # Then for HIV, Q = (all subcauses)/(1-HIV)
    # Here, we generate Q for use later.

    if len(step_df) == 4:
        complement_late = Late_df.applymap(lambda x: 1 - x)
        Q = all_data['Summed_Subtypes'] / complement_late
    else:
        complement_hiv = hiv_df.applymap(lambda x: 1 - x)
        Q = all_data['Summed_Subtypes'] / complement_hiv

    for index, row in step_df.iterrows():
        target_id = row['target_id']
        print target_id
        if len(step_df) == 4:  # if we're on timings
            if row['source_type'] == 'process':  # if we're on late timing
                final_data[target_id] = Late_df
            else:
                final_data[target_id] = all_data[target_id] / Q
        else:
            if row['source_id'] == '9015':  # if we're on HIV cause
                final_data[target_id] = hiv_df
            else:
                final_data[target_id] = all_data[target_id] / Q

        # make sure output directory exists
        output_dir = row['out_dir']
        out_fname = '18_%s_%s_2' % (geo, year)
        out_dir = '%s/%s.csv' % (output_dir, out_fname)
        rlog.log('saving %s to %s' % (target_id, out_dir))

        final_data[target_id].to_csv(out_dir, encoding='utf-8')

    # make sure subtypes sum to 1 (ish); send the user an  email otherwise
    epsilon = 0.00001
    summed = sum(final_data.itervalues())
    abs_diff = summed.applymap(lambda x: abs(1 - x))
    not_right = abs_diff[abs_diff > epsilon].dropna()

    if not not_right.empty:

        s = server('smtp.uw.edu')
        s.set_user('User@uw.edu')
        s.set_password('Password')
        s.connect()

        e = emailer(s)
        user = os.environ.get("USER")
        me = '%s@uw.edu' % user
        e.add_recipient('%s' % me)

        e.set_subject('PROBLEM WITH CFS')
        e.set_body('CAUSE FRACTIONS DO NOT SUM TO one FOR YEAR %s & GEO %s'
                   % (year, geo))

        e.send_email()
        s.disconnect()

rlog.log('Finished!')
