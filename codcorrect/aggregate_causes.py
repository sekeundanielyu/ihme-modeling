import pandas as pd
import logging
from codcorrect.core import read_json
from codcorrect.io import read_hdf_draws, import_cod_model_draws
from codcorrect.io import read_envelope_draws, save_hdf
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


def read_helper_files(parent_dir):
    """ Read in and return helper DataFrames.

        Returns:
        DataFrame containing cause hierarchy used for aggregation
    """

    # Config file
    config = read_json(parent_dir + r'/_temp/config.json')

    # Cause hierarchy
    cause_hierarchy = pd.read_csv(parent_dir + r'/_temp/cause_aggregation_hierarchy.csv')

    # Population
    population_data = read_envelope_draws(parent_dir + r'/_temp/envelope.h5', location_id)
    population_data = population_data[['location_id', 'year_id', 'sex_id',
                                       'age_group_id', 'pop']]

    return config, cause_hierarchy, population_data


def read_rescaled_draw_files(parent_dir, location_id):
    """ Reads in rescaled draw files """
    data = []
    for sex_name in ['male', 'female']:
        draw_filepath = (parent_dir +
                         r'/unaggregated/rescaled/rescaled_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
                        )
        data.append(read_hdf_draws(draw_filepath, location_id))
    data = pd.concat(data).reset_index(drop=True)
    return data

def read_unscaled_draw_files(parent_dir, location_id, index_columns, draw_columns):
    """ Reads in unscaled draw files """
    data = []
    for sex_name in ['male', 'female']:
        draw_filepath = (parent_dir +
                         r'/unaggregated/unscaled/unscaled_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
                        )
        data.append(read_hdf_draws(draw_filepath, location_id))
    data = pd.concat(data).reset_index(drop=True)
    data = data[index_columns + data_columns]
    data = data.sort(index_columns).reset_index(drop=True)
    return data

def read_shock_draw_files(parent_dir, location_id):
    """ Reads in shock draw files """
    data = []
    for sex_name in ['male', 'female']:
        draw_filepath = (parent_dir +
                         r'/unaggregated/shocks/shocks_{location_id}_{sex_name}.h5'.format(location_id=location_id, sex_name=sex_name)
                        )
        data.append(read_hdf_draws(draw_filepath, location_id))
    data = pd.concat(data).reset_index(drop=True)
    return data


def aggregate_causes(data, index_columns, data_columns, cause_hierarchy):
    """ Aggregate causes up the cause hierarchy """
    logger = logging.getLogger('aggregate_causes.aggregate_causes')
    try:

        # Merge on cause hierarchy
        cause_hierarchy['level'] = cause_hierarchy['level'].astype('int64')
        min_level = cause_hierarchy['level'].min()
        data = data[index_columns + data_columns]
        data = pd.merge(data,
                        cause_hierarchy[['cause_id',
                                         'level',
                                         'parent_id',
                                         'most_detailed']
                                       ],
                        on='cause_id',
                        how='left')
        # Filter down to the most detailed causes
        data = data.ix[data['most_detailed']==1]
        max_level = data['level'].max()
        # Loop through and aggregate
        data = data[index_columns + data_columns]
        for level in xrange(max_level, min_level, -1):
            print "Level:", level
            data = pd.merge(data,
                            cause_hierarchy[['cause_id',
                                             'level',
                                             'parent_id']
                                           ],
                            on='cause_id',
                            how='left')
            temp = data.ix[data['level']==level].copy(deep=True)
            temp['cause_id'] = temp['parent_id']
            temp = temp[index_columns + data_columns]
            temp = temp.groupby(index_columns).sum().reset_index()
            data = pd.concat([data[index_columns + data_columns], temp]).reset_index(drop=True)

    except Exception as e:
        logger.exception('Failed to aggregate causes: {}'.format(e))
        sys.exit()

    return data

