from __future__ import division
import pandas as pd
from transmogrifier.transmogrifier import gopher
from db_tools import dbapis, query_tools
import numpy as np
import sys


class Base(object):
    def __init__(self, cluster_dir, year_id, input_me, output_me):
        self.cluster_dir = cluster_dir
        self.year_id = year_id
        self.input_me = input_me
        self.output_me = output_me
        self.enginer = dbapis.engine_factory()

    def get_locations(self, location_set_id):
        query = ('SELECT location_id, most_detailed FROM shared.'
                 'location_hierarchy_history WHERE location_set_version_id=('
                 'SELECT location_set_version_id FROM shared.location_set_'
                 'version WHERE location_set_id = %s AND end_date IS NULL) '
                 'AND most_detailed = 1' % location_set_id)
        loc_df = query_tools.query_2_df(query,
                                        engine=self.enginer.
                                        engines["cod_prod"])
        return loc_df

    def get_asfr(self):
        query = ('SELECT '
                 'model.location_id, model.year_id, model.age_group_id, '
                 'model.sex_id, model.mean_value AS asfr FROM covariate.model '
                 'JOIN covariate.model_version ON model.model_version_id='
                 'model_version.model_version_id JOIN covariate.data_version '
                 'ON model_version.data_version_id=data_version.'
                 'data_version_id JOIN shared.covariate ON data_version.'
                 'covariate_id=covariate.covariate_id '
                 'AND covariate.last_updated_action!="DELETE" AND is_best=1 '
                 'AND covariate.covariate_id= 13 AND model.age_group_id '
                 'BETWEEN 7 AND 15 AND model.year_id = %s' % self.year_id)
        asfr = query_tools.query_2_df(query,
                                      engine=self.enginer.engines["cov_prod"])
        asfr['sex_id'] = 2
        loc_df = self.get_locations(35)
        asfr = asfr.merge(loc_df, on='location_id', how='inner')
        asfr.drop('most_detailed', axis=1, inplace=True)
        return asfr

    def get_draws(self, measure_id=6):
        draws = gopher.draws(gbd_ids={'modelable_entity_ids': [self.input_me]},
                             source='epi', measure_ids=[measure_id],
                             location_ids=[], year_ids=[self.year_id],
                             age_group_ids=[7, 8, 9, 10, 11, 12, 13, 14, 15],
                             sex_ids=[2])
        loc_df = self.get_locations(35)
        draws = draws.merge(loc_df, on='location_id', how='inner')
        draws.drop('most_detailed', axis=1, inplace=True)
        return draws

    def keep_cols(self):
        draw_cols = ['draw_%s' % i for i in xrange(1000)]
        index_cols = ['location_id', 'year_id', 'age_group_id', 'sex_id']
        keep_cols = list(draw_cols)
        keep_cols.extend(index_cols)
        return keep_cols, index_cols, draw_cols

    def get_new_incidence(self, draw_df, asfr_df):
        keep_cols, index_cols, draw_cols = self.keep_cols()
        # make sure dataframes match in terms of indexes
        new_draws = draw_df.copy(deep=True)
        new_draws = new_draws[keep_cols]
        asfr_cols = list(index_cols)
        asfr_cols.append('asfr')
        new_asfr = asfr_df.copy(deep=True)
        new_asfr = new_asfr[asfr_cols]

        # multiply incidence by asfr to get new incidence
        new_incidence = new_draws.merge(new_asfr, on=index_cols, how='inner')
        for col in draw_cols:
            new_incidence['%s' % col] = (new_incidence['%s' % col] *
                                         new_incidence['asfr'])
        new_incidence.drop('asfr', axis=1, inplace=True)
        return new_incidence

    def mul_draws(self, draw_df, other_df):
        keep_cols, index_cols, draw_cols = self.keep_cols()
        new_draws = draw_df.copy(deep=True)
        new_draws[draw_cols] = new_draws[draw_cols].mul(other_df, axis=1)
        return new_draws

    def create_draws(self, mean, lower, upper):
        '''For the purpose of severity splits or duration'''
        sd = (upper - lower) / (2 * 1.96)
        sample_size = mean * (1 - mean) / sd ** 2
        alpha = mean * sample_size
        beta = (1 - mean) * sample_size
        draws = np.random.beta(alpha, beta, size=1000)
        return draws

    def squeeze_severity_splits(self, sev_df1, sev_df2):
        drawsum = sev_df1 + sev_df2
        sev_df1 = sev_df1 / drawsum
        sev_df2 = sev_df2 / drawsum
        return sev_df1, sev_df2

    def data_rich_data_poor(self, df):
        '''Splits a given dataframe into two dataframes, based on
            data rich or data poor, and returns the two dfs'''
        query = ('SELECT location_id, parent_id FROM shared.'
                 'location_hierarchy_history WHERE location_set_version_id=('
                 'SELECT location_set_version_id FROM shared.location_set_'
                 'version WHERE location_set_id = 43 AND end_date IS NULL)')
        loc_df = query_tools.query_2_df(query,
                                        engine=self.enginer.
                                        engines["cod_prod"])
        all = df.merge(loc_df, on='location_id', how='inner')
        data_rich = all.query("parent_id==44640")
        data_rich.drop('parent_id', axis=1, inplace=True)
        data_poor = all.query("parent_id==44641")
        data_poor.drop('parent_id', axis=1, inplace=True)
        return data_rich, data_poor

    def output(self, df, output_me, measure):
        out_dir = '%s/%s' % (self.cluster_dir, output_me)
        locations = df.location_id.unique()
        year = df.year_id.unique().item()
        year = int(year)
        for geo in locations:
            output = df[df.location_id == geo]
            output.to_csv('%s/%s_%s_%s_2.csv' % (out_dir, measure,
                                                 geo, year), index=False)

    def output_for_epiuploader(self, df, output_me):
        out_dir = '%s/%s' % (self.cluster_dir, output_me)
        year = df.year_start.unique().item()
        year = int(year)
        df.to_csv('%s/sepsis_inc_infertility_%s.csv' % (out_dir, year),
                  index=False, encoding='utf-8')


