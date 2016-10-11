import pandas as pd
from codcorrect.core import Envelope, read_json
from codcorrect.io import import_cod_model_draws, read_envelope_draws, save_hdf
from codcorrect.error_check import tag_zeros, check_data_format
from codcorrect.error_check import missing_check, exclusivity_check
from codcorrect.restrictions import expand_id_set
import logging
import codcorrect.log_utilities as l
import argparse
import sys

"""
    This script does the following:
      -Reads in best model CoD draws
      -Converts to cause fraction space
      -Rescales so cause fractions add up to 1 for
       a given level-parent_id group
      -Adjusts cause fractions based on the
       parent_id
      -Multiply cause fractions by latest version
       of the envelope to get corrected death
       numbers
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
    logger = logging.getLogger('correct.read_helper_files')
    sex_dict = {1: 'male', 2: 'female'}

    # Config file
    logger.info('Reading config file')
    config = read_json(parent_dir + r'/_temp/config.json')

    # List of best models (excluding shocks)
    logger.info('Reading best models')
    best_models = pd.read_csv(parent_dir + r'/_temp/best_models.csv')
    best_models['sex_name'] = best_models['sex_id'].map(lambda x: sex_dict[x])
    best_models = best_models.ix[(best_models['sex_name'] == sex_name)&
                                 (best_models['model_version_type_id'].isin(range(0,5)))]

    # List of eligible data
    logger.info('Reading eligible models')
    eligible_data = pd.read_csv(parent_dir + r'/_temp/eligible_data.csv')

    # Space-time restrictions
    spacetime_restriction_data = pd.read_csv(parent_dir+'/_temp/spacetime_restrictions.csv')

    # Envelope
    logger.info('Reading envelope draws')
    envelope_data = read_envelope_draws(parent_dir + r'/_temp/envelope.h5',
                                        location_id)
    rename_columns = {}
    for x in xrange(1000):
        rename_columns['env_{}'.format(x)] = 'draw_{}'.format(x)
    envelope_data = envelope_data.rename(columns=rename_columns)

    return config, best_models, eligible_data, spacetime_restriction_data, envelope_data


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
                                           required_columns,
                                           filter_years=filter_years)
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


def filter_zeros(data, data_columns):
    data = tag_zeros(data, data_columns, tag_column='zeros')
    return data.ix[data['zeros']==False].copy(deep=True)


def restrict_and_check(data, eligible_data, index_columns, data_columns, save_missing_filepath=None, save_overlap_filepath=None):
    """ Restricts data and the does checks of missing and overlapping data

    Restricts data down to eligible demographics, and then checks for missing
    data and checks for overlapping data

    Returns: Restricted DataFrame
    """

    logger = logging.getLogger('correct.restrict_and_check')
    try:
        for c in index_columns:
            eligible_data.ix[:, c] = eligible_data.ix[:, c].astype('int64')
            data.ix[:, c] = data.ix[:, c].astype('int64')

        # Merge with eligible data
        data = pd.merge(eligible_data[index_columns + ['restricted']],
                        data,
                        on=index_columns,
                        how='left')
        data.ix[:, data_columns] = data.ix[:, data_columns].fillna(0)
        # Restrict
        data = data.ix[data['restricted']==False].reset_index(drop=True)
        # Check missingness
        # missing_check(data, data_columns, save_missing_filepath=save_missing_filepath)
        missing_check(data, data_columns)
        # Check exclusivity
        exclusivity_check(data, index_columns, fail=True,
                          save_overlap_filepath=save_overlap_filepath)
    except Exception as e:
        logger.exception('Failed to restrict and check data: {}'.format(e))
        sys.exit()

    return data


def format_for_rescale(data, eligible_data, index_columns, data_columns, envelope_column, debug_folder, prefix):
    """ Runs all steps to take the raw data and prepare it to be rescaled """
    logger = logging.getLogger('correct.format_for_rescale')
    try:
        # Filter out zeros
        data = filter_zeros(data, data_columns)
        # Restrict
        data = restrict_and_check(data, eligible_data, index_columns, data_columns,
                                  save_missing_filepath=(debug_folder+'/missing_'+prefix+'.csv'),
                                  save_overlap_filepath=debug_folder+'/overlap_'+prefix+'.csv')
        # Get a copy of the model data
        model_data = data.ix[:, index_columns + ['model_version_id']].copy(deep=True)
        # Keep just the variables we need
        data = data.ix[:, index_columns + [envelope_column] + data_columns]
        # Convert to cause fractions
        for data_column in data_columns:
            data.eval('{d} = {d}/{e}'.format(d=data_column, e=envelope_column))
            data[data_column] = data[data_column].fillna(0)
        # Merge on hierarchy variables
        data = pd.merge(data,
                        eligible_data[index_columns + ['level', 'parent_id']],
                        on=index_columns, how='left')
        data = data.ix[:, index_columns + ['level', 'parent_id'] + data_columns]
    except Exception as e:
        logger.exception('Failed to format data for rescale: {}'.format(e))
        sys.exit()

    return data, model_data


def rescale_group(data, groupby_columns, data_columns):
    """ Rescale column to 1

    Takes a set of columns and rescales to 1 in groups defined by the groupby
    colunns.
    NOTE: the intermediate total column CANNOT have a value of 0 or else
          this can cause problems aggregating up the hierarchy later.  If
          this happens, make the all values within that group equal and
          resume.
    """
    # Make totals
    temp = data[groupby_columns + data_columns].copy(deep=True)
    temp = temp.groupby(groupby_columns)[data_columns].sum().reset_index()
    rename_columns = {'{}'.format(d): '{}_total'.format(d) for d in data_columns}
    temp = temp.rename(columns=rename_columns)
    # Attempt to rescale
    data = pd.merge(data, temp, on=groupby_columns)
    for data_column in data_columns:
        data.eval('{d} = {d}/{d}_total'.format(d=data_column))
    data = data.drop(['{}_total'.format(d) for d in data_columns], axis=1)
    # Fill in problem cells
    data[data_columns] = data[data_columns].fillna(1)
    # Remake totals
    temp = data[groupby_columns + data_columns].copy(deep=True)
    temp = temp.groupby(groupby_columns)[data_columns].sum().reset_index()
    temp = temp.rename(columns=rename_columns)
    # Rescale
    data = pd.merge(data, temp, on=groupby_columns)
    for data_column in data_columns:
        data.eval('{d} = {d}/{d}_total'.format(d=data_column))
    data = data.drop(['{}_total'.format(d) for d in data_columns], axis=1)
    return data


def rescale_to_parent(data, index_columns, data_columns, cause_column, parent_cause_column, level_column, level):
    """ Rescales child data to be internally consistent with parent data

    This function is called once for every level of the hierarchy.

    It subsets out all data for that level, and merges on the parent cause data.
    Then it overwrites the child adjusted values with the product of the parent and child
    adjusted values so that the data is internally consistent.

    Data MUST BE IN CAUSE FRACTION space in order for this to work.

    Returns: Entire DataFrame with adjusted child data
    """
    parent_keep_columns = list(set(index_columns + [cause_column] + data_columns))
    merge_columns = list(set(list(set(index_columns) - set([cause_column])) + [parent_cause_column]))
    temp_child = data.ix[data[level_column]==level].copy(deep=True)
    temp_parent = data.ix[data[cause_column].isin(temp_child[parent_cause_column].drop_duplicates())].copy(deep=True)
    temp_parent = temp_parent.ix[:, parent_keep_columns]
    parent_rename_columns = {'cause_id': 'parent_id'}
    for data_column in data_columns:
        parent_rename_columns[data_column] = '{}_parent'.format(data_column)
    temp_parent = temp_parent.rename(columns=parent_rename_columns)
    temp_child = pd.merge(temp_child, temp_parent, on=merge_columns)
    for data_column in data_columns:
        temp_child[data_column] = temp_child.eval('{data_column} * {data_column}_parent'.format(data_column=data_column))
        temp_child = temp_child.drop('{}_parent'.format(data_column), axis=1)
    return pd.concat([data.ix[data['level']!=level], temp_child])


def rescale_data(data, index_columns, data_columns, cause_column='cause_id', parent_cause_column='parent_id', level_column='level'):
    """ Rescales data to make it internally consistent within hierarchy

    First, takes DataFrame and rescale to 1 within each level of the index
    columns

    Then runs down cause hierarchy and rescales each level according to the
    parent

    Returns a scaled DataFrame
    """
    # Rescale
    data = rescale_group(data,
                         list(set(index_columns) - set([cause_column])) + [parent_cause_column, level_column],
                         data_columns)
    # Propagate down levels
    for level in xrange(data[level_column].min()+1, data[level_column].max()+1):
        data = rescale_to_parent(data, index_columns, data_columns,
                                 cause_column, parent_cause_column,
                                 level_column, level)
    return data


def convert_to_deaths(data, data_columns, envelope):
    """ Multiplies death draws by envelope """
    logger = logging.getLogger('correct.convert_to_deaths')
    try:
        # Merge on envelope data
        envelope_data = envelope.data
        envelope_data = envelope_data[envelope.index_columns + data_columns]
        rename_columns = {d: '{}_env'.format(d) for d in data_columns}
        envelope_data = envelope_data.rename(columns=rename_columns)
        data = pd.merge(data, envelope_data,
                        on=envelope.index_columns,
                        how='left')
        # Convert to death space
        for data_column in data_columns:
            data.eval('{d} = {d} * {d}_env'.format(d=data_column))
        # Drop old columns
        data = data.drop(['{}_env'.format(d) for d in data_columns], axis=1)

    except Exception as e:
        logger.exception('Failed to convert to death space: {}'.format(e))
        sys.exit()

    return data


def save_unscaled_draws(data, index_columns):
    """ Saves unscaled draws in an h5 file """

    logger = logging.getLogger('correct.save_unscaled_draws')

    # Save unscaled draws
    draw_filepath = parent_dir + r'/unaggregated/unscaled/unscaled_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
    save_hdf(data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)


def save_models(data, index_columns):
    """ Saves model version id for each data point in an h5 file """

    logger = logging.getLogger('correct.save_models')

    # Save model data
    draw_filepath = parent_dir + r'/models/models_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
    save_hdf(data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)


def save_rescaled_draws(data, index_columns):
    """ Saves rescaled draws in an h5 file """
    logger = logging.getLogger('correct.save_rescaled_draws')

    # Save rescaled draws
    draw_filepath = parent_dir + r'/unaggregated/rescaled/rescaled_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
    save_hdf(data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)


if __name__ == '__main__':

    # Get command line arguments
    output_version_id, location_id, sex_name = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'correct', output_version_id, location_id, sex_name)

    # Sex dictionary
    sex_dict = {'male': 1, 'female': 2}
    sex_id = sex_dict[sex_name]

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, best_models, eligible_data, spacetime_restriction_data, envelope_data = read_helper_files(parent_dir, location_id, sex_name)

        # Read in config variables
        eligible_year_ids = config['eligible_year_ids']
        index_columns = config['index_columns']
        data_columns = config['data_columns']
        envelope_index_columns = config['envelope_index_columns']
        envelope_pop_column = config['envelope_pop_column']
        envelope_column = config['envelope_column']
        raw_data_columns = ['model_version_id'] + [envelope_column] + index_columns + data_columns

        # Make eligible data for data
        print "Make eligible data list"
        logging.info("Make eligible data list")
        eligible_data = eligible_data.ix[eligible_data['sex_id']==sex_id]
        eligible_data = expand_id_set(eligible_data, eligible_year_ids,
                                      'year_id')
        eligible_data['location_id'] = int(location_id)

        # Merge on space-time restrictions
        spacetime_restriction_data['spacetime_restriction'] = True
        eligible_data = pd.merge(eligible_data,
                                 spacetime_restriction_data,
                                 on=['location_id', 'year_id', 'cause_id'],
                                 how='left')

        # Apply space-time restrictions
        eligible_data.ix[eligible_data['spacetime_restriction']==True,
                                       'restricted'] = True
        eligible_data = eligible_data.ix[:, ['cause_id', 'age_group_id',
                                             'sex_id', 'restricted', 'level',
                                             'parent_id', 'year_id',
                                             'location_id']]

        # Make envelope object
        print "Make envelope object"
        logging.info("Make envelope object")
        envelope = Envelope(envelope_data, envelope_index_columns,
                            envelope_pop_column, data_columns)

        # Read in draw files
        print "Reading in best model draws"
        logging.info("Reading in best model draws")
        raw_data = read_all_model_draws(best_models, raw_data_columns,
                                        filter_years=eligible_year_ids)

        # Check formatting
        print "Checking best model draws"
        logging.info("Checking in best model draws")
        check_data_format(raw_data, raw_data_columns, fail=True)

        # Format data for rescale
        print "Formatting data for rescale"
        logging.info("Formatting data for rescale")
        formatted_data, model_data = format_for_rescale(raw_data, eligible_data,
                                                        index_columns,
                                                        data_columns,
                                                        envelope_column,
                                                        parent_dir+'/debug',
                                                        '{}_{}_{}'.format(output_version_id,
                                                                          location_id,
                                                                          sex_name))

        # Save model data
        print "Saving model data"
        logging.info("Saving model data")
        save_models(model_data, index_columns)

        # Save input data
        print "Saving input data"
        logging.info("Saving input data")
        formatted_data_deaths = convert_to_deaths(formatted_data, data_columns,
                                                  envelope)
        save_unscaled_draws(formatted_data_deaths, index_columns)

        # Rescale data
        print "Rescaling data"
        logging.info("Rescaling data")
        scaled_data = rescale_data(formatted_data, index_columns, data_columns,
                                   cause_column='cause_id',
                                   parent_cause_column='parent_id',
                                   level_column='level')

        # Saving data
        print "Saving data"
        logging.info("Saving data")
        scaled_data = convert_to_deaths(scaled_data, data_columns, envelope)
        save_rescaled_draws(scaled_data, index_columns)

        print 'All done!'
        logging.info('All done!')
    except:
        logging.exception('uncaught exception in correct.py')
