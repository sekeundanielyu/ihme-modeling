import json
import getpass
import subprocess
import os
import sys
try:
    from db_tools import dbapis, query_tools, loaders
except:
    sys.path.append(str(os.getcwd()).rstrip('/mmr'))
    from db_tools import dbapis, query_tools, loaders


def read_json(file_path):
    json_data = open(file_path)
    data = json.load(json_data)
    json_data.close()
    return data

# get passwords from home directory
credential_path = "/homes/%s/credentials.json" % (getpass.getuser())

c = read_json(credential_path)
user, password = c['user'], c['password']

enginer = dbapis.engine_factory()
enginer.servers["gbd"] = {"prod": "modeling-gbd-db.ihme.washington.edu",
                          "test": "gbd-db-t01.ihme.washington.edu"}
enginer.define_engine(engine_name='gbd_test', server_name="gbd",
                      default_schema='gbd', envr='test',
                      user=user, password=password)
enginer.define_engine(engine_name='gbd_prod', server_name="gbd",
                      default_schema='gbd', envr='prod',
                      user=user, password=password)


def create_tables(gbd_env):
    code_version = str(subprocess.check_output(["git", "rev-parse", "HEAD"]))
    query = ('SELECT MAX(kit_version_id) AS kit_vers '
             'FROM gbd.kit_version '
             'WHERE kit_id = 2')
    vers_df = query_tools.query_2_df(query, engine=enginer.engines[gbd_env])
    kit_id = vers_df.loc[0, 'kit_vers']
    kit_id = int(kit_id) + 1

    query = ('CALL gbd.new_gbd_process_version(3, 12, "MMR Upload", "%s", '
             'NULL, %s)' % (code_version.rstrip('\n'), kit_id))
    gbd_process = query_tools.query_2_df(
        query, engine=enginer.engines[gbd_env])
    return gbd_process


def upload(gbd_env, sm, process_v, in_dir):
    '''Args: gbd_env: 'gbd_prod' or 'gbd_test'
             sm: 'single' or 'multi', referring to which table to use
             process_v: comes from the output of above
             in_dir: filepath of csvs to be uploaded
    '''
    session_fac = dbapis.session_factory(engine=enginer.engines[gbd_env])
    sess = session_fac.open_session(session_name="mat_load", replace=True)
    subprocess.call(['chmod', '777', in_dir])
    loader = loaders.infiles(table='output_mmr_' + sm + '_year_v' +
                             str(process_v),
                             schema='gbd', session=sess)
    loader.indir(path=in_dir, with_replace=True, commit=True)
    print "Uploaded!"