class Abortion(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        # get incidence draws
        draws = self.get_draws()
        # create new incidence
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create new prevalence
        duration = self.create_draws(0.0082, 0.0055, 0.0110)
        new_prev = self.mul_draws(new_inc, duration)
        self.output(new_prev, output_me, 5)


class Hemorrhage(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me, mod_seq_me,
                 sev_seq_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        self.mod_seq_me = mod_seq_me
        self.sev_seq_me = sev_seq_me
        # pull in incidence draws
        draws = self.get_draws()
        # create new incidence
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # generate severity draws
        moderate = self.create_draws(0.85, 0.80, 0.90)
        severe = self.create_draws(0.15, 0.10, 0.20)
        # squeeze severities
        moderate, severe = self.squeeze_severity_splits(moderate, severe)
        # generate duration draws
        moderate_dur = self.create_draws(7 / 365, 4 / 365, 10 / 365)
        severe_dur = self.create_draws(14 / 365, 10 / 365, 18 / 365)
        # create moderate and severe incidence
        mod_inc = self.mul_draws(new_inc, moderate)
        sev_inc = self.mul_draws(new_inc, severe)
        # output moderate and severe incidence
        self.output(mod_inc, mod_seq_me, 6)
        self.output(sev_inc, sev_seq_me, 6)
        # create moderate and severe prevalence
        mod_prev = self.mul_draws(mod_inc, moderate_dur)
        sev_prev = self.mul_draws(sev_inc, severe_dur)
        # output moderate and severe incidence and prevalence
        self.output(mod_prev, mod_seq_me, 5)
        self.output(sev_prev, sev_seq_me, 5)


class Eclampsia(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me, lt_seq_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        self.lt_seq_me = lt_seq_me
        # pull in incidence draws
        draws = self.get_draws()
        # create new incidence for Eclampsia Adjusted for Live Births 3635
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create new prevalence for for Eclampsia Adjusted for Live Births 3635
        duration = self.create_draws(0.00274, 0.00137, 0.00548)
        new_prev = self.mul_draws(new_inc, duration)
        self.output(new_prev, output_me, 5)
        # create long term sequela severity draws for data rich/data poor locs
        data_rich_sev = self.create_draws(0.065, 0.0606, 0.0694)
        data_poor_sev = self.create_draws(0.114, 0.108, 0.120)
        # create long term sequela, by multiplying by severity draws
        dr_inc, dp_inc = self.data_rich_data_poor(new_inc)
        dr_prev = self.mul_draws(dr_inc, data_rich_sev)
        dp_prev = self.mul_draws(dp_inc, data_poor_sev)
        lt_seq_prev = pd.concat([dr_prev, dp_prev])
        # output long term sequela for 3931
        self.output(lt_seq_prev, lt_seq_me, 5)


class Hypertension(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me, other_seq_me,
                 sev_seq_me, lt_seq_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        self.other_seq_me = other_seq_me
        self.sev_seq_me = sev_seq_me
        self.lt_seq_me = lt_seq_me
        # pull in incidence draws
        draws = self.get_draws()
        # create new incidence for maternal htn adj for live births
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create severity splits
        other_htn_prop = self.create_draws(0.98, 0.966, 0.9946)
        severe_preeclampsia_prop = self.create_draws(0.020, 0.0054, 0.034)
        longterm_prop = self.create_draws(0.62, 0.567, 0.673)
        # create durations
        other_htn_dur = self.create_draws(3 / 12, 2 / 12, 4 / 12)
        severe_preeclampsia_dur = self.create_draws(7 / 365, 5 / 365, 10 / 365)
        longterm_dur = self.create_draws(6 / 12, 3 / 12, 9 / 12)
        # squeeze proportions
        other_htn_prop, severe_preeclampsia_prop = (
            self.squeeze_severity_splits(
                other_htn_prop, severe_preeclampsia_prop))
        # multiply proportions and durations
        other_htn_prop_dur = other_htn_prop * other_htn_dur
        severe_preeclampsia_prop_dur = (severe_preeclampsia_prop *
                                        severe_preeclampsia_dur)
        longterm_prop_dur = longterm_prop * longterm_dur
        # create new incidence and prevalence for Other Htn 2625
        other_htn_inc = self.mul_draws(new_inc, other_htn_prop)
        other_htn_prev = self.mul_draws(new_inc, other_htn_prop_dur)
        self.output(other_htn_prev, other_seq_me, 5)
        self.output(other_htn_inc, other_seq_me, 6)
        # create new incidence and prevalence for Severe Preeclampsia 1542
        severe_preeclampsia_inc = self.mul_draws(new_inc,
                                                 severe_preeclampsia_prop)
        severe_preeclampsia_prev = self.mul_draws(new_inc,
                                                  severe_preeclampsia_prop_dur)
        self.output(severe_preeclampsia_inc, sev_seq_me, 6)
        self.output(severe_preeclampsia_prev, sev_seq_me, 5)
        # split severe preeclampsia into sub-sequala of long-term 3928
        longterm_inc = self.mul_draws(severe_preeclampsia_inc,
                                      longterm_prop)
        longterm_prev = self.mul_draws(severe_preeclampsia_inc,
                                       longterm_prop_dur)
        self.output(longterm_inc, lt_seq_me, 6)
        self.output(longterm_prev, lt_seq_me, 5)


class Obstruct(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        # get incidence draws
        draws = self.get_draws()
        # create new incidence
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create new prevalence
        duration = self.create_draws(0.0137, 0.0082, 0.0192)
        new_prev = self.mul_draws(new_inc, duration)
        self.output(new_prev, output_me, 5)


class Fistula(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me,
                 recto_seq_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        self.recto_seq_me = recto_seq_me
        k_cols, i_cols, d_cols = self.keep_cols()
        # get incidence draws
        inc = self.get_draws()
        inc = inc[k_cols]
        # get prevalence draws
        prev = self.get_draws(measure_id=5)
        prev = prev[k_cols]
        # create severity splits
        vesi_prop = self.create_draws(0.95, 0.90, 0.99)
        recto_prop = self.create_draws(0.05, 0.01, 0.1)
        # squeeze proportions
        vesi_prop, recto_prop = (
            self.squeeze_severity_splits(vesi_prop, recto_prop))
        # create vesicovaginal fistula incidence and prevalence
        vesi_prev = self.mul_draws(prev, vesi_prop)
        vesi_inc = self.mul_draws(inc, vesi_prop)
        self.output(vesi_prev, output_me, 5)
        self.output(vesi_inc, output_me, 6)
        # create rectovaginal fistula incidence and prevalence
        recto_prev = self.mul_draws(prev, recto_prop)
        recto_inc = self.mul_draws(inc, recto_prop)
        self.output(recto_prev, recto_seq_me, 5)
        self.output(recto_inc, recto_seq_me, 6)


class Sepsis(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me,
                 infertile_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        self.infertile_me = infertile_me
        k_cols, i_cols, d_cols = self.keep_cols()
        # get incidence draws
        draws = self.get_draws()
        # create new incidence
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create new prevalence
        duration = self.create_draws(0.01918, 0.0137, 0.0274)
        new_prev = self.mul_draws(new_inc, duration)
        self.output(new_prev, output_me, 5)
        # create incidence of infertility & output as input data for that model
        infertility_sev = self.create_draws(0.09, 0.077, 0.104)
        infert_inc = self.mul_draws(new_inc, infertility_sev)
        # get mean/upper/lower
        infert_inc.set_index(i_cols, inplace=True)
        infert_inc = infert_inc.transpose().describe(
            percentiles=[.025, .975]).transpose()[['mean', '2.5%', '97.5%']]
        infert_inc.rename(
            columns={'2.5%': 'lower', '97.5%': 'upper'}, inplace=True)
        infert_inc.index.rename(i_cols, inplace=True)
        infert_inc.reset_index(inplace=True)
        # get year_start, year_end
        infert_inc['year_start'] = infert_inc['year_id']
        infert_inc['year_end'] = infert_inc['year_id']
        # get age_start and age_end
        query = "SELECT age_group_id, age_group_name FROM shared.age_group"
        age_df = query_tools.query_2_df(query, engine=self.enginer.engines
                                        ['cod_prod'])
        age_df = age_df.query("age_group_id < 22")
        age_df = age_df[age_df.age_group_name.str.contains('to')]
        age_df['age_start'], age_df['age_end'] = zip(
            *age_df['age_group_name'].apply(lambda x: x.split(' to ', 1)))
        age_df['age_start'] = age_df['age_start'].astype(int)
        age_df['age_end'] = age_df['age_end'].astype(int)
        infert_inc = infert_inc.merge(age_df, on='age_group_id', how='left')
        # get location_name
        query = ('SELECT location_id, location_ascii_name AS location_name '
                 'FROM shared.location_hierarchy_history LEFT JOIN shared.'
                 'location USING(location_id) WHERE '
                 'location_set_version_id=(SELECT location_set_version_id '
                 'FROM shared.location_set_version WHERE location_set_id = 9 '
                 'and end_date IS NULL) AND most_detailed=1')
        loc_df = query_tools.query_2_df(query, engine=self.enginer.engines
                                        ['cod_prod'])
        infert_inc = infert_inc.merge(loc_df, on='location_id', how='inner')
        # get sex
        infert_inc['sex'] = infert_inc['sex_id'].map({2: 'Female'})
        infert_inc.drop(['year_id', 'sex_id', 'age_group_id',
                        'age_group_name'], axis=1, inplace=True)
        # add other necessary cols for the epi uploader
        infert_inc['modelable_entity_id'] = infertile_me
        query = ('SELECT modelable_entity_name FROM epi.modelable_entity '
                 'WHERE modelable_entity_id = %s' % infertile_me)
        infert_inc['modelable_entity_name'] = (query_tools.query_2_df(query,
                                               engine=self.enginer.engines
                                               ['epi_prod'])
                                               .ix[0, 'modelable_entity_name'])
        infert_inc['nid'] = 254237
        empty_cols = ['row_num', 'parent_id', 'input_type', 'underlying_nid',
                      'underlying_field_citation_value',
                      'field_citation_value', 'file_path', 'page_num',
                      'table_num', 'ihme_loc_id', 'smaller_site_unit',
                      'site_memo', 'age_demographer', 'standard_error',
                      'effective_sample_size', 'cases', 'sample_size',
                      'design_effect', 'measure_adjustment',
                      'recall_type_value', 'sampling_type', 'response_rate',
                      'case_name', 'case_definition', 'case_diagnostics',
                      'group', 'specificity', 'group_review', 'note_modeler',
                      'note_SR', 'extractor', 'data_sheet_filepath']
        for col in empty_cols:
            infert_inc['%s' % col] = np.nan
        infert_inc['sex_issue'] = 0
        infert_inc['year_issue'] = 0
        infert_inc['age_issue'] = 0
        infert_inc['measure'] = "incidence"
        infert_inc['measure_issue'] = 0
        infert_inc['representative_name'] = "Unknown"
        infert_inc['urbanicity_type'] = "Unknown"
        infert_inc['unit_type'] = "Person"
        infert_inc['unit_value_as_published'] = 1
        infert_inc['is_outlier'] = 0
        infert_inc['recall_type'] = "Point"
        infert_inc['uncertainty_type'] = "Confidence interval"
        infert_inc['uncertainty_type_value'] = 95
        infert_inc['source_type'] = "Mixed or estimation"
        self.output_for_epiuploader(infert_inc, infertile_me)


class SepsisOther(Base):
    def __init__(self, cluster_dir, year_id, input_me, output_me):
        Base.__init__(self, cluster_dir, year_id, input_me, output_me)
        # get incidence draws
        draws = self.get_draws()
        # create new incidence
        asfr = self.get_asfr()
        new_inc = self.get_new_incidence(draws, asfr)
        self.output(new_inc, output_me, 6)
        # create new prevalence
        duration = self.create_draws(0.082, 0.041, 0.123)
        new_prev = self.mul_draws(new_inc, duration)
        self.output(new_prev, output_me, 5)

if __name__ == "__main__":
    if len(sys.argv) < 6:
        raise Exception('''Need class_name, cluster_dir, year_id, input_ME, and
                            output_MEs as args''')
    class_name = sys.argv[1]
    cluster_dir = sys.argv[2]
    year = int(sys.argv[3])
    input_me = int(sys.argv[4])
    out_mes = sys.argv[5].split(';')
    print class_name, cluster_dir, year, input_me, out_mes
    if class_name == "Abortion":
        output_me = int(out_mes[0])
        go = Abortion(cluster_dir, year, input_me, output_me)
    elif class_name == "Hemorrhage":
        output_me, mod_seq_me, sev_seq_me = (int(out_mes[0]), int(out_mes[1]),
                                             int(out_mes[2]))
        go = Hemorrhage(cluster_dir, year, input_me, output_me, mod_seq_me,
                        sev_seq_me)
    elif class_name == "Eclampsia":
        output_me, lt_seq_me = int(out_mes[0]), int(out_mes[1])
        go = Eclampsia(cluster_dir, year, input_me, output_me, lt_seq_me)
    elif class_name == "Hypertension":
        output_me, other_seq_me, sev_seq_me, lt_seq_me = (int(out_mes[0]),
                                                          int(out_mes[1]),
                                                          int(out_mes[2]),
                                                          int(out_mes[3]))
        go = Hypertension(cluster_dir, year, input_me, output_me,
                          other_seq_me, sev_seq_me, lt_seq_me)
    elif class_name == "Obstruct":
        output_me = int(out_mes[0])
        go = Obstruct(cluster_dir, year, input_me, output_me)
    elif class_name == "Fistula":
        output_me, recto_seq_me = int(out_mes[0]), int(out_mes[1])
        go = Fistula(cluster_dir, year, input_me, output_me, recto_seq_me)
    elif class_name == "Sepsis":
        output_me, infertile_me = int(out_mes[0]), int(out_mes[1])
        go = Sepsis(cluster_dir, year, input_me, output_me, infertile_me)
    elif class_name == "SepsisOther":
        output_me = int(out_mes[0])
        go = SepsisOther(cluster_dir, year, input_me, output_me)
    else:
        raise ValueError('''Must be Abortion, Hemorrhage, Eclampsia,
                 Hypertension, Obstruct, Fistula, Sepsis, or SepsisOther''')
