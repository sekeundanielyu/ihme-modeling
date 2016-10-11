import sqlalchemy as sql
import pandas as pd
from codcorrect.core import run_query, get_credentials
import logging
import datetime

def get_best_model_version(gbd_round):
    """ Get the list of best models for a given GBD round except for shock
        aggregator models
    """
    sql_statement = """SELECT
                        gbd_round,
                        model_version_id,
                        cause_id,
                        sex_id,
                        model_version_type_id,
                        is_best
                       FROM
                        cod.model_version
                       JOIN shared.cause_set_version USING (cause_set_version_id)
                       WHERE
                        is_best = 1 AND
                        gbd_round = {gbd_round} AND
                        model_version_type_id IN (0, 1, 2, 3, 4, 6);
                    """.format(gbd_round=gbd_round)
    result_df = run_query(sql_statement)
    return result_df

def get_best_shock_models(gbd_round):
    """ Get list of models for a given GBD round used in the shock aggregator """
    sql_statement = """ SELECT
                            gr.gbd_round,
                            mv.model_version_id,
                            mv.cause_id,
                            mv.sex_id,
                            mv.model_version_type_id,
                            mv.is_best
                        FROM
                            cod.shock_version sv
                        JOIN
                            cod.shock_version_model_version svmv USING (shock_version_id)
                        JOIN
                            cod.model_version mv USING (model_version_id)
                        JOIN
                        	shared.gbd_round gr USING (gbd_round_id)
                        WHERE
                            shock_version_status_id = 1 AND
                            gbd_round = {gbd_round};
                    """.format(gbd_round=gbd_round)
    result_df = run_query(sql_statement)
    return result_df


def get_best_envelope_version():
    """ Get best envelope version """
    sql_statement = "SELECT * FROM mortality.output_version WHERE is_best = 1;"
    result_df = run_query(sql_statement)
    if len(result_df) > 1:
        exception_text = "This returned more than 1 envelope version: ({returned_ids})".format(returened_ids=", ".join(result_df['output_version_id'].drop_duplicates().to_list()))
        raise LookupError(exception_text)
    elif len(result_df) < 1:
        raise LookupError("No envelope versions returned")
    return result_df.ix[0, 'output_version_id']


def get_cause_hierarchy_version(cause_set_id, gbd_round):
    """ Get the IDs associated with best version of a cause set

    This function will return the following integers:
        cause_set_version_id
        cause_metadata_version_id
    """
    sql_statement = "SELECT cause_set_version_id, cause_metadata_version_id FROM shared.cause_set_version WHERE cause_set_id = {cause_set_id} AND gbd_round = {gbd_round} AND end_date IS NULL;".format(cause_set_id=cause_set_id, gbd_round=gbd_round)
    result_df = run_query(sql_statement)

    if len(result_df) > 1:
        exception_text = "This returned more than 1 cause_set_version_id ({returned_ids})".format(returened_ids=", ".join(result_df['cause_set_version_id'].drop_duplicates().to_list()))
        raise LookupError(exception_text)
    elif len(result_df) < 1:
        raise LookupError("No cause set versions returned")
    return result_df.ix[0, 'cause_set_version_id'], result_df.ix[0, 'cause_metadata_version_id']


def get_cause_hierarchy(cause_set_version_id):
    ''' Return a DataFrame containing cause hierarchy table

        Arguments: cause set version id
        Returns: DataFrame
    '''

    sql_statement = "SELECT cause_id, acause, level, parent_id, sort_order, most_detailed FROM shared.cause_hierarchy_history WHERE cause_set_version_id = {cause_set_version_id};".format(cause_set_version_id=cause_set_version_id)
    result_df = run_query(sql_statement)
    return result_df

def get_cause_metadata(cause_metadata_version_id):
    ''' Returns a dict containing cause ids as keys and cause metadata as as a nested dict

        Arguments: cause metadata version id
        Returns: nested dict
    '''
    sql_statement = "SELECT cause_id, cause_metadata_type, cause_metadata_value FROM shared.cause_metadata_history JOIN shared.cause_metadata_type USING (cause_metadata_type_id) WHERE cause_metadata_version_id = {cause_metadata_version_id};".format(cause_metadata_version_id=cause_metadata_version_id)
    result_df = run_query(sql_statement)
    result_dict = {}
    for i in result_df.index:
        id = result_df.ix[i, 'cause_id']
        metadata_type = result_df.ix[i, 'cause_metadata_type']
        metadata_value = result_df.ix[i, 'cause_metadata_value']
        if id not in result_dict:
            result_dict[id] = {}
        result_dict[id][metadata_type] = metadata_value
    return result_dict


def get_location_hierarchy_version(location_set_id, gbd_round):
    """ Get the IDs associated with best version of a location set

    This function will return the following variables:
        location_set_version_id
        location_metadata_version_id
    """
    sql_statement = "SELECT location_set_version_id, location_metadata_version_id FROM shared.location_set_version WHERE location_set_id = {location_set_id} AND gbd_round = {gbd_round} AND end_date IS NULL;".format(location_set_id=location_set_id, gbd_round=gbd_round)
    result_df = run_query(sql_statement)

    if len(result_df) > 1:
        exception_text = "This returned more than 1 location_set_version_id ({returned_ids})".format(returened_ids=", ".join(result_df['location_set_version_id'].drop_duplicates().to_list()))
        raise LookupError(exception_text)
    elif len(result_df) < 1:
        raise LookupError("No location set versions returned")
    return result_df.ix[0, 'location_set_version_id'], result_df.ix[0, 'location_metadata_version_id']


def get_location_hierarchy(location_set_version_id):
    sql_statement = "SELECT location_id, parent_id, level, is_estimate, most_detailed, sort_order FROM shared.location_hierarchy_history WHERE location_set_version_id = {location_set_version_id};".format(location_set_version_id=location_set_version_id)
    result_df = run_query(sql_statement)
    return result_df


def get_location_metadata(location_metadata_version_id):
    sql_statement = "SELECT location_id, location_metadata_type, location_metadata_value FROM shared.location_metadata_history JOIN shared.location_metadata_type USING (location_metadata_type_id) WHERE location_metadata_version_id = {location_metadata_version_id};".format(location_metadata_version_id=location_metadata_version_id)
    result_df = run_query(sql_statement)
    result_dict = {}
    for i in result_df.index:
        id = result_df.ix[i, 'location_id']
        metadata_type = result_df.ix[i, 'location_metadata_type']
        metadata_value = result_df.ix[i, 'location_metadata_value']
        if id not in result_dict:
            result_dict[id] = {}
        result_dict[id][metadata_type] = metadata_value
    return result_dict


def get_age_weights():
    sql_query = """
        SELECT
            age_group_id,
            age_group_weight_value
        FROM
            shared.age_group_weight agw
        JOIN
            shared.gbd_round USING (gbd_round_id)
        WHERE
            gbd_round = 2015;"""
    age_standard_data = run_query(sql_query)
    return age_standard_data


def get_spacetime_restrictions():
    sql_query = """
        SELECT
            rv.cause_id,
            r.location_id,
            r.year_id
        FROM
            codcorrect.spacetime_restriction r
        JOIN
            codcorrect.spacetime_restriction_version rv
                USING (restriction_version_id)
        WHERE
            rv.is_best = 1 AND
            rv.gbd_round = 2015;"""
    spacetime_restriction_data = run_query(sql_query,
                                           server=DATABASE_HOST_NAME,
                                           database=DATABASE_NAME)
    return spacetime_restriction_data
