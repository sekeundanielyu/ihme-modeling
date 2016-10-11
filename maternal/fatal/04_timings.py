
##########################################################################
# Date created: 10/30/15
# Description: Dalynator outputs deaths draws for the full dalynator maternal
#              envelope, as well as for each of the subcauses. Because late is
#              a subcause that becomes a timing, we divide late by the full
#              env, for each location and year, to get late cause fractions.
#              The output of this will be used as a frozen part of the scaling
#              of all the timings. Later we will save these to the cluster_dir
#              using the modelable_entity_id that we will use to upload the
#              scaled version of this to the epi database
# Input: log_dir: directory for where you want log files to be saved
#        year: year of interest
#        dalynator_dir: directory where dalynator death draw results are stored
#        env_id: cause_id of all maternal disorders
#        late_id: cause_id of the late cause
#        output_dir: directory for where to save Late cause fractions
# Output: A .csv saved to the directory specified, with Late cause fractions
#         for the year and location specified.
##########################################################################

import sys
import pandas as pd
import maternal_fns
from PyJobTools import rlog

##############################################
# PREP WORK:
# set directories and other preliminary data
##############################################

log_dir, year, dalynator_dir, env_id, late_id, out_dir = sys.argv[1:7]

year = int(year)
env_id = int(env_id)
late_id = int(late_id)
cause = [env_id, late_id]

# get list of locations
locations = maternal_fns.get_locations()

# set up columns we want to subset
columns = maternal_fns.filter_cols()

# logging
rlog.open('%s/dalynator_late_%s.log' % (log_dir, year))
rlog.log('')
rlog.log('Starting to get late cause fractions')

##############################################
# GET LATE CAUSE FRACTIONS:
##############################################
for geo in locations:
    fname = 'draws_%s_%s.h5' % (geo, year)

    # dalynator files are saved as loc/year, with age, sex and cause inside
    try:
        dalynator_df = pd.read_hdf('%s/%s/%s' % (dalynator_dir, geo, fname),
                                   'data',
                                   where=[("'cause_id'==%s & 'measure_id'==1"
                                           "& 'metric_id'==1 & 'sex_id'==2"
                                           "& 'rei_id'==0") % cause])
    except:
        print "%s_%s" % (geo, year)
        raise

    # we only want maternal age groups
    dalynator_df = dalynator_df[dalynator_df.age_group_id.isin(range(7, 16))]

    # we only want women
    dalynator_df = dalynator_df[dalynator_df.sex_id == 2]

    # subset env dataframe for results from only the maternal disorders
    # cause_id
    envelope_df = dalynator_df[dalynator_df.cause_id == env_id]
    # subset late dataframe for results from only the late cause cause_id
    late_df = dalynator_df[dalynator_df.cause_id == late_id]

    # we only want age_group_id and draws as columns, with age_group_id as
    # index
    envelope_df = envelope_df[columns].set_index('age_group_id').sort()
    late_df = late_df[columns].set_index('age_group_id').sort()

    # calculate late cause fractions
    rlog.log('Calculating late cfs for geo %s and year %s' % (geo, year))
    late_cfs = late_df / envelope_df

    out_fname = '%s/%s_%s_2.csv' % (out_dir, geo, year)

    # save late cause fractions
    late_cfs.to_csv(out_fname, encoding='utf-8')
