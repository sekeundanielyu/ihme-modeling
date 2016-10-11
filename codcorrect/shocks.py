import pandas as pd
from codcorrect.core import Envelope, read_json
from codcorrect.io import import_cod_model_draws, read_envelope_draws
from codcorrect.error_check import tag_zeros, check_data_format, missing_check, exclusivity_check
from codcorrect.restrictions import expand_id_set
import logging
import codcorrect.log_utilities as l
import argparse
import sys

"""
    This script does the following:
      -Reads in best CoD shock draws
      -Saves file for Mortality team
      -Saves HDF file

"""

def parse_args():
    '''
        Parse command line arguments

        Arguments are output_version_id, location_id, and sex_name

        Returns all 3 arguments as a tuple, in that order
    '''
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_version_id", type=str)
    parser.add_argument("--location_id", type=str)
    parser.add_argument("--sex_name", type=str)

    args = parser.parse_args()
    output_version_id = args.output_version_id
    location_id = args.location_id
    sex_name = args.sex_name

    return output_version_id, location_id, sex_name


def read_helper_files(parent_dir, location_id, sex_name):
    ''' Read in and return helper DataFrames.

        Returns:
        best_models: DataFrame containing all best model ids
                     and relevant cause metadata for a given sex
        eligible_data: a DataFrame containing all demographics
                       and their restriction status
    '''
    logger = logging.getLogger('shocks.read_helper_files')
    sex_dict = {1: 'male', 2: 'female'}

    # Config file
    logger.info('Reading config file')
    config = read_json(parent_dir + r'/_temp/config.json')

    # List of best models for shocks
    logger.info('Reading best models')
    best_models = pd.read_csv(parent_dir + r'/_temp/best_models.csv')
    best_models['sex_name'] = best_models['sex_id'].map(lambda x: sex_dict[x])
    best_models = best_models.ix[(best_models['sex_name'] == sex_name)&(best_models['model_version_type_id'].isin(range(5,8)))]

    return config, best_models


def read_all_model_draws(best_models, required_columns, filter_years=None):
    """
        Reads in all CODEm models for a specific
        sex and location_id

        Also logs which models it couldn't open

        returns:
        a DataFrame with the CODEm draws
    """
    # Read in best models
    data = []
    for i in best_models.index:
        model_version_id = int(best_models.ix[i, 'model_version_id'])
        acause = best_models.ix[i, 'acause']
        temp_data = import_cod_model_draws(model_version_id, location_id,
                                           acause, sex_name,
                                           required_columns)
        if filter_years:
            temp_data = temp_data.ix[temp_data['year_id'].isin(filter_years)]
        data.append(temp_data)

    data = pd.concat(data)

    # DataFrame shouldn't be empty
    logger = logging.getLogger('correct.read_all_model_draws')
    try:
        assert not data.empty, 'No best model data found'
    except AssertionError as e:
        logger.exception('No best model data found')
        sys.exit()

    return data


def save_draws(data, index_columns):
    """
       Saves draws wide in an h5 file. Converts from cause fractions
       to deaths first

       Returns
       None
    """
    logger = logging.getLogger('shocks.save_draws')

    # Save draws
    data = data.sort(index_columns).reset_index(drop=True)
    data.to_hdf(
        parent_dir + r'/unaggregated/shocks/shocks_{location_id}_{sex_name}.h5'.format(
            location_id=location_id,
            sex_name=sex_name),
            'draws', mode='w', format='table',
        data_columns=index_columns)



if __name__ == '__main__':

    # Get command line arguments
    output_version_id, location_id, sex_name = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'shocks', output_version_id, location_id, sex_name)

    # Sex dictionary
    sex_dict = {'male': 1, 'female': 2}
    sex_id = sex_dict[sex_name]

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, best_models = read_helper_files(parent_dir, location_id, sex_name)

        # Read in config variables
        eligible_year_ids = config['eligible_year_ids']
        index_columns = config['index_columns']
        data_columns = config['data_columns']
        raw_data_columns = index_columns + data_columns

        # Read in draw files
        print "Reading in best model draws"
        logging.info("Reading in best model draws")
        raw_data = read_all_model_draws(best_models, raw_data_columns, filter_years=eligible_year_ids)

        # Check formatting
        print "Checking best model draws"
        logging.info("Checking in best model draws")
        check_data_format(raw_data, raw_data_columns, fail=True)

        # Saving data
        print "Saving data"
        logging.info("Saving data")
        save_draws(raw_data, index_columns)
        logging.info('All done!')
    except:
        logging.exception('uncaught exception in shocks.py')
