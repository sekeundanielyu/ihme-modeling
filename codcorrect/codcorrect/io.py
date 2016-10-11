import sqlalchemy as sql
import pandas as pd
from codcorrect.error_check import check_data_format
import logging
import os
import subprocess

def read_hdf_draws(draws_filepath, location_id, key="draws", filter_sexes=None, filter_ages=None, filter_years=None):
    """ Read in model draws

    Read in CODEm/custom model draws from a given filepath and filter by location_id.
    """
    # Get data
    where_clause = ["location_id=={location_id}".format(location_id=location_id)]
    data = pd.read_hdf(draws_filepath, key=key, where=where_clause)
    # Filter if necessary
    if filter_sexes and 'sex_id' in data.columns:
        data = data.ix[data['sex_id'].isin(filter_sexes)]
    if filter_ages and 'age_group_id' in data.columns:
        data = data.ix[data['age_group_id'].isin(filter_ages)]
    if filter_years and 'year_id' in data.columns:
        data = data.ix[data['year_id'].isin(filter_years)]
    # Return data
    return data


def import_cod_model_draws(model_version_id, location_id, acause, sex_name, required_columns, filter_years=None):
    """ Import model draws from CODEm/custom models

    Read in CODEm/custom model draws from a given filepath (filtered by a specific
    location_id) and then check to make sure that the imported draws are not missing any
    columns and do not have null values.

    """
    sex_dict = {'male': 1, 'female': 2}
    logger = logging.getLogger('io.import_cod_model_draws')
    try:
        # Get file path for CoD model
        draws_filepath = DRAWS_PATH
        # Read in file
        data = read_hdf_draws(draws_filepath, location_id, key="data", filter_sexes=[sex_dict[sex_name]], filter_ages=range(2, 22), filter_years=filter_years)
        data['model_version_id'] = model_version_id
    except IOError:
        logger.warn('Failed to read {}'.format(draws_filepath))
        print model_version_id
        return None
    logger.info('Reading {}'.format(draws_filepath))
    r = check_data_format(data, required_columns)
    if not r:
        print model_version_id, r
        return None
    data = data.ix[:, required_columns]
    return data

def read_envelope_draws(draws_filepath, location_id, filter_sexes=None, filter_ages=None, filter_years=None):
    """ Read in envelope file draws

    Read in envelope draws from a given filepath and filter by location_id.
    """
    data = read_hdf_draws(draws_filepath, location_id, key="draws", filter_sexes=filter_sexes, filter_ages=filter_ages, filter_years=filter_years)
    return data

def save_hdf(data, filepath, key='draws', mode='w', format='table', data_columns=None):
    if data_columns:
        data = data.sort(data_columns).reset_index(drop=True)
    data.to_hdf(filepath, key, mode=mode, format=format,
                data_columns=data_columns)


def change_permission(folder_path, recursively=False):
    if recursively:
        change_permission_cmd = ['chmod',
                                 '-R', '775',
                                 folder_path]
    else:
        change_permission_cmd = ['chmod',
                                 '775',
                                 folder_path]
    print ' '.join(change_permission_cmd)
    subprocess.check_output(change_permission_cmd)
