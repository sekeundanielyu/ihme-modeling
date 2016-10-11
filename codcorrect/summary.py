import pandas as pd
import logging
from codcorrect.core import read_json
from codcorrect.io import read_hdf_draws
import codcorrect.log_utilities as l
import argparse
import sys
import datetime
import getpass

"""
This script generates summary files
"""

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_version_id", type=str)
    parser.add_argument("--location_id", type=str)

    args = parser.parse_args()
    output_version_id = args.output_version_id
    location_id = args.location_id

    return output_version_id, location_id


def read_helper_files(parent_dir, location_id):
    """ Read in and return helper DataFrames.

        Returns:
        DataFrame containing age_weights for age-standardized
        rate caluclation
    """

    # Age weights
    age_weights = pd.read_csv(parent_dir + r'/_temp/age_weights.csv')

    # Most-detailed location
    location_hierarchy = pd.read_csv(parent_dir + r'/_temp/location_hierarchy.csv')
    estimate_locations = location_hierarchy.ix[location_hierarchy['is_estimate']==1, 'location_id'].tolist()

    if int(location_id) in estimate_locations:
        most_detailed_location = True
    else:
        most_detailed_location = False

    return age_weights, most_detailed_location


def read_draw_files(parent_dir, location_id):
    """ Reads in draw files """
    logger = logging.getLogger('summary.read_draw_files')
    try:
        # Rescaled data
        draw_filepath = (parent_dir +
                         r'/aggregated/rescaled/rescaled_{location_id}.h5'.format(location_id=str(location_id))
                        )
        rescaled_draws = read_hdf_draws(draw_filepath, location_id).reset_index(drop=True)
        # DALYnator data
        draw_filepath = (parent_dir +
                         r'/draws/death_{location_id}.h5'.format(location_id=str(location_id))
                        )
        dalynator_draws = read_hdf_draws(draw_filepath, location_id).reset_index(drop=True)
    except Exception as e:
        logger.exception('Failed to read location: {}'.format(e))
    return rescaled_draws, dalynator_draws


def get_model_numbers(location_id, index_columns):
    """ Reads in model version ids """
    logger = logging.getLogger('summary.get_model_numbers')
    try:
        data = []
        for sex_name in ['male', 'female']:
            draw_filepath = (parent_dir +
                             r'/models/models_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
                            )
            data.append(read_hdf_draws(draw_filepath, location_id))
        data = pd.concat(data).reset_index(drop=True)
        data = data[index_columns + ['model_version_id']]
    except Exception as e:
        logger.exception('Failed to read model version data: {}'.format(e))
    return data


def generate_all_ages(data, index_columns):
    data = data.ix[data['age_group_id']!=22]
    temp = data.ix[((data['age_group_id']>=2)&
                    (data['age_group_id']<=21))].copy(deep=True)
    temp['age_group_id'] = 22
    temp = temp.groupby(index_columns).sum().reset_index()
    data = pd.concat([data, temp])
    return data

def generate_asr(data, index_columns, pop_column, data_columns, age_weights):
    temp = data.ix[((data['age_group_id']>=2)&
                    (data['age_group_id']<=21))].copy(deep=True)
    temp = pd.merge(data, age_weights, on=['age_group_id'])
    for c in data_columns:
        temp[c] = (temp[c] / temp[pop_column]) * temp['age_group_weight_value']
    temp['age_group_id'] = 27
    temp = temp.drop('age_group_weight_value', axis=1)
    temp = temp.groupby(index_columns).sum().reset_index()
    data = pd.concat([data, temp])
    return data


def generate_summaries(data, index_columns, data_columns):
    # Generate mean, lower, and upper
    data['mean_death'] = data[data_columns].mean(axis=1)
    data['lower_death'] = data[data_columns].quantile(0.025, axis=1)
    data['upper_death'] = data[data_columns].quantile(0.975, axis=1)
    data = data.ix[:, index_columns + ['mean_death', 'lower_death', 'upper_death']]
    return data

def generate_cause_fractions(data, index_columns, data_columns):
    temp = data.ix[(data['cause_id']==294)&(data['age_group_id']!=27)].copy(deep=True)
    temp = temp[['location_id', 'year_id', 'sex_id', 'age_group_id'] + ['draw_{}'.format(x) for x in xrange(1000)]]
    rename_columns = {'draw_{}'.format(x): 'env_{}'.format(x) for x in xrange(1000)}
    temp = temp.rename(columns=rename_columns)
    data = pd.merge(data, temp, on=['location_id', 'year_id', 'sex_id', 'age_group_id'])
    for x in xrange(1000):
        data['draw_{}'.format(x)] = data['draw_{}'.format(x)] / data['env_{}'.format(x)]
    rename_columns = {'{}_death'.format(x): '{}_cf'.format(x) for x in ['mean', 'lower', 'upper']}
    data = generate_summaries(data, index_columns, data_columns).rename(columns=rename_columns)
    return data


