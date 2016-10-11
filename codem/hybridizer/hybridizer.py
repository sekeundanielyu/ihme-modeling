import sqlalchemy as sql
import pandas as pd
from hybridizer.core import run_query
from hybridizer.database import get_location_hierarchy_version
from hybridizer.save_results import ModelData
import hybridizer.log_utilities as l
import smtplib
import sys
import os


model_version_id = int(sys.argv[1])
global_model = int(sys.argv[2])
developed_model = int(sys.argv[3])


def get_cause_dict():
    """ Return cause information in dictionary form

    Will return information stored in the shared.cause table with a key of cause_id.
    This does not include hierarchy-specific information like age start or age end
    """
    cause_data = run_query('SELECT * FROM shared.cause;', server=server_name).set_index('cause_id')
    output = {}
    for i in cause_data.index:
        output[i] = {}
        for c in cause_data.columns:
            output[i][c] = cause_data.ix[i, c]
    return output


def read_model_draws(draws_filepath, filter_statement=None):
    """ Read in model draws

    Read in CODEm/custom model draws from a given filepath and filter by location_id.
    """
    if filter_statement:
        data = pd.read_hdf(draws_filepath, key="data", where=filter_statement)
    else:
        data = pd.read_hdf(draws_filepath, key="data")
    return data


def get_locations(location_set_version_id):
    """ Get a DataFrame of the specified location hierarchy version """
    return run_query("Call shared.view_location_hierarchy_history({location_set_version_id})".format(location_set_version_id=location_set_version_id), server=server_name)


def get_model_properties(model_version_id):
    model_data = run_query("SELECT * FROM cod.model_version WHERE model_version_id = {};".format(model_version_id), server=server_name)
    output = {}
    for c in model_data.columns:
        output[c] = model_data.ix[0, c]
    return output


def get_excluded_locations(developed_model):
    """ Get a list of the excluded locations from the developed model

    We will use these IDs to figure out which locations to pull from the global
    model and which ones to pull from the developed model.

    Returns a list of location_ids.
    """
    model_data = get_model_properties(developed_model)
    return model_data['locations_exclude'].split(' ')


def tag_location_from_path(path, location_id):
    """ Tag whether or not a location ID is in a path

    Path must be a list.
    """
    if location_id in path:
        return True
    else:
        return False


def get_locations_for_models(developed_model_id, location_set_version_id):
    excluded_locations = get_excluded_locations(developed_model_id)
    location_hierarchy_data = get_locations(location_set_version_id)
    location_hierarchy_data['global_model'] = False
    for location_id in excluded_locations:
        location_hierarchy_data.ix[location_hierarchy_data['global_model']==False, 'global_model'] = location_hierarchy_data['path_to_top_parent'].map(lambda x: tag_location_from_path(x.split(','), location_id))
    location_hierarchy_data = location_hierarchy_data.ix[(location_hierarchy_data['is_estimate']==1)]

    developed_location_list = location_hierarchy_data.ix[location_hierarchy_data['global_model']==False, 'location_id'].tolist()
    global_location_list = location_hierarchy_data.ix[location_hierarchy_data['global_model']==True, 'location_id'].tolist()

    return global_location_list, developed_location_list


def chunks(l, n):
    """Yield successive n-sized chunks from l."""
    for i in xrange(0, len(l), n):
        yield l[i:i+n]


def transfer_draws_to_temp(draws_filepath, location_ids):
    """ Transfer draws from a CoD model to a temporary directory

    Save draws as deaths_{location_id}_{year_id}_{sex_name}

    """
    data_all = []
    temp_all_location_ids = chunks(location_ids, 20)
    for temp_location_ids in temp_all_location_ids:
        data = read_model_draws(draws_filepath, "location_id in ["+','.join([str(x) for x in temp_location_ids])+"]")
        data_all.append(data)
    return pd.concat(data_all).reset_index(drop=True)




# Get cause and model data
cause_data = get_cause_dict()
developed_model_properties = get_model_properties(developed_model)
global_model_properties = get_model_properties(global_model)
hybrid_model_properties = get_model_properties(model_version_id)