def aggregate_blanks(data, index_columns, data_columns, cause_hierarchy, full_index_set):
    """ This function is to fill in gaps and to preserve existing data """
    logger = logging.getLogger('aggregate_causes.aggregate_blanks')
    # Merge on cause hierarchy
    data = pd.merge(data,
                    full_index_set,
                    on=index_columns,
                    how='outer')
    data = pd.merge(data,
                    cause_hierarchy[['cause_id',
                                     'level',
                                     'parent_id']],
                    on='cause_id',
                    how='left')

    # Get min and max level where we need to aggregate
    min_level = data.ix[data[data_columns[0]].isnull(), 'level'].min() - 1
    max_level = data.ix[data[data_columns[0]].isnull(), 'level'].max()

    # Loop through and aggregate things that are missing
    for level in xrange(max_level, min_level, -1):
        print level
        # Wipe then merge cause hierarchy onto data
        data = data[index_columns + data_columns]
        data = pd.merge(data,
                    cause_hierarchy[['cause_id', 'level', 'parent_id']],
                    on='cause_id')
        # Get data that needs to get aggregated
        temp = data.ix[(data[data_columns[0]].isnull())&
                       (data['level']==level),
                       index_columns].copy(deep=True)
        temp = temp.rename(columns={'cause_id': 'parent_id'})
        temp = pd.merge(temp,
                        data,
                        on=list(set(index_columns) - set(['cause_id'])) + ['parent_id'])
        # Collapse to parent
        temp['cause_id'] = temp['parent_id']
        temp = temp.groupby(index_columns)[data_columns].sum().reset_index()
        # Merge back onto original data
        data = pd.concat([data.ix[((data[data_columns[0]].notnull())&
                                   (data['level']==level))|
                                  (data['level']!=level)],
                          temp])

    data = data[index_columns + data_columns]
    return data


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

    # Save DALYNator draws
    """ For this, we just want CoDCorrect-ed & HIV data """
    if dalynator_export_years_ids:
        for year_id in dalynator_export_years_ids:
            draw_filepath = parent_dir + r'/draws/death_{location_id}_{year_id}.dta'.format(location_id=location_id,
                                                                                            year_id=year_id)
            rescaled_data.ix[rescaled_data['year_id']==year_id].drop('pop', axis=1).to_stata(draw_filepath, write_index=False)



if __name__ == '__main__':

    # Get command line arguments
    output_version_id, location_id = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'agg_cause', output_version_id, location_id, 'both')

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, cause_hierarchy, population_data = read_helper_files(parent_dir)

        # Read in config variables
        index_columns = config['index_columns']
        data_columns = config['data_columns']
        dalynator_export_years_ids = config['dalynator_export_years_ids']

        # Read in rescaled draw files
        print "Reading in rescaled draw files"
        logging.info("Reading in rescaled draw files")
        rescaled_data = read_rescaled_draw_files(parent_dir, location_id)

        # Read in unscaled draw files
        print "Reading in unscaled draw files"
        logging.info("Reading in unscaled draw files")
        unscaled_data = read_unscaled_draw_files(parent_dir, location_id,
                                                 index_columns, data_columns)

        # Read in shock draw files
        print "Reading in shock draw files"
        logging.info("Reading in shock draw files")
        shocks_data = read_shock_draw_files(parent_dir, location_id)
        hiv_data = shocks_data.ix[shocks_data['cause_id'].isin([299, 300])].copy(deep=True)
        shocks_data = shocks_data.ix[~shocks_data['cause_id'].isin([299, 300])]

        # Aggregate causes
        print "Aggregating causes - rescaled"
        logging.info("Aggregating causes - rescaled")
        rescaled_data = pd.concat([rescaled_data, hiv_data]).reset_index(drop=True)
        rescaled_data = rescaled_data[index_columns + data_columns].groupby(index_columns).sum().reset_index()
        aggregated_rescaled_data = aggregate_causes(rescaled_data,
                                                    index_columns, data_columns,
                                                    cause_hierarchy)
        print "Aggregating causes - unscaled"
        logging.info("Aggregating causes - unscaled")
        full_index_set = aggregated_rescaled_data.ix[:, index_columns].copy(deep=True)
        full_index_set = full_index_set.drop_duplicates()
        aggregated_unscaled_data = aggregate_blanks(unscaled_data,
                                                    index_columns, data_columns,
                                                    cause_hierarchy,
                                                    full_index_set)
        print "Aggregating causes - shocks"
        logging.info("Aggregating causes - shocks")
        aggregated_shocks = aggregate_causes(shocks_data, index_columns,
                                             data_columns, cause_hierarchy)


        # Combine shocks and rescaled data
        print "Merging shocks and rescaled data"
        logging.info("Merging shocks and rescaled data")
        dalynator_data = pd.concat([aggregated_rescaled_data, aggregated_shocks]).reset_index(drop=True)
        dalynator_data = dalynator_data[index_columns + data_columns].groupby(index_columns).sum().reset_index()

        # Merge on population
        print "Merging population"
        logging.info("Merging population")
        dalynator_data = pd.merge(dalynator_data, population_data,
                                   on=['location_id', 'year_id', 'sex_id',
                                       'age_group_id'],
                                   how='left').fillna(0)
        aggregated_rescaled_data = pd.merge(aggregated_rescaled_data,
                                            population_data,
                                            on=['location_id', 'year_id',
                                                'sex_id', 'age_group_id'],
                                            how='left').fillna(0)

        # Save
        logging.info("Save draws")
        save_all_draws(parent_dir, index_columns, aggregated_rescaled_data,
                       aggregated_shocks, aggregated_unscaled_data,
                       dalynator_data,
                       dalynator_export_years_ids=dalynator_export_years_ids)

        # Saving diagnostics
        print "Saving diagnostics"
        logging.info("Saving diagnostics")
        save_diagnostics(aggregated_unscaled_data, dalynator_data,
                         index_columns, data_columns, location_id, parent_dir)

        logging.info('All done!')
    except:
        logging.exception('uncaught exception in aggregate_causes.py')
