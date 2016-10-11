import os
import pandas as pd
import sqlalchemy
from adding_machine.db import EpiDB
from hierarchies import dbtrees
from transmogrifier.gopher import version_id
from datetime import datetime
import getpass
import json
from . import git_info
from dws.combine import combine_epilepsy_any, combine_epilepsy_subcombos
from dws.urolithiasis import import_gbd2013

this_path = os.path.dirname(os.path.abspath(__file__))

# Set default file mask to readable-for all users
os.umask(0o0002)


class ComoVersion(object):

    def __init__(self, como_version_id, init_from_files=True):
        self.como_version_id = como_version_id
        self.root_dir = (
            "/ihme/centralcomp/como/{cvid}".format(
                cvid=self.como_version_id))
        self.drawcols = ['draw_%s' % i for i in range(1000)]

        if init_from_files:
            self.init_from_files()
        else:
            self.generate_version_directories()
            self.mvid_list = self.generate_mvid_list()
            self.seq_map = self.generate_seq_map()
            self.agg_cause_map = self.generate_agg_cause_map()
            self.cause_restrictions = self.generate_cause_restrictions()
            self.age_lu = self.generate_age_lu()
            self.pv_meta = json.loads(self.new_process_version())
            self.gbd_process_version_id = int(
                    self.pv_meta[0]["gbd_process_version_id"])
            self.gen_epilepsy_dws()
            self.gen_urolith_dws()
            self.generate_cause_list()
            self.hazard_list()

    @classmethod
    def new(cls, env='dev'):
        como_version_id = cls.generate_new_version(env)
        inst = cls(como_version_id, init_from_files=False)
        return inst

    @classmethod
    def generate_new_version(cls, env):
        if env == 'prod':
            db = EpiDB('epi')
        else:
            db = EpiDB('epi-dev')
        code_version = db.git_dict(this_path)
        code_version = str(code_version).replace("'", '"')
        como_version_id = db.create_como_version(2)
        return como_version_id

    def generate_version_directories(self):
        try:
            os.makedirs(self.root_dir)
            os.chmod(self.root_dir, 0o775)
        except:
            pass
        with open("%s/config/dirs.config" % this_path) as dirs_file:
            for d in dirs_file.readlines():
                if d.strip() != "":
                    try:
                        dir = os.path.join(self.root_dir, d.strip("\r\n"))
                        os.makedirs(dir)
                        os.chmod(dir, 0o775)
                    except:
                        pass

    def generate_mvid_list(self):
        eng = sqlalchemy.create_engine("stDir")
        meid_mvids = pd.read_sql("""
            SELECT modelable_entity_id, model_version_id
            FROM epi.model_version
            WHERE is_best=1""", eng)
        meid_mvids.to_csv(
            "{rd}/info/mvids.csv".format(rd=self.root_dir), index=False)
        return meid_mvids

    def generate_cause_list(self):
        eng = sqlalchemy.create_engine("strDir")
        causes = pd.read_sql(
            "SELECT cause_id, acause FROM shared.cause", eng)
        causes.to_csv(
            "{rd}/info/causes.csv".format(rd=self.root_dir), index=False)
        return causes

    def generate_seq_map(self):
        seqids = self.standard_sequela()
        seqids = seqids.append(self.injury_sequela())
        seqids.to_csv("{rd}/info/seq_map.csv".format(
                rd=self.root_dir), index=False)
        return seqids

    def generate_agg_cause_map(self):
        ct = dbtrees.causetree(None, 9)
        acm = []
        for n in ct.nodes:
            if len(n.all_descendants()) > 0:
                leaves = [l.id for l in n.leaves()]
                ac_seq = self.seq_map[self.seq_map.cause_id.isin(leaves)]
                ac_seq['cause_id'] = n.id
                if len(ac_seq) == 0:
                    print n.info
                acm.append(ac_seq)
        acm = pd.concat(acm)
        acm.to_csv("{rd}/info/agg_cause_map.csv".format(
                rd=self.root_dir), index=False)
        return acm

    def standard_sequela(self):
        eng = sqlalchemy.create_engine("strDir")
        seqids = pd.read_sql("""
            SELECT sequela_id, cause_id, modelable_entity_id, healthstate_id,
                under_3_mo
            FROM epi.sequela
            WHERE active_end IS NULL
            AND healthstate_id != 639""", eng)
        return seqids

    def injury_sequela(self):
        injmap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "long_term")
        self.ismap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "inj_seq_map")
        self.ismap = self.ismap[['n_code', 'sequela_id']]
        injmap = injmap.merge(self.ismap, on="n_code")
        injmap['healthstate_id'] = injmap.sequela_id
        injmap['cause_id'] = -1
        injmap = injmap.query('longterm == 1')
        self.auto_mark_latest(injmap.modelable_entity_id)
        return injmap[[
            'modelable_entity_id', 'sequela_id', 'cause_id', 'healthstate_id']]

    def hazard_list(self):
        nonhazmap = pd.read_excel(
                "%s/config/non-hazard_incidence_160729.xlsx" % this_path)
        nonhazmap = nonhazmap[['sequela_id']]
        nonhazmap.to_csv("{rd}/info/nonhaz_map.csv".format(
                rd=self.root_dir), index=False)
        self.nonhazmap = nonhazmap
        return nonhazmap

    def st_injury_by_cause(self):
        injmap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "short_term")
        injmap = injmap[injmap.cause_id.notnull()]
        injmap['cause_id'] = injmap.cause_id.astype(int)
        return injmap[[
            'modelable_entity_id', 'cause_id']]

    def injury_prev_by_cause(self):
        injmap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "ecode_prev")
        injmap = injmap[injmap.cause_id.notnull()]
        injmap['cause_id'] = injmap.cause_id.astype(int)
        return injmap[[
            'modelable_entity_id', 'cause_id']]

    def st_injury_by_sequela(self):
        injmap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "short_term")
        self.ismap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "inj_seq_map")
        self.ismap = self.ismap[['n_code', 'sequela_id']]
        injmap = injmap.merge(self.ismap, on="n_code")
        return injmap[[
            'modelable_entity_id', 'sequela_id']]

    def auto_mark_latest(self, meid_list):
        db = EpiDB('epi')
        for meid in meid_list:
            mvid = version_id(modelable_entity_id=meid, status='latest')
            if mvid is not None:
                mvid = mvid[0]
                db.mark_best(mvid, 'auto-marked for COMO')

    def generate_cause_restrictions(self):
        eng = sqlalchemy.create_engine("strDir")
        restrictions = pd.read_sql(
            """
            SELECT cause_id, male, female, yld_age_start, yld_age_end
            FROM shared.cause_hierarchy_history chh
            JOIN shared.cause_set_version csv USING(cause_set_version_id)
            JOIN shared.cause_set cs ON csv.cause_set_id=cs.cause_set_id
            WHERE cs.cause_set_id=3
            AND csv.end_date IS NULL""", eng)
        restrictions['yld_age_start'] = restrictions.yld_age_start.fillna(0)
        restrictions['yld_age_end'] = restrictions.yld_age_end.fillna(80)
        restrictions['yld_age_start'] = (
                restrictions.yld_age_start.round(2).astype(str))
        restrictions['yld_age_end'] = (
                restrictions.yld_age_end.round(2).astype(str))
        ridiculous_am = {
                '0.0': 2, '0.01': 3, '0.1': 4, '1.0': 5, '5.0': 6, '10.0': 7,
                '15.0': 8, '20.0': 9, '25.0': 10, '30.0': 11, '35.0': 12,
                '40.0': 13, '45.0': 14, '50.0': 15, '55.0': 16, '60.0': 17,
                '65.0': 18, '70.0': 19, '75.0': 20, '80.0': 21}
        restrictions['yld_age_start'] = (
                restrictions.yld_age_start.replace(ridiculous_am).astype(int))
        restrictions['yld_age_end'] = (
                restrictions.yld_age_end.replace(ridiculous_am).astype(int))

        restrictions = restrictions.append(pd.DataFrame([{
            'cause_id': -1, 'male': 1, 'female': 1, 'yld_age_start': 2,
            'yld_age_end': 21}]))
        restrictions.to_csv("{rd}/info/crs.csv".format(
                rd=self.root_dir), index=False)
        return restrictions

    def generate_age_lu(self):
        eng = sqlalchemy.create_engine("strDir")
        age_lu = pd.read_sql("""
                SELECT age_group_id, age_group_years_start, age_group_years_end
                FROM shared.age_group""", eng)
        age_lu.to_csv("{rd}/info/age_lu.csv".format(
                rd=self.root_dir), index=False)
        return age_lu

    def init_from_files(self):
        self.mvid_list = pd.read_csv("{rd}/info/mvids.csv".format(
                rd=self.root_dir))
        self.seq_map = pd.read_csv("{rd}/info/seq_map.csv".format(
                rd=self.root_dir))
        self.cause_restrictions = pd.read_csv("{rd}/info/crs.csv".format(
                rd=self.root_dir))
        self.age_lu = pd.read_csv("{rd}/info/age_lu.csv".format(
                rd=self.root_dir))
        with open("{rd}/info/pv_meta.json".format(rd=self.root_dir), "r") as f:
            self.pv_meta = json.loads("".join(f.readlines()))
            self.gbd_process_version_id = int(
                    self.pv_meta[0]["gbd_process_version_id"])
        self.ismap = pd.read_excel(
                "%s/config/como_inj_me_to_ncode.xlsx" % this_path,
                "inj_seq_map")
        self.ismap = self.ismap[['n_code', 'sequela_id']]
        self.agg_cause_map = pd.read_csv("{rd}/info/agg_cause_map.csv".format(
            rd=self.root_dir))
        self.nonhazmap = pd.read_csv("{rd}/info/nonhaz_map.csv".format(
                rd=self.root_dir))

    def new_process_version(self):
        q = """
        -- create a new process version
        CALL gbd.new_gbd_process_version (
            3, 1, 'Como run', 'run', NULL, NULL)"""
        db = EpiDB('gbd')
        eng = db.get_engine(db.dsn_name)
        res = eng.execute(q)
        row = res.fetchone()
        pv_meta = row[0]
        with open("{rd}/info/pv_meta.json".format(rd=self.root_dir), "w") as f:
            f.write(pv_meta)
        gbd_process_version_id = int(json.loads(
            pv_meta)[0]["gbd_process_version_id"])
        q = """
            INSERT INTO gbd.gbd_process_version_metadata
                (`gbd_process_version_id`, `metadata_type_id`, `val`)
            VALUES
                ({gpvid}, 4, '{cv}')""".format(
                    gpvid=gbd_process_version_id, cv=self.como_version_id)
        eng.execute(q)
        return pv_meta

    def mark_best(self):
        self.unmark_current_best()
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        desc = "test best"
        q = """
            UPDATE epi.output_version
            SET best_start='{bs}', best_end=NULL, is_best=1,
                best_description='{bd}', best_user='{bu}'
            WHERE output_version_id={ovid}""".format(
                bs=now, bd=desc, bu=getpass.getuser(),
                ovid=self.como_version_id)
        db = EpiDB('epi')
        eng = db.get_engine(db.dsn_name)
        res = eng.execute(q)
        return res

    def unmark_current_best(self):
        now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        q = """
            UPDATE epi.output_version
            SET best_end='{be}', is_best=0
            WHERE is_best=1""".format(be=now)
        db = EpiDB('epi')
        eng = db.get_engine(db.dsn_name)
        res = eng.execute(q)
        return res

    def write_git_info(self):
        with open("%s/info/git_info.txt" % self.root_dir) as f:
            f.write(git_info)
        return git_info

    def gen_epilepsy_dws(self):
        combine_epilepsy_any.epilepsy_any(self.como_version_id)
        combine_epilepsy_subcombos.epilepsy_combos(self.como_version_id)

    def gen_urolith_dws(self):
        import_gbd2013.to_como(self.como_version_id)

    def create_compare_version(self):
        db = EpiDB('gbd')
        eng = db.get_engine(db.dsn_name)
        bestvs = pd.read_sql("""
            SELECT gbd_process_name as name, gbd_process_version_id as id
            FROM gbd.gbd_process_version
            JOIN (
                SELECT DISTINCT(gbd_process_version_id)
                FROM gbd.compare_version
                JOIN gbd.compare_version_output USING(compare_version_id)
                WHERE compare_version_status_id=1 AND gbd_round_id=3) best
            USING(gbd_process_version_id)
            JOIN gbd.gbd_process USING(gbd_process_id)
            WHERE gbd_process_id != 1""", eng)
        bestvs['vstr'] = bestvs.apply(
                lambda x: "{pname}={pid}".format(
                    pname="_".join(x['name'].split(" ")[1:]).lower(),
                    pid=x['id']), axis=1)
        pvstr = ", ".join(
                ["epi=%s" % self.gbd_process_version_id]+list(bestvs.vstr))
        pvids = [self.gbd_process_version_id] + list(bestvs.id)

        cv_q = """
            INSERT INTO gbd.compare_version
            (
                gbd_round_id,
                compare_version_description,
                compare_version_status_id)
            VALUES
            (3, '{desc}', 2)""".format(desc=pvstr)
        res = eng.execute(cv_q)
        cvid = res.lastrowid

        for pvid in pvids:
            pv_q = """
                INSERT INTO gbd.compare_version_output
                (compare_version_id,
                measure_id,
                template_id,
                compare_context_id,
                output_table_name,
                gbd_process_version_id
                )
                SELECT
                    {compare_vid} as compare_version_id,
                    map.measure_id,
                    map.template_id,
                    map.compare_context_id,
                    CONCAT(
                        t.template_name,
                        '_v',
                        CAST(pv.gbd_process_version_id AS CHAR))
                    as output_table_name,
                    pv.gbd_process_version_id
                FROM
                    gbd.gbd_process_measure_context_template map
                    INNER JOIN
                    gbd.gbd_process_version pv
                    ON map.gbd_process_id = pv.gbd_process_id
                    INNER JOIN
                    gbd.template t
                    ON map.template_id = t.template_id
                WHERE
                    pv.gbd_process_version_id = {process_vid};""".format(
                    compare_vid=cvid, process_vid=pvid)
            eng.execute(pv_q)
        unmark = """
            UPDATE gbd.compare_version SET compare_version_status_id=2
            WHERE compare_version_status_id=1 AND gbd_round_id=3"""
        eng.execute(unmark)
        mark = """
            UPDATE gbd.compare_version SET compare_version_status_id=1
            WHERE compare_version_id={cvid}""".format(cvid=cvid)
        eng.execute(mark)
        return pvstr