log_dir = LOG_DIRECTORY
l.setup_logging(log_dir, 'hybridizer')

try:

    # Get list of locations for global and developing model
    location_set_version_id, location_metadata_version_id = get_location_hierarchy_version(35, 2015)
    global_location_list, developed_location_list = get_locations_for_models(developed_model, location_set_version_id)

    print "Global locations:"
    print sorted(global_location_list)
    print "Developed locations:"
    print sorted(developed_location_list)

    # Loop through developed and developing models
    data_all = []
    global_draws_filepath = get_draws_filepath(global_model_properties, cause_data)
    data_all.append(transfer_draws_to_temp(global_draws_filepath, global_location_list))

    developed_draws_filepath = get_draws_filepath(developed_model_properties, cause_data)
    data_all.append(transfer_draws_to_temp(developed_draws_filepath, developed_location_list))

    data_all = pd.concat(data_all).reset_index(drop=True)

    # Create ModelData instace
    m = ModelData(model_version_id,
                  data_all,
                  ['location_id', 'year_id', 'sex_id', 'age_group_id', 'cause_id'],
                  'envelope',
                  'pop',
                  ['draw_{}'.format(x) for x in xrange(1000)],
                  35)

    # Run prep steps for upload
    print "Aggregating locations"
    logging.info("Aggregating locations")
    m.aggregate_locations()

    print "Save draws"
    logging.info("Save draws")
    m.save_draws()

    print "Generate all ages"
    logging.info("Generate all ages")
    m.generate_all_ages()

    print "Generate ASR"
    logging.info("Generate ASR")
    m.generate_age_standardized()

    print "Generate summaries"
    logging.info("Generate summaries")
    m.generate_summaries()

    print "Save summaries"
    logging.info("Save summaries")
    m.save_summaries()

    print "Upload summaries"
    logging.info("Upload summaries")
    m.upload_summaries()

    print "Update status"
    logging.info("Update status")
    m.update_status()

    print "DONE!!!!"


    # Send email when completed
    logging.info("Sending email")
    user = get_model_properties(model_version_id)['inserted_by']
    print user
    message_for_body = '''
    <p>Hello {user},</p>
    <p>The hybrid of {global_model} and {developed_model} for {acause} has completed and saved as model {model_version_id}.</p>
    <p>Please check your model and then, if everything looks good, mark it as best.</p>
    <p></p>
    <p>Regards,</p>
    <p>Your Friendly Neighborhood Hybridizer</p>
    '''.format(user=user, global_model=global_model, developed_model=developed_model, acause=cause_data[hybrid_model_properties['cause_id']]['acause'], model_version_id=model_version_id)
    send_email(['{user}@uw.edu'.format(user=user)],
               "Hybrid of {global_model} and {developed_model} ({acause}) has completed".format(global_model=global_model,
                                                                                    developed_model=developed_model,
                                                                                    acause=cause_data[hybrid_model_properties['cause_id']]['acause']),
               message_for_body)

    logging.info("Done!")

except Exception as e:

    logger.exception('Failed to hybridize results: {}'.format(e))

    # Send email when completed
    user = get_model_properties(model_version_id)['inserted_by']
    print user
    message_for_body = '''
    <p>Hello {user},</p>
    <p>The hybrid of {global_model} and {developed_model} for {acause} has failed.</p>
    <p>Please check the following log file:</p>
    <p>{log_filepath}</p>
    <p></p>
    <p>Regards,</p>
    <p>Your Friendly Neighborhood Hybridizer</p>
    '''.format(user=user, log_filepath=log_dir+'/hybridizer.txt', global_model=global_model, developed_model=developed_model, acause=cause_data[hybrid_model_properties['cause_id']]['acause'], model_version_id=model_version_id)
    send_email(['{user}@uw.edu'.format(user=user)],
               "Hybrid of {global_model} and {developed_model} ({acause}) failed".format(global_model=global_model,
                                                                                    developed_model=developed_model,
                                                                                    acause=cause_data[hybrid_model_properties['cause_id']]['acause']),
               message_for_body)
