import pandas as pd
import logging
from codcorrect.core import read_json
from codcorrect.io import read_hdf_draws, save_hdf
from codcorrect.error_check import save_diagnostics
import codcorrect.log_utilities as l
import argparse
import sys

"""
    This script aggregates up the cause hierarchy
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

    args = parser.parse_args()
    output_version_id = args.output_version_id
    location_id = args.location_id

    return output_version_id, location_id


def read_helper_files(parent_dir, location_id):
    """ Read in and return helper DataFrames.

        Returns:
        DataFrame containing cause hierarchy used for aggregation
    """

    # Config file
    config = read_json(parent_dir + r'/_temp/config.json')

    # Location hierarchy
    location_hierarchy = pd.read_csv(parent_dir + r'/_temp/location_hierarchy.csv')
    child_locations = location_hierarchy.ix[((location_hierarchy['parent_id']==int(location_id))&
                                            (location_hierarchy['location_id']!=int(location_id))),
                                            'location_id'].drop_duplicates().tolist()

    return config, child_locations


def aggregate_location(data, location_id, index_columns):
    """ Aggregate causes up the cause hierarchy """
    logger = logging.getLogger('aggregate_locations.aggregate_locations')
    try:
       # Set location_id column to parent location_id
       data['location_id'] = location_id

       # Collapse down
       data = data.groupby(index_columns).sum().reset_index()
    except Exception as e:
        logger.exception('Failed to aggregate location: {}'.format(e))
        sys.exit()

    return data


def read_child_location_draw_files(parent_dir, location_id, child_locations, index_columns):
    """ Chunks up reading in the child locations, collapsing after each 10th location"""
    logger = logging.getLogger('aggregate_locations.read_child_location_draw_files')
    try:
        c = 0
        rescaled_data = []
        unscaled_data = []
        shocks_data = []
        for child_id in child_locations:
            rescaled_filepath = parent_dir + r'/aggregated/rescaled/rescaled_{location_id}.h5'.format(location_id=str(child_id))
            unscaled_filepath = parent_dir + r'/aggregated/unscaled/unscaled_{location_id}.h5'.format(location_id=str(child_id))
            shocks_filepath = parent_dir + r'/aggregated/shocks/shocks_{location_id}.h5'.format(location_id=str(child_id))

            logger.info('Appending in {}'.format(rescaled_filepath))
            print 'Appending in {}'.format(rescaled_filepath)
            rescaled_data.append(read_hdf_draws(rescaled_filepath, child_id).reset_index(drop=True))

            logger.info('Appending in {}'.format(unscaled_filepath))
            print 'Appending in {}'.format(unscaled_filepath)
            unscaled_data.append(read_hdf_draws(unscaled_filepath, child_id).reset_index(drop=True))

            logger.info('Appending in {}'.format(shocks_filepath))
            print 'Appending in {}'.format(shocks_filepath)
            shocks_data.append(read_hdf_draws(shocks_filepath, child_id).reset_index(drop=True))

            c += 1
            if c % 5 == 0:
                logger.info('Intermediate collapsing location')
                rescaled_data = [aggregate_location(pd.concat(rescaled_data), location_id, index_columns)]
                unscaled_data = [aggregate_location(pd.concat(unscaled_data), location_id, index_columns)]
                shocks_data = [aggregate_location(pd.concat(shocks_data), location_id, index_columns)]
        logger.info('Intermediate collapsing location')
        rescaled_data = aggregate_location(pd.concat(rescaled_data), location_id, index_columns)
        unscaled_data = aggregate_location(pd.concat(unscaled_data), location_id, index_columns)
        shocks_data = aggregate_location(pd.concat(shocks_data), location_id, index_columns)

    except Exception as e:
        logger.exception('Failed to aggregate location: {}'.format(e))
    return rescaled_data, unscaled_data, shocks_data


def save_all_draws(parent_dir, index_columns, rescaled_data, shock_data, unscaled_data, dalynator_data, dalynator_export_years_ids=None):
    # Save rescaled data
    draw_filepath = parent_dir + r'/aggregated/rescaled/rescaled_{location_id}.h5'.format(location_id=location_id)
    save_hdf(rescaled_data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)

    # Save unscaled data
    draw_filepath = parent_dir + r'/aggregated/unscaled/unscaled_{location_id}.h5'.format(location_id=location_id)
    save_hdf(unscaled_data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)

    # Save shocks
    draw_filepath = parent_dir + r'/aggregated/shocks/shocks_{location_id}.h5'.format(location_id=location_id)
    save_hdf(shock_data, draw_filepath, key='draws', mode='w', format='table',
             data_columns=index_columns)

    # Save DALYNator draws
    draw_filepath = parent_dir + r'/draws/death_{location_id}.h5'.format(location_id=location_id)
    save_hdf(dalynator_data, draw_filepath, key='draws', mode='w',
             format='table', data_columns=index_columns)


if __name__ == '__main__':

    # Get command line arguments
    output_version_id, location_id = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'agg_location', output_version_id, location_id, 'both')

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, child_locations = read_helper_files(parent_dir, location_id)

        # Read in config variables
        index_columns = config['index_columns']
        data_columns = config['data_columns']

        # Read in rescaled draw files
        print "Reading in child location draw files"
        logging.info("Reading in child location draw files")
        logging.info("{}".format(', '.join([str(x) for x in child_locations])))
        rescaled_data, unscaled_data, shocks_data = read_child_location_draw_files(parent_dir, location_id, child_locations, index_columns)

        # Combine shocks and rescaled data
        print "Merging shocks and rescaled data"
        logging.info("Merging shocks and rescaled data")
        pop_data = rescaled_data.copy(deep=True)
        pop_data = pop_data.ix[pop_data['cause_id']==294]
        pop_data = pop_data[['location_id', 'year_id',
                             'sex_id', 'age_group_id'] + ['pop']]
        rescaled_data = pd.merge(rescaled_data.drop('pop', axis=1),
                                  pop_data,
                                  on=['location_id', 'year_id', 'sex_id',
                                      'age_group_id'],
                                  how='left')
        dalynator_data = pd.concat([rescaled_data, shocks_data]).reset_index(drop=True)
        dalynator_data = dalynator_data[index_columns + data_columns].groupby(index_columns).sum().reset_index()
        dalynator_data = pd.merge(dalynator_data,
                                  pop_data,
                                  on=['location_id', 'year_id', 'sex_id',
                                      'age_group_id'],
                                  how='left')

        # Save
        logging.info("Save draws")
        save_all_draws(parent_dir, index_columns, rescaled_data, shocks_data, unscaled_data, dalynator_data)

        # Saving diagnostics
        print "Saving diagnostics"
        logging.info("Saving diagnostics")
        save_diagnostics(unscaled_data, dalynator_data, index_columns,
                         data_columns, location_id, parent_dir)

        logging.info('All done!')
    except:
        logging.exception('uncaught exception in aggregate_locations.py')
