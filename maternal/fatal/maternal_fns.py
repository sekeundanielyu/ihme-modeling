
import pandas as pd
import re
from datetime import datetime, date
import os
from db_tools import dbapis, query_tools
from cluster_utils import submitter
import time


def wait(pattern, seconds):
    '''
    Description: Pause the master script until certain sub-jobs are finished.

    Args:
        1. pattern: the pattern of the jobname that you want to wait for
        2. seconds: number of seconds you want to wait

    Output:
        None, just pauses the script
    '''
    seconds = int(seconds)
    while True:
        qstat = submitter.qstat()
        if qstat['name'].str.contains(pattern).any():
            print time.localtime()
            time.sleep(seconds)
            print time.localtime()
        else:
            break


def filter_cols():
    '''
    Description: Returns a list of the only columns needed for doing math
    on data frames within the maternal custom code. This is used to subset
    dataframes to only keep those columns.

    Args: None

    Output: (list) columns names: age_group_id and draws_0 - draw_999
    '''
    usecols = ['age_group_id']
    for i in range(0, 1000, 1):
        usecols.append("draw_%d" % i)
    return usecols


# get date and time info
def get_time():
    '''
    Description: get timestamp in a format you can put in filepaths

    Args: None

    Output: (string) date_str: string of format '{year}_{month}_{day}_{hour}'
    '''
    date_regex = re.compile('\W')
    date_unformatted = str(datetime.now())[0:13]
    date_str = date_regex.sub('_', date_unformatted)
    return date_str


def get_locations():
    '''
    Description: get list of locations to iterate through for every part of the
    maternal custom process, down to one level of subnationals

    Args: None

    Output: (list) location_ids
    '''
    enginer = dbapis.engine_factory()
    loc_set_version_query = '''
    SELECT location_set_version_id FROM shared.location_set_version
    WHERE location_set_id = 35 AND end_date IS NULL'''
    location_set_version = query_tools.query_2_df(
        loc_set_version_query,
        engine=enginer.engines["cod_prod"]).ix[
        0, 'location_set_version_id']

    query = ('call shared.view_location_hierarchy_history(%s)'
             % location_set_version)
    locations_df = query_tools.query_2_df(query,
                                          engine=enginer.engines["cod_prod"])
    locations = (locations_df[locations_df['most_detailed'] == 1][
                 'location_id'].tolist())

    return locations


def check_dir(filepath):
    '''
    Description: Checks if a file path exists. If not, creates the file path.

    Args: (str) a file path

    Output: (str) the file path that already existed or was created if it
    didn't already exist
    '''

    if not os.path.exists(filepath):
        os.makedirs(filepath)
    else:
        pass
    return filepath

# DEPRECATED
# def get_last_step(inner_folder_id):
#    '''
#    Description: Because of the many steps and their dependencies, an input for
#    one step might not exist in the timestamped folder in cluster_dir that we
#    are currently working in. This function organizes the timestamped folders
#    from most-recent to oldest, and looks through each for the folder of the
#    specific output that we need (specified by a me_id or cause_id, called
#    inner_folder_id)
#
#    Args: me_id or cause_id of the output we are looking for
#
#    Output: (str) the cluster_dir filepath of the most recent output for the
#    given id
#    '''
#    root_dir = '/clustertmp/maternal_mortality'
#
#    file_num = len(os.listdir('%s' %root_dir))
#    index = np.arange(0, file_num+1, 1)
#    columns = ['folder', 'date', 'hour']
#    df = pd.DataFrame(index=index, columns=columns)
#
#    count = 0
#    for folder in os.listdir('%s' %root_dir):
#        d = folder.split('_')[0:3]
#        ord_date = date(year=int(d[0]), month=int(d[1]), day=int(d[2]))
#        hour = folder.split('_')[3]
#        row = [folder, ord_date, hour]
#        df.loc[count]=row
#        count+=1
#
#    df = df.dropna(axis='rows', how='all').sort(['date', 'hour'],
#                   ascending=[0,0])
#
#    for folder in df.folder:
#        if os.path.exists('%s/%s/%s' %(root_dir, folder, inner_folder_id)):
#            if len(os.listdir('%s/%s/%s' %(root_dir, folder, inner_folder_id))) > 0:
#                return '%s/%s/%s' %(root_dir, folder, inner_folder_id)
#            else:
#                continue
#        else:
#            continue


def get_model_vers(process, model_id=None, step=None):
    '''
    Description: Queries the database for the best model_version for the given
    model_id. Can do this for Dismod, Codem, or Codcorrect outputs.

    Args:
        1. (str) process ('dismod', 'codem', or 'codcorrect')
        2. id (model_id for dismod, cause_id for codem, or none for codcorrect)

    Output: (int) best model_version
    '''
    enginer = dbapis.engine_factory()
    enginer.servers["gbd"] = {"prod": "modeling-gbd-db.ihme.washington.edu"}
    enginer.define_engine(strConnection)
    if model_id is not None:
        model_id = int(model_id)

    if process == 'dismod':
        if model_id is None:
            raise ValueError('Must specify a me_id')
        else:
            query = '''SELECT model_version_id from epi.model_version WHERE
            is_best = 1 AND best_end IS NULL AND modelable_entity_id =
            %d''' % model_id
            model_vers_df = query_tools.query_2_df(
                query, engine=enginer.engines['epi_prod'])
            if len(model_vers_df) > 0:
                model_vers = model_vers_df.ix[0, 'model_version_id']
            else:
                model_vers = None
    elif process == 'codem':
        if model_id is None:
            raise ValueError('Must specify a cause_id')
        if step == 2:
            query = '''SELECT MAX(model_version_id) as model_version_id from
              cod.model_version where best_start IS NOT NULL AND
              best_start > '2015-01-01 00:00:01'
              AND cause_id = %d and model_version_type_id = 3''' % model_id
        else:
            query = '''SELECT model_version_id from cod.model_version where
              best_end IS NULL AND best_start IS NOT NULL AND
              best_start > '2015-01-01 00:00:01'
              AND cause_id = %d''' % model_id
        model_vers = query_tools.query_2_df(query, engine=enginer.engines[
            "cod_prod"]).ix[0, 'model_version_id']
    else:
        query = ('SELECT  '
                 'distinct(val) AS daly_id '
                 'FROM '
                 'gbd.gbd_process_version_metadata gpvm '
                 'JOIN '
                 'gbd.gbd_process_version USING (gbd_process_version_id) '
                 'JOIN '
                 'gbd.compare_version_output USING (compare_version_id) '
                 'WHERE '
                 'compare_version_id = (SELECT '
                 'compare_version_id '
                 'FROM '
                 'gbd.compare_version '
                 'WHERE '
                 'compare_version_status_id = 1 '
                 'AND gbd_round_id = 3) '
                 'AND gpvm.metadata_type_id = 5')
        model_vers = query_tools.query_2_df(
            query, engine=enginer.engines["gbd_prod"]).loc[0, 'daly_id']
    return model_vers


