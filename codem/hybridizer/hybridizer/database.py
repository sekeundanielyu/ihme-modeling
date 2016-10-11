import sqlalchemy as sql
import pandas as pd
from hybridizer.core import run_query
import logging

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
