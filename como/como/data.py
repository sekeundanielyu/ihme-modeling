import pandas as pd
from adding_machine.super_gopher import SuperGopher
from multiprocessing import Process, Queue
from functools import partial
import validations
import os
from aggregate import agg_cause_hierarchy
from adding_machine.summarizers import get_pop

this_path = os.path.dirname(os.path.abspath(__file__))
sentinel = None

# Set default file mask to readable-for all users
os.umask(0o0002)


def get_mvid_draws(meid, mvid, env, lid, yid, sid, mid=[3, 5, 6]):
    print 'Reading draws for (meid, mvid): (%s, %s)' % (meid, mvid)
    meid_dd = (
        '/ihme/epi/panda_cascade/{e}/{mvid}/full/draws'.format(
            e=env, mvid=mvid))
    sg = SuperGopher.auto(meid_dd)
    draws = sg.content(
            location_id=lid,
            year_id=yid,
            sex_id=sid,
            measure_id=mid)
    print 'Draws read for (meid, mvid): (%s, %s)' % (meid, mvid)
    draws['modelable_entity_id'] = meid
    return draws


def qget_mvid_draws(inq, outq, env, lid, yid, sid, mid=[3, 5, 6]):
    for arglist in iter(inq.get, sentinel):
        try:
            meid, mvid = arglist
            draws = get_mvid_draws(meid, mvid, env, lid, yid, sid, mid)
            outq.put(draws)
        except Exception as e:
            print 'Could not find (meid, mvid): (%s, %s)' % (meid, mvid)
            outq.put({'error': e, 'meid': meid, 'mvid': mvid})