def get_best_date(enginer, step, dep_type, dep_id=""):
    '''
    Description: Queries the database for the best_start date of the most
    recent model version for the given cause_id/modelable_entity_id/process.
    Also pulls the most recent date of timestamped files.
    See dependency_map.csv for context.

    Args:
        enginer: connection to the db
        step: step of the process we're on
        dep_type: "cause_id" or "modelable_entity_id"
        dep_id: the modelable_entity_id, cod_correct id, or codem_id for
        which you want to get the best_start date.
        NOTE: dep_id REQUIRED for dismod process

    Output: (datetime) best start date
    '''

    if dep_type == 'cause_id':
        query = '''
            SELECT best_start from cod.model_version where
            best_end IS NULL AND best_start IS NOT NULL AND
            best_start > "2015-01-01 00:00:01" AND cause_id = %s''' % dep_id
        most_recent_best_df = query_tools.query_2_df(
            query, engine=enginer.engines["cod_prod"])
        if len(most_recent_best_df) == 0:
            most_recent_best = datetime(1800, 01, 01, 00, 00, 00)
        else:
            most_recent_best = (most_recent_best_df.ix[0, 'best_start'].
                                to_datetime())

    elif dep_type == 'filename':
        fdict = {}
        for filename in os.listdir(dep_id):
            if 'pafs_draws' in filename:
                if 'hdf' not in filename and not filename.startswith('.'):
                    d = filename.split('_')[2:5]
                    time = ' 00:00:00'
                    d[2] = d[2].rstrip(".csv")
                    ord_date = date(year=int(d[0]), month=int(d[1]),
                                    day=int(d[2])).toordinal()
                    fdict[ord_date] = d
        ord_dates = fdict.keys()
        ord_dates.sort()
        most_recent_str = str(
            fdict[ord_dates[-1]]
        ).replace("['", "").replace("']", "").replace("', '", "-") + time
        most_recent_best = datetime.strptime(
            most_recent_str, "%Y-%m-%d %H:%M:%S")

    elif dep_type == 'modelable_entity_id':
        query = '''
            SELECT best_start from epi.model_version where is_best = 1 AND
            best_end IS NULL AND modelable_entity_id = %s''' % dep_id
        most_recent_best_df = query_tools.query_2_df(
            query, engine=enginer.engines["epi_prod"])
        if len(most_recent_best_df) == 0:
            most_recent_best = datetime(1800, 01, 01, 00, 00, 00)
        else:
            most_recent_best = (most_recent_best_df.ix[0, 'best_start'].
                                to_datetime())

    elif dep_type == 'process':
        query = '''
            SELECT best_start FROM cod.output_version WHERE
            is_best = 1 AND env_version = (SELECT MAX(env_version)
            FROM cod.output_version)'''
        most_recent_best_df = query_tools.query_2_df(
            query, engine=enginer.engines["cod_prod"])
        if len(most_recent_best_df) == 0:
            most_recent_best = datetime(1800, 01, 01, 00, 00, 00)
        elif most_recent_best_df.ix[0, 'best_start'] is None:
            most_recent_best = datetime(1800, 01, 01, 00, 00, 00)
        else:
            most_recent_best = (most_recent_best_df.ix[0, 'best_start'].
                                to_datetime())
    else:
        raise ValueError(
            '''Dep_type must be "cause_id", "modelable_entity_id",
               or "process"'''
        )

    return most_recent_best


def check_dependencies(step):
    '''
    Description: Checks dependencies of the step given, using the dependency
    map.

    Args: specify which step for which you want to check dependencies
        Options: 1, 2, 3, or '4'

    Output: True or False, which turns the step specified to 'On' or 'Off'
    '''
    dep_map = pd.read_csv(
        "dependency_map.csv", header=0).dropna(axis='columns', how='all')
    step_df = dep_map.ix[dep_map.step == step]
    enginer = dbapis.engine_factory()

    if len(step_df) != 0:
        bool_list = []
        for idx in step_df.index:
            src_date = get_best_date(
                enginer, step, step_df.ix[idx, "source_type"],
                step_df.ix[idx, "source_id"])
            trg_date = get_best_date(
                enginer, step, step_df.ix[idx, "target_type"],
                step_df.ix[idx, "target_id"])
            boolean = src_date > trg_date
            bool_list.append(boolean)

        if any(bool_list):
            return True
        else:
            return False
    else:
        raise ValueError("Must specify 1, 2, 3, or 4")
