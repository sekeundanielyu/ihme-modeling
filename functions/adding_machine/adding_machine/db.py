import re
import os
import sqlalchemy
import subprocess
from datetime import datetime
import getpass
import pandas as pd
import json

this_path = os.path.realpath(os.path.dirname(__file__))
root_path = os.path.join(this_path, "..")


class EpiDB(object):

    def __init__(self, dsn_name='epi-dev-custom', odbc_filepath="~/.odbc.ini"):
        self.dsn_name = dsn_name
        self.odbc_filepath = odbc_filepath

    def get_odbc_defs(self):
        with open(os.path.expanduser(self.odbc_filepath)) as f:
            lines = f.readlines()
        conn_defs = {}
        def_name = ''
        for l in lines:

            # Identify whether this is a new connection definition
            name_match = re.search("\[.*\]", l)
            if name_match is not None:
                def_name = name_match.group()[1:-1]
                conn_defs[def_name] = {}
                continue

            # Skips any blank leading lines
            if def_name == '':
                continue

            # Read key, value pairs
            tokens = l.split("=")
            if len(tokens) < 2:
                continue
            k, v = tokens[0:2]
            k = k.strip().lower()
            v = v.strip()
            conn_defs[def_name][k] = v
        return conn_defs

    def connection_string(self, def_name):
        conn_def = self.get_odbc_defs()[def_name]
        user = conn_def['user']
        passw = conn_def['password']
        server = conn_def['server']
        if conn_def['port'] is not None:
            port = conn_def['port']
        else:
            port = 3306
        connstr = (
            "mysql+pymysql://{user}:{passw}@{server}:{port}/"
            "?charset=utf8&use_unicode=0".format(
                user=user, passw=passw, server=server, port=port))
        return connstr

    def get_engine(self, def_name):
        cstr = self.connection_string(def_name)
        return sqlalchemy.create_engine(cstr)

    def create_model_version(self, meid, description, location_set_version_id):
        eng = self.get_engine(self.dsn_name)
        code_version = str(self.git_dict(root_path)).replace("'", '"')
        res = eng.execute("""
            INSERT INTO epi.model_version (
                modelable_entity_id,
                description,
                code_version,
                location_set_version_id,
                model_version_status_id,
                is_best,
                drill,
                data_likelihood,
                prior_likelihood,
                fix_cov,
                fix_sex,
                fix_year,
                external,
                cross_validate_id
            )
            VALUES(
                {meid},
                '{description}',
                '{code_version}',
                {lsvid},
                0, 0, 0, -1, -1, -1, -1, -1, 0, 0)""".format(
                    meid=meid,
                    description=description,
                    code_version=code_version,
                    lsvid=location_set_version_id))
        mvid = res.lastrowid
        if self.dsn_name == 'epi-dev-custom':
            drawsdir = "/ihme/epi/panda_cascade/dev/{mvid}/full/draws".format(
                mvid=mvid)
        elif self.dsn_name == 'epi':
            drawsdir = "/ihme/epi/panda_cascade/prod/{mvid}/full/draws".format(
                mvid=mvid)
        try:
            os.makedirs(drawsdir)
        except:
            pass
        return mvid

    def unmark_current_best(self, meid):
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        q = """
            UPDATE epi.model_version
            SET best_end='%s', is_best=0
            WHERE modelable_entity_id=%s AND is_best=1""" % (now, meid)
        eng = self.get_engine(self.dsn_name)
        res = eng.execute(q)
        return res

    def mark_best(self, mvid, desc):
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        q = """
            UPDATE epi.model_version
            SET best_start='{bs}', best_end=NULL, is_best=1,
                best_description='{bd}', best_user='{bu}'
            WHERE model_version_id={mvid}""".format(
                bs=now, bd=desc, bu=getpass.getuser(), mvid=mvid)
        meid = self.get_meid_from_mv(mvid)
        self.unmark_current_best(meid)
        eng = self.get_engine(self.dsn_name)
        res = eng.execute(q)
        return res

    def update_status(self, mvid, new_status):
        q = """
            UPDATE epi.model_version
            SET model_version_status_id={status}
            WHERE model_version_id={mvid}""".format(
                status=new_status, mvid=mvid)
        eng = self.get_engine(self.dsn_name)
        res = eng.execute(q)
        return res

    def upload_summaries(self, summary_file, mvid):
        summary_file = os.path.normpath(
            os.path.realpath(
                os.path.abspath(os.path.expanduser(summary_file))))
        ldstr = """
            LOAD DATA INFILE '{sf}'
            INTO TABLE epi.model_estimate_final
            FIELDS
                TERMINATED BY ","
                OPTIONALLY ENCLOSED BY '"'
            LINES
                TERMINATED BY "\\n"
            IGNORE 1 LINES
                (location_id, year_id, age_group_id, sex_id, measure_id,
                 mean, lower, upper)
            SET model_version_id = {mvid}""".format(sf=summary_file, mvid=mvid)
        eng = self.get_engine(self.dsn_name)
        res = eng.execute(ldstr)
        return res

    def get_commit_hash(self, dir="."):
        cmd = ['git', '--git-dir=%s/.git' % dir, '--work-tree=%s',
               'rev-parse', 'HEAD']
        return subprocess.check_output(cmd).strip()

    def get_branch(self, dir="."):
        cmd = ['git', '--git-dir=%s/.git' % dir, '--work-tree=%s',
               'rev-parse', '--abbrev-ref', 'HEAD']
        return subprocess.check_output(cmd).strip()

    def git_dict(self, dir="."):
        installed_vfile = os.path.join(this_path, "__version__.txt")
        if os.path.isfile(installed_vfile):
            with open(installed_vfile) as vf:
                return json.load(vf)
        branch = self.get_branch(dir)
        commit = self.get_commit_hash(dir)
        path = os.path.normpath(os.path.abspath(os.path.expanduser(dir)))
        return {'path': path, 'branch': branch, 'commit': commit}

    def get_model_quota_available(self, meid):
        eng = self.get_engine(self.dsn_name)
        available = pd.read_sql("""
            SELECT model_quota_available FROM epi.v_epi_model_quota
            WHERE modelable_entity_id=%s""" % meid, eng)
        return available.model_quota_available.values[0]

    def create_como_version(self, code_version):
        eng = self.get_engine(self.dsn_name)
        res = eng.execute("""
            INSERT INTO epi.output_version (
                username,
                description,
                code_version,
                status,
                is_best
            )
            VALUES(
                'strUser',
                'Central COMO run',
                '{code_version}',
                0,
                0)""".format(code_version=code_version))
        como_version_id = res.lastrowid
        return como_version_id

    def get_meid_from_mv(self, mv):
        eng = self.get_engine(self.dsn_name)
        """Return the meid for a given model_version"""
        meid = pd.read_sql("""
            SELECT modelable_entity_id FROM epi.model_version
            WHERE model_version_id=%s""" % mv, eng)
        return meid.modelable_entity_id.values[0]