class ComoData(object):

    def __init__(self, como_version, location_id, year_id, sex_id, env='dev'):
        """Initialize a data-keeping object

        Arguments:
            como_version (ComoVersion): An instance of ComoVersion
            location_id (int): The location_id of the data
            year_id (int): The year_id of the data
            sex_id (int): The sex_id of the data
        """
        self.cv = como_version
        self.env = env
        self.lid = location_id
        self.yid = year_id
        self.sid = sex_id
        self.drawcols = ['draw_%s' % d for d in range(1000)]
        self.keycols = [
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'sequela_id', 'modelable_entity_id', 'cause_id',
                'healthstate_id']

        self.prevalence = self.get_all_draws()
        self.convert_inj_ylds()
        self.prevalence = self.attach_sequela_ids()
        self.prevalence = self.apply_restrictions(self.prevalence)
        self.incidence = self.prevalence.query('measure_id == 6')
        self.prevalence = self.prevalence.query('measure_id == 5')
        self.convert_from_inc_hazards()
        self.write_prevalence()
        self.write_acute_prevalence()
        self.write_chronic_prevalence()
        self.write_incidence()
        self.write_cause_incidence()
        self.write_acute_incidence()

        self.dws = self.get_dws()
        self.id_dws = self._get_id_dws()
        self.age_lu = self.get_age_lookup_dict()

    def get_all_draws(self, nprocs=20):
        meidq = Queue()
        dq = Queue()

        # Create and feed reader procs
        pget_mvid_draws = partial(
                qget_mvid_draws, env=self.env, lid=self.lid, yid=self.yid,
                sid=self.sid)
        read_procs = []
        for i in range(nprocs):
            p = Process(target=pget_mvid_draws, args=(meidq, dq))
            read_procs.append(p)
            p.start()

        # Feed and close the meid queue
        seq_list = self.cv.mvid_list.merge(
                self.cv.seq_map, on='modelable_entity_id')
        st_inj_clist = self.cv.mvid_list.merge(
                self.cv.st_injury_by_cause(), on='modelable_entity_id')
        st_inj_slist = self.cv.mvid_list.merge(
                self.cv.st_injury_by_sequela(), on='modelable_entity_id')
        inj_cprev = self.cv.mvid_list.merge(
                self.cv.injury_prev_by_cause(), on='modelable_entity_id')
        memv_list = pd.concat(
            [seq_list, st_inj_clist, st_inj_slist, inj_cprev])[[
                'modelable_entity_id', 'model_version_id']]
        arglist = zip(
                list(memv_list.modelable_entity_id),
                list(memv_list.model_version_id))
        arglist = list(set(arglist))
        for meid in arglist:
            meidq.put(meid)
        for p in read_procs:
            meidq.put(sentinel)

        # Build output df from reader procs
        df = [dq.get() for i in arglist]
        for p in read_procs:
            p.join()
        errs = [e for e in df if isinstance(e, dict)]
        print errs
        df = pd.concat([d for d in df if not isinstance(d, dict)])
        df = df[[
            'modelable_entity_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id', 'measure_id']+['draw_%s' % d for d in range(1000)]]
        self.st_inj_by_cause = df.merge(st_inj_clist, on='modelable_entity_id')
        self.st_inj_by_cause = self.st_inj_by_cause.query('measure_id == 3')
        self.st_inj_by_seq = df.merge(st_inj_slist, on='modelable_entity_id')
        self.st_inj_by_seq = self.st_inj_by_seq.query('measure_id == 3')
        self.inj_cprev = df.merge(inj_cprev, on='modelable_entity_id')
        self.inj_cprev = self.inj_cprev.query('measure_id == 5')
        self.inj_cprev = self.inj_cprev[
                ['location_id', 'year_id', 'age_group_id', 'sex_id',
                 'cause_id']+self.drawcols].groupby(
                    ['location_id', 'year_id', 'age_group_id', 'sex_id',
                     'cause_id']).sum().reset_index()
        df = df[df.modelable_entity_id.isin(seq_list.modelable_entity_id)]
        self.gen_reports(df)
        df = self.fill_expected_me_age_sets(df)
        df = self.cast_ids_to_ints(df)
        return df

    def convert_inj_ylds(self):
        pop = get_pop({
            'location_id': self.lid, 'sex_id': self.sid, 'year_id': self.yid})
        self.st_inj_by_cause = self.st_inj_by_cause.merge(pop)
        self.st_inj_by_seq = self.st_inj_by_seq.merge(pop)
        self.st_inj_by_cause.ix[:, self.drawcols] = (
                self.st_inj_by_cause.ix[:, self.drawcols].values /
                self.st_inj_by_cause[['pop_scaled']].values)
        self.st_inj_by_seq.ix[:, self.drawcols] = (
                self.st_inj_by_seq.ix[:, self.drawcols].values /
                self.st_inj_by_seq[['pop_scaled']].values)

    def fill_expected_me_age_sets(self, df):
        expect = self.cv.seq_map[['modelable_entity_id']]
        expect['expected'] = 1
        expect = expect.merge(pd.DataFrame({
            'age_group_id': range(2, 22), 'location_id': self.lid,
            'year_id': self.yid, 'sex_id': self.sid, 'expected': 1}))
        expect['measure_id'] = 5
        expect = pd.concat([expect, expect.replace({'measure_id': {5: 6}})])
        filldf = expect.merge(
                df,
                on=['location_id', 'year_id', 'age_group_id', 'sex_id',
                    'modelable_entity_id', 'measure_id'],
                how='outer')
        filldf = filldf[filldf.expected == 1]

        # Write missingness to files
        try:
            odir = os.path.join(self.cv.root_dir, 'diagnostics')
            ofile = '%s/missing_%s_%s_%s.h5' % (
                    odir, self.lid, self.yid, self.sid)
            cols = [
                    'modelable_entity_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id', 'measure_id']
            filldf[filldf.draw_0.isnull()][cols].to_hdf(
                    ofile, 'draws', mode='w', format='t')
        except:
            print 'Could not write diagnostic file'
        filldf.drop('expected', axis=1, inplace=True)
        filldf = filldf.set_index([
            'modelable_entity_id', 'age_group_id', 'location_id', 'year_id',
            'sex_id', 'measure_id'])
        filldf = filldf.fillna(0)
        filldf = filldf.reset_index()
        return filldf

    def cast_ids_to_ints(self, df):
        thisdf = df.copy()
        id_cols = [c for c in thisdf.columns if 'id' in c]
        for c in id_cols:
            try:
                thisdf[c] = thisdf[c].astype(int)
            except:
                pass
        return thisdf

    def get_dws(self):
        dws = self._get_standard_dws()
        dws = dws.append(self._get_custom_dws())
        dws = dws.append(self._get_inj_dws())
        dws = dws.append(self._get_epi_dws())
        dws = dws.append(self._get_mnd_dws())
        dws = dws.append(self._get_autism_dws())
        dws = dws.append(self._get_uro_dws())

        # Asymp
        asymp_row = {'draw_%s' % i: 0 for i in range(1000)}
        asymp_row['healthstate_id'] = 799
        dws = dws.append(pd.DataFrame([asymp_row]))
        dws = dws.reset_index(drop=True)
        dws = dws[['healthstate_id']+self.drawcols]
        return dws

    def _get_standard_dws(self):
        dws = pd.read_csv(
            "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv")
        dws.rename(
                columns={d.replace("_", ""): d for d in self.drawcols},
                inplace=True)
        return dws

    def _get_custom_dws(self):
        dws = pd.read_csv(
            "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/"
            "combined_dws.csv")
        dws.rename(
                columns={d.replace("_", ""): d for d in self.drawcols},
                inplace=True)
        return dws

    def _get_id_dws(self):
        dws = pd.read_csv(
            "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/"
            "combined_id_dws.csv")
        dws['age_end'] = dws['age_end']+1
        dws['age_end'] = dws.age_end.replace({101: 200})
        dws.rename(
                columns={d.replace("_", ""): d for d in self.drawcols},
                inplace=True)
        return dws

    def _get_mnd_dws(self):
        dws = pd.read_csv(
            "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/"
            "combined_mnd_dws.csv")
        return dws

    def _get_autism_dws(self):
        dws = pd.read_csv(
            "/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/"
            "autism_dws.csv")
        return dws

    def _get_epi_dws(self):
        eafp = os.path.join(self.cv.root_dir, 'info', 'epilepsy_any_dws.h5')
        ecfp = os.path.join(self.cv.root_dir, 'info', 'epilepsy_combo_dws.h5')
        epi_any = pd.read_hdf(
            eafp, 'draws',
            where='location_id == {l} & year_id == {y}'.format(
                l=self.lid, y=self.yid))
        epi_combos = pd.read_hdf(
            ecfp, 'draws',
            where='location_id == {l} & year_id == {y}'.format(
                l=self.lid, y=self.yid))
        epi_dws = pd.concat([epi_any, epi_combos])
        return epi_dws[['healthstate_id']+self.drawcols]

    def _get_uro_dws(self):
        fp = os.path.join(self.cv.root_dir, 'info', 'urolith_dws.h5')
        uro_dws = pd.read_hdf(
            fp, 'draws',
            where='location_id == {l} & year_id == {y}'.format(
                l=self.lid, y=self.yid))
        return uro_dws[['healthstate_id']+self.drawcols]

    def _get_inj_dws(self):
        inj_dws = pd.read_csv(
            "/ihme/epi/injuries/lt_dws/draws/{l}_{y}.csv".format(
                l=self.lid, y=self.yid))
        inj_dws = inj_dws.merge(
                self.cv.ismap,
                left_on="healthstate",
                right_on="n_code")
        inj_dws['healthstate_id'] = inj_dws.sequela_id
        inj_dws = inj_dws[['sequela_id', 'healthstate_id']+self.drawcols]
        return inj_dws

    def check_draws(self):
        dctest = validations.has_all_draw_cols(self.prevalence)
        rngtest = validations.has_valid_range(
            self.prevalence,
            ['draw_%s' % d for d in range(1000)],
            lower=0,
            upper=1)
        nulltest = validations.has_no_null_values(
                self.prevalence,
                self.prevalence.columns)
        has_all_hsids = len(
                set(self.prevalence.healthstate_id) -
                set(self.dws.healthstate_id)) == 0
        return dctest, rngtest, nulltest, has_all_hsids

    def apply_restrictions(self, df):
        restrictions = self.get_restrictions()
        restricted = df.merge(restrictions, on='cause_id')

        r_bool = (
            (restricted.age_group_id < restricted.yld_age_start) |
            (restricted.age_group_id > restricted.yld_age_end) |
            ((restricted.sex_id == 1) & (restricted.male == 0)) |
            ((restricted.sex_id == 2) & (restricted.female == 0)))
        restricted.ix[r_bool, self.drawcols] = 0

        # Restrict to non-aggregate age groups
        r_bool = (restricted.age_group_id.isin(range(2, 22)))
        restricted = restricted[r_bool]
        return restricted

    def write_prevalence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=5, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'sequela', 'total', fn)
        wcols = [c for c in self.keycols+self.drawcols
                 if c in self.prevalence.columns]
        self.prevalence[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'sequela_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_cause_prevalence(self, agg_cause_prev):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=5, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'total', fn)
        cause_prev = self.prevalence.groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_prev = cause_prev[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.drawcols]
        cause_prev = cause_prev.append(agg_cause_prev)
        wcols = [c for c in self.keycols+self.drawcols
                 if c in cause_prev.columns]
        cause_prev[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'cause_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_acute_prevalence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=23, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'acute', fn)
        sp = self.prevalence.merge(
                self.cv.seq_map[['sequela_id', 'under_3_mo']])
        cause_prev = sp[sp.under_3_mo == 1].groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_prev = cause_prev[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.drawcols]
        wcols = [c for c in self.keycols+self.drawcols
                 if c in cause_prev.columns]
        cause_prev['measure_id'] = 23
        cause_prev[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'cause_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_chronic_prevalence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=22, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'chronic', fn)
        sp = self.prevalence.merge(
                self.cv.seq_map[['sequela_id', 'under_3_mo']])
        cause_prev = sp[sp.under_3_mo == 0].groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_prev = cause_prev[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.drawcols]
        wcols = [c for c in self.keycols+self.drawcols
                 if c in cause_prev.columns]
        cause_prev['measure_id'] = 22
        cause_prev[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'cause_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_incidence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=6, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'sequela', 'total', fn)
        wcols = [c for c in self.keycols+self.drawcols
                 if c in self.incidence.columns]
        self.incidence[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'sequela_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_cause_incidence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=6, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'total', fn)
        cause_inc = self.incidence.groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_inc = cause_inc[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.drawcols]
        wcols = [c for c in self.keycols+self.drawcols
                 if c in cause_inc]
        cause_inc = agg_cause_hierarchy(cause_inc)
        cause_inc[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'cause_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def write_acute_incidence(self):
        fn = "{mid}_{lid}_{yid}_{sid}.h5".format(
                mid=24, lid=self.lid, yid=self.yid, sid=self.sid)
        fp = os.path.join(self.cv.root_dir, 'draws', 'cause', 'acute', fn)
        si = self.incidence.merge(
                self.cv.seq_map[['sequela_id', 'under_3_mo']])
        cause_inc = si[si.under_3_mo == 1].groupby([
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']).sum().reset_index()
        cause_inc = cause_inc[[
            'cause_id', 'location_id', 'year_id', 'age_group_id',
            'sex_id']+self.drawcols]
        wcols = [c for c in self.keycols+self.drawcols
                 if c in cause_inc]
        cause_inc['measure_id'] = 24
        cause_inc[wcols].to_hdf(
                fp, 'draws', mode='w', format='table',
                data_columns=[
                    'measure_id', 'cause_id', 'location_id', 'year_id',
                    'age_group_id', 'sex_id'])

    def attach_sequela_ids(self):
        seqids = self.cv.seq_map
        prev = self.prevalence.merge(
            seqids, on='modelable_entity_id', how='left')
        prev = prev.groupby([
            'location_id', 'year_id', 'age_group_id', 'sex_id', 'sequela_id',
            'cause_id', 'healthstate_id', 'measure_id']).sum()
        prev = prev[self.drawcols].reset_index()
        prev = prev.reset_index(drop=True)
        return prev

    def get_age_lookup_dict(self):
        age_lu = self.get_age_lookup()
        return age_lu.set_index('age_group_id').to_dict(orient='index')

    def get_age_lookup(self):
        return self.cv.age_lu

    def get_restrictions(self):
        return self.cv.cause_restrictions

    def convert_from_inc_hazards(self):
        cols = ['location_id', 'year_id', 'age_group_id',
                'sex_id', 'cause_id', 'sequela_id']+self.drawcols
        nhzbool = self.incidence.sequela_id.isin(self.cv.nonhazmap.sequela_id)
        nhz = self.incidence.ix[nhzbool, cols]
        ti = self.incidence.ix[~nhzbool, cols].merge(
                self.prevalence[cols],
                on=['location_id', 'year_id', 'age_group_id', 'sex_id',
                    'cause_id', 'sequela_id'],
                suffixes=('_inc', '_prev'))
        ti = ti.reset_index(drop=True)
        ti = ti.join(pd.DataFrame((
                ti.filter(regex="_inc$").values *
                (1-ti.filter(regex='_prev$')).values),
            index=ti.index,
            columns=self.drawcols))
        ti = ti[cols].append(nhz)
        self.incidence = ti
        return self.incidence

    def gen_reports(self, df):
        pass