def save_summaries(data, index_columns, location_id):
    """
       Saves draws wide in an h5 file.

       Returns
       None
    """
    logger = logging.getLogger('summary.save_summaries')

    # Save draws
    data = data[['output_version_id',
                 'cause_id',
                 'year_id',
                 'location_id',
                 'sex_id',
                 'age_group_id',
                 'model_version_id',
                 'mean_cf',
                 'upper_cf',
                 'lower_cf',
                 'mean_death',
                 'upper_death',
                 'lower_death',
                 'mean_cf_with_shocks',
                 'upper_cf_with_shocks',
                 'lower_cf_with_shocks',
                 'mean_death_with_shocks',
                 'upper_death_with_shocks',
                 'lower_death_with_shocks',
                 'date_inserted',
                 'inserted_by',
                 'last_updated',
                 'last_updated_by',
                 'last_updated_action']]
    data.to_csv(
        parent_dir + r'/summaries/summary_{location_id}.csv'.format(
            location_id=location_id),
            index=False)



if __name__ == '__main__':

    # Get command line arguments
    output_version_id, location_id = parse_args()

    # Read in config file
    index_columns = ['location_id', 'year_id', 'sex_id', 'age_group_id', 'cause_id']
    data_columns = ['draw_{}'.format(x) for x in xrange(1000)]

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'summary', output_version_id, location_id, 'both')

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        age_weights, most_detailed_location = read_helper_files(parent_dir, location_id)
        print most_detailed_location

        # Read in models
        if most_detailed_location:
            print "Reading in model files"
            logging.info("Reading in model files")
            model_version_data = get_model_numbers(location_id, index_columns)

        # Read in draw file
        print "Reading in draw files"
        logging.info("Reading in draw files")
        rescaled_draws, dalynator_draws = read_draw_files(parent_dir, location_id)

        # Make all-ages
        print "Generate all-ages"
        logging.info("Generate all-ages")
        rescaled_draws = generate_all_ages(rescaled_draws, index_columns)
        dalynator_draws = generate_all_ages(dalynator_draws, index_columns)

        # Make age-standardized
        print "Generate age-standardized rates"
        logging.info("Generate age-standardized rates")
        pop_data = rescaled_draws.copy(deep=True)
        pop_data = pop_data.ix[pop_data['cause_id']==294]
        pop_data = pop_data[['location_id', 'year_id',
                             'sex_id', 'age_group_id'] + ['pop']]
        rescaled_draws = pd.merge(rescaled_draws.drop('pop', axis=1),
                                  pop_data,
                                  on=['location_id', 'year_id', 'sex_id',
                                      'age_group_id'],
                                  how='left')
        rescaled_draws = generate_asr(rescaled_draws, index_columns, 'pop',
                                      data_columns, age_weights)
        dalynator_draws = pd.merge(dalynator_draws.drop('pop', axis=1),
                                   pop_data,
                                   on=['location_id', 'year_id', 'sex_id',
                                       'age_group_id'],
                                   how='left')
        dalynator_draws['pop'] = dalynator_draws['pop'].fillna(0)
        dalynator_draws = generate_asr(dalynator_draws, index_columns, 'pop',
                                       data_columns, age_weights)

        # Make summaries
        print "Generate summaries"
        logging.info("Generate summaries")
        rescaled_summaries = generate_summaries(rescaled_draws, index_columns, data_columns)
        dalynator_summaries = generate_summaries(dalynator_draws, index_columns, data_columns)

        # Make cause fractions
        print "Generate cause fractions"
        logging.info("Generate cause fractions")
        rescaled_summaries = pd.merge(rescaled_summaries,
                                      generate_cause_fractions(rescaled_draws,
                                                               index_columns,
                                                               data_columns),
                                      on=index_columns,
                                      how='left')
        dalynator_summaries = pd.merge(dalynator_summaries,
                                       generate_cause_fractions(dalynator_draws,
                                                                index_columns,
                                                                data_columns),
                                       on=index_columns,
                                       how='left')

        # Merge on model_version_ids
        if most_detailed_location:
            print "Merge on model_version_ids"
            logging.info("Merge on model_version_ids")
            rescaled_summaries = pd.merge(rescaled_summaries, model_version_data, on=index_columns, how='left')
            rescaled_summaries['model_version_id'] = rescaled_summaries['model_version_id'].fillna(0)
        else:
            rescaled_summaries['model_version_id'] = 0

        # Merge with rescaled and DALYnator summaries together
        rename_columns = {}
        for t in ['cf', 'death']:
            for b in ['mean', 'lower', 'upper']:
                rename_columns['{}_{}'.format(b, t)] = '{}_{}_with_shocks'.format(b, t)
        dalynator_summaries = dalynator_summaries.rename(columns=rename_columns)
        data_summaries = pd.merge(rescaled_summaries, dalynator_summaries,
                                  on=index_columns, how='outer')

        # Format
        data_summaries['output_version_id'] = output_version_id
        data_summaries['date_inserted'] = datetime.datetime.now()
        data_summaries['inserted_by'] = getpass.getuser()
        data_summaries['last_updated'] = datetime.datetime.now()
        data_summaries['last_updated_by'] = getpass.getuser()
        data_summaries['last_updated_action'] = 'INSERT'

        # Save
        print "Save summaries"
        logging.info("Save summaries")
        save_summaries(data_summaries, index_columns, location_id)

        logging.info('All done!')
    except:
        logging.exception('uncaught exception in summary.py')
