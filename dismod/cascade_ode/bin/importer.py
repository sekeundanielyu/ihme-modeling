#!bin/env python

# mapping from parameter_type_id to a short name for the prior_type
# (missing from data-base).

inf = float('inf')

likelihood_map = {
    1: 'gaussian',
    2: 'laplace',
    3: 'log_gaussian',
    4: 'log_laplace',
    5: 'log_gaussian' }

prior_id2name = {
    1: 'value'         ,
    2  : 'slope'         ,
    5  : 'study_xcov'    ,
    6  : 'study_zcov'    ,
    7  : 'country_xcov'  ,
    8  : 'asdr_xcov'     ,
    9  : 'location'      ,
    10 : 'smoothness'    ,
    11 : 'zeta_one'      ,
    12 : 'rate_offset'   ,
    13 : 'data_offset'   ,
    14 : 'gamma_subreg ' ,
    15 : 'gamma_region'  ,
    16 : 'gamma_super'   ,
    17 : 'exclude_data'  ,
    18 : 'exclude_prior'
}

integrand_rate_map = {
    'incidence' : 'iota' ,
    'remission' : 'rho'  ,
    'mtexcess'  : 'chi'  ,
    'mtother'   : 'omega'
}

integrand_pred = [
    'incidence',
    'remission',
    'prevalence',
    'mtexcess',
    'mtall',
    'relrisk',
    'mtstandard',
    'mtwith',
    'mtspecific',
    'mtother'
]

# ----------------------------------------------------------------------------

import json
import sys
import math
import os
import pandas as pd
import sqlalchemy
import numpy as np
from hierarchies import loctree

# Set default file mask to readable-for all users
os.umask(0o0002)

# Get this filepath
this_path = os.path.dirname(os.path.abspath(__file__))

# Get configuration options
if os.path.isfile(os.path.join(this_path, "../config.local")):
    settings = json.load(open(os.path.join(this_path, "../config.local")))
else:
    settings = json.load(open(os.path.join(this_path, "../config.default")))
mysql_server = {
    'epi': settings['epi_conn_str'],
    'cod': settings['cod_conn_str'] }

def gen_locmap(location_set_version_id):

    lt = loctree.construct(location_set_version_id)
    lmap = lt.flatten()
    lmap.drop('level_0', axis=1, inplace=True)
    lmap.rename(columns={
        'level_1':'super',
        'level_2':'region',
        'level_3':'subreg',
        'level_4':'atom',
        'leaf_node':'location_id'}, inplace=True)
    lmap = lmap.append(lmap.ix[lmap.atom.notnull(), ['super','region','subreg']].drop_duplicates())
    lmap.ix[lmap.location_id.isnull(), 'location_id'] = lmap.ix[lmap.location_id.isnull(), 'subreg']
    lmap = lmap.append(lmap[['super','region']].drop_duplicates())
    lmap.ix[lmap.location_id.isnull(), 'location_id'] = lmap.ix[lmap.location_id.isnull(), 'region']
    lmap = lmap.append(lmap[['super']].drop_duplicates())
    lmap.ix[lmap.location_id.isnull(), 'location_id'] = lmap.ix[lmap.location_id.isnull(), 'super']

    for c in ['atom','subreg','region','super']:
        lmap[c] = lmap[c].apply(lambda x: "{:.1f}".format(x))
        lmap.ix[lmap[c]=='nan', c] = 'none'

    return lmap


class Importer(object):

    def __init__(self, model_version_id):
        self.mvid = model_version_id
        self.model_params = self.get_model_parameters()
        self.model_version_meta = Importer.get_model_version(self.mvid)
        self.covariate_data = pd.DataFrame()
        if self.model_version_meta.integrand_only.isnull().any():
            self.single_param = None
            self.integrand_pred = [
                'incidence',
                'remission',
                'prevalence',
                'mtexcess',
                'mtall',
                'relrisk',
                'mtstandard',
                'mtwith',
                'mtspecific',
                'mtother'
            ]

        else:
            self.single_param = self.model_version_meta.integrand_only.values[0]
            self.model_params['measure'] = self.model_params.measure.replace({
                self.single_param: 'mtother'})
            self.integrand_pred = ['mtother']

        self.age_mesh = self.get_age_mesh()
        self.data = self.get_input_data()

        # Get mtall data for multiple-param models
        if self.single_param is None:
            self.mtall = self.get_mtall_data()
        else:
            self.mtall = pd.DataFrame()

        # Get mtspecific data if specified
        if self.model_version_meta.add_csmr_cause.notnull().any():
            mpm = self.model_params
            exclude_params = mpm.ix[mpm.parameter_type_id==17, 'measure']
            if 'mtspecific' not in list(exclude_params):
                mtspec_data = self.get_mtspec_data()
                self.data = self.data.append(mtspec_data)

        self.ccov_means = {}

    @staticmethod
    def execute_select(query, db='epi'):
        conn_string = mysql_server[db]
        engine = sqlalchemy.create_engine(conn_string)
        conn = engine.connect()
        df = pd.read_sql(query, conn.connection)
        conn.close()
        return df

    def recalc_SE(self, meas_value, standard_error, sample_size, lower_ci, upper_ci) :
        # First prefer standard deviation
        if standard_error > 0.0 :
            return standard_error

        # next use sample_size
        if sample_size > 0.0 :
            counts = meas_value * sample_size
            # When the number of counts is greater than or equal 5, use
            # standard deviation corresponding to counts is Possion distributed
            # Note that when counts = 5.0 meas_value is 5.0 / sample_size
            std_5 = math.sqrt( (5.0 / sample_size) / sample_size )
            if counts >= 5.0 :
                return math.sqrt( meas_value / sample_size )
            # Standard deviation for binomial with measure zero is about
            std_0 = 1.0 / sample_size
            # Linear interpolate between value std_5 at counts equal 5
            # and std_0 at counts equal 0
            return  ((5.0 - counts) * std_0 + counts * std_5) / 5.0

        # Last choice, interpret 95% confidence limits using normal distribution
        if upper_ci != None and lower_ci != None :
            return (upper_ci - lower_ci) / (2. * 1.96);

        raise ValueError("Insufficient information to calculate standard error")

    def get_mtall_data(self):
        """ Return all cause mortality for all locations formatted for
        appending to data for other integrands """

        lmap = gen_locmap(self.model_version_meta.location_set_version_id.values[0])
        mortality_age_grid = ",".join([ str(i) for i in range(2,22)])
        mo_vid = self.model_version_meta.csmr_mortality_output_version_id.values[0]

        query = """
            SELECT mean_pop, mean_env_whiv as mean_env,
                upper_env_whiv as upper_env,
                lower_env_whiv as lower_env,
                location_id, year_id as time_lower, o.sex_id as x_sex,
                o.age_group_id, a.age_group_years_start AS age_lower,
                a.age_group_years_end AS age_upper, s.sex
            FROM mortality.output o
            FORCE INDEX(idx_output)
            STRAIGHT_JOIN shared.sex s ON (s.sex_id = o.sex_id)
            STRAIGHT_JOIN shared.age_group a ON (a.age_group_id = o.age_group_id)
            WHERE o.output_version_id = %s
            AND o.sex_id IN (1,2)
            AND o.year_id IN (1985, 1990, 1995, 2000, 2005, 2010, 2015)
            AND o.age_group_id IN (%s)
        """ % (mo_vid, mortality_age_grid)

        df = Importer.execute_select(query, 'cod')
        df.ix[df.age_lower==80, "age_upper"] = 100

        # Calculate values
        df['meas_value'] = df['mean_env']/df['mean_pop']
        df['meas_stdev'] = (df.upper_env-df.lower_env) / (2.0*1.96*df.mean_pop)
        #df['meas_stdev'] = inf
        df.drop(['mean_env','lower_env','upper_env','mean_pop'], axis=1, inplace=True)

        # Format as strings...
        df['meas_value'] = df.meas_value.apply(lambda x: '{:.5g}'.format(x))
        df['meas_stdev'] = df.meas_stdev.apply(lambda x: '{:.5g}'.format(x))
        df['age_lower'] = df.age_lower.apply(lambda x: '{:.3g}'.format(x))
        df['age_upper'] = df.age_upper.apply(lambda x: '{:.3g}'.format(x))

        # Reformat age values
        df['x_sex'] = df.x_sex.replace({1:0.5, 2:-0.5, 3:0.0})

        df['time_upper'] = df['time_lower'] + 1
        df['year_id'] = df['time_lower']
        df['hold_out'] = 0
        df['x_local'] = 1
        df['study_covariates'] = ''
        df['integrand'] = 'mtall'
        df['data_like'] = likelihood_map[
                self.model_version_meta.data_likelihood.values[0]]

        df = df.merge(lmap, on='location_id')
        df[['atom','subreg','region','super']] = df[['atom','subreg','region','super']].astype('str')

        return df

    def get_mtspec_data(self):
        """ Return all cause mortality for all locations formatted for
        appending to data for other integrands """

        lmap = gen_locmap(self.model_version_meta.location_set_version_id.values[0])
        csmr_cause_id = self.model_version_meta.add_csmr_cause.values[0]
        mo_vid = self.model_version_meta.csmr_mortality_output_version_id.values[0]
        cc_vid = self.model_version_meta.csmr_cod_output_version_id.values[0]

        query = """
            SELECT o.location_id, o.year_id as time_lower, o.sex_id as x_sex, mean_death/pop_scaled as meas_value,
                lower_death/pop_scaled as meas_lower,
                upper_death/pop_scaled as meas_upper,
                o.age_group_id,
                age_group_years_start AS age_lower,
                age_group_years_end AS age_upper
            FROM cod.output as o
            JOIN shared.age_group USING(age_group_id)
            JOIN (
                SELECT location_id, year_id, sex_id, age_group_id, pop_scaled
                FROM mortality.output
                WHERE output_version_id = %s) as p
                    ON o.location_id=p.location_id
                    AND o.year_id=p.year_id
                    AND o.age_group_id=p.age_group_id
                    AND o.sex_id=p.sex_id
            WHERE output_version_id = %s
            AND o.age_group_id BETWEEN 2 AND 21
            AND o.year_id IN (1985, 1990, 1995, 2000, 2005, 2010, 2015)
            AND o.sex_id IN (1,2)
            AND cause_id=%s
        """ % (mo_vid, cc_vid, csmr_cause_id)

        print 'Getting mtspecific data....'
        df = Importer.execute_select(query, 'cod')

        # Calculate values
        df['meas_stdev'] = (df.meas_upper-df.meas_lower) / (2.0*1.96)
        df['meas_stdev'] = df.meas_stdev.replace({0: 1e-9})
        df.drop(['meas_lower','meas_upper'], axis=1, inplace=True)

        # Format as strings...
        df['meas_value'] = df.meas_value.apply(lambda x: '{:.5g}'.format(x))
        df['meas_stdev'] = df.meas_stdev.apply(lambda x: '{:.5g}'.format(x))
        df['age_lower'] = df.age_lower.apply(lambda x: '{:.3g}'.format(x))
        df['age_upper'] = df.age_upper.fillna(100)
        df['age_upper'] = df.age_upper.apply(lambda x: '{:.3g}'.format(x))

        # Reformat age values
        df['x_sex'] = df.x_sex.replace({1:0.5, 2:-0.5, 3:0.0})
        df['time_upper'] = df['time_lower'] + 1
        df['year_id'] = df['time_lower']
        df['hold_out'] = 0
        df['x_local'] = 1
        df['study_covariates'] = ''
        df['integrand'] = 'mtspecific'
        df['data_like'] = likelihood_map[
                self.model_version_meta.data_likelihood.values[0]]

        df = df.merge(lmap, on='location_id')
        df[['atom','subreg','region','super']] = df[['atom','subreg','region','super']].astype('str')

        return df

    def attach_study_covariates(self, df):
        # Get study covariates
        sclists = df.study_covariates.str.strip()
        sclists = sclists.apply(lambda x: str(x).split(" "))

        scovs = reduce(lambda x,y: x.union(set(y)), sclists, set())
        try:
            scovs.remove('None')
        except:
            pass
        try:
            scovs.remove('')
        except:
            pass
        scovs = list(scovs)
        scov_str = ",".join(scovs)

        # Retrieve study covariate names and ids
        query = """
            SELECT study_covariate_id, study_covariate
            FROM epi.study_covariate
            WHERE study_covariate_id IN (%s) """ % (scov_str)

        if len(scovs)>0:
            scov_names = Importer.execute_select(query)

            for i, row in scov_names.iterrows():
                v_zeros_ones = (
                    [ 1 if str(row["study_covariate_id"]) in r else 0 for r in sclists ])
                df['x_s_'+row["study_covariate"]] = v_zeros_ones

        df.drop('study_covariates', axis=1, inplace=True)

    def get_input_data(self):
        lmap = gen_locmap(self.model_version_meta.location_set_version_id.values[0])

        query = """
            SELECT d.input_data_key as data_id, nid, location_id, m.measure as integrand, mean, year_start, year_end, age_start, age_end,
                lower, upper, sample_size, standard_error,
                outlier_type_id, sex_id, trim(GROUP_CONCAT(
                    case when scid.study_covariate_value = 1 then scid.study_covariate_id
                    else '' end SEPARATOR ' ')) AS study_covariates
            FROM
                epi.model_version mv
            INNER JOIN
                epi.input_data_audit d ON (mv.modelable_entity_id = d.modelable_entity_id)
            LEFT JOIN
                epi.study_covariate_input_data scid ON (d.input_data_id = scid.input_data_id)
            LEFT JOIN
                epi.input_data_relation idr ON (d.input_data_id = idr.parent_id)
            LEFT JOIN
                shared.measure m ON (d.measure_id = m.measure_id)
            WHERE
                mv.model_version_id = %s
                AND d.last_updated_action != 'DELETE'
                AND d.outlier_type_id = 0
                AND d.audit_end IS NULL
                        AND idr.parent_id IS NULL
            GROUP BY d.input_data_key""" % (self.mvid)

        df = Importer.execute_select(query)

        # Rename columns to dismod_ode file nomenclature
        renames = {
            'data_id'        : 'a_data_id',
            'mean'           : 'meas_value',
            'year_start'     : 'time_lower',
            'year_end'       : 'time_upper',
            'age_start'      : 'age_lower',
            'age_end'        : 'age_upper',
            'standard_error' : 'meas_stdev',
            'sex_id'         : 'x_sex' }
        df.rename(columns=renames, inplace=True)
        df['x_sex'] = df.x_sex.replace({1:0.5, 2:-0.5, 3:0.0})
        df = df[df.integrand!='cfr']

        df['meas_stdev'] = df.apply(lambda x: self.recalc_SE(
            x['meas_value'], x['meas_stdev'], x['sample_size'],
            x['lower'], x['upper']), axis=1)

        df.drop(['lower','upper','sample_size','outlier_type_id'], axis=1, inplace=True)

        # Use the mid-year as the year_id for merging country covariates
        df['year_id'] = ((df.time_upper+df.time_lower)/2).astype('int')
        df['x_local'] = 1
        df['hold_out'] = 0
        df['data_like'] = likelihood_map[
                self.model_version_meta.data_likelihood.values[0]]

        df = df.merge(lmap, on='location_id')
        df[['atom','subreg','region','super']] = df[['atom','subreg','region','super']].astype('str')
        self.attach_study_covariates(df)

        # Exclude data if requested
        mpm = self.model_params
        exclude_params = mpm.ix[mpm.parameter_type_id==17, 'measure']
        df = df[~df.integrand.isin(exclude_params)]

        # Scope to single parameter if requested
        if self.single_param is not None:
            df = df[df.integrand==self.single_param]
            df['integrand'] = df.integrand.replace(
                {self.single_param: 'mtother'})
        else:
            df = df[df.integrand.isin(integrand_pred)]

        df.ix[(df.age_lower>=1) & (df.age_upper<100), 'age_upper'] = df.ix[
                (df.age_lower>=1) & (df.age_upper<100), 'age_upper'] + 1

        return df

    def measured_integrands(self):
        return list(self.data.integrand.drop_duplicates())

    def measured_locations(self):
        data = self.data
        if self.single_param is None:
            data = data[data.integrand!='mtall']
        mls = {}
        for ltype in ['atom', 'subreg', 'region', 'super']:
            mls[ltype] = list(data.ix[data[ltype]!='none', ltype].drop_duplicates())
        return mls

    @staticmethod
    def get_model_version(mvid):
        query = """
            SELECT * FROM epi.model_version
            JOIN epi.modelable_entity USING(modelable_entity_id)
            JOIN epi.integration_type it ON integrate_method=it.integration_type_id
            LEFT JOIN (SELECT measure_id, measure as integrand_only
                    FROM shared.measure) m ON model_version.measure_only=m.measure_id
            WHERE model_version_id=%s """ % (mvid)
        df = Importer.execute_select(query)
        return df

    def get_model_parameters(self):
        query = """
            SELECT * FROM epi.model_parameter
            LEFT JOIN shared.measure USING(measure_id)
            LEFT JOIN epi.parameter_type USING(parameter_type_id)
            LEFT JOIN epi.study_covariate USING(study_covariate_id)
            WHERE model_version_id=%s """ % (self.mvid)
        df = Importer.execute_select(query)
        df.drop(['date_inserted', 'inserted_by', 'last_updated', 'last_updated_by', 'last_updated_action'], axis=1, inplace=True)

        df['mean'] = df['mean'].fillna((df.upper+df.lower)/2.0)
        df['std'] = df['std'].fillna(inf)

        return df

    def get_integrand_data(self, input_data, integrand):
        return input_data[input_data.integrand==integrand]

    def assign_eta(self):
        """ Assign eta based on some logical rules... """

        model_param_meta = self.model_params
        model_version_meta = self.model_version_meta
        data = self.data.append(self.mtall)

        db_etas = model_param_meta[model_param_meta.parameter_type_id==13]

        eta_priors = []
        for integrand in self.integrand_pred:
            if integrand in db_etas.measure.values:
                # check if eta has a value for this integrand in
                # epi.model_parameters
                eta = db_etas.ix[
                        db_etas.measure == integrand, "mean"].values[0]
            elif integrand in data.integrand.values:
                # otherwise check if there is any data for this integrand
                if len(data[
                        (data.integrand == integrand) &
                        (data.meas_value != 0)]) > 0:
                    eta = 1e-2 * data.ix[(
                        (data.integrand == integrand) &
                        (data.meas_value != 0)), "meas_value"].median()
                else:
                    eta = 1e-5
            else:
                # otherwise use a default value
                eta = 1e-5

            eta = "{:.5g}".format(eta)
            eta_priors.append(eta)

        eta_df = pd.DataFrame({'integrand':self.integrand_pred, 'eta':eta_priors})
        return eta_df

    def get_age_mesh(self, use_default=False):
        # parent age grid
        if use_default:
            age_group_ids = range(2,21) + range(30,34)
            age_group_ids = [ str(a) for a in age_group_ids ]
            age_group_id_str = ",".join(age_group_ids)
            query = """
                SELECT * FROM shared.age_group
                WHERE age_group_id IN (%s) """ % (age_group_id_str)
            age_mesh = Importer.execute_select(query)
            age_mesh.rename(columns={
                'age_group_years_start': 'age_start',
                'age_group_years_end': 'age_end'}, inplace=True)
            age_mesh = age_mesh.sort('age_start')
            age_mesh = (age_mesh['age_start']+age_mesh['age_end'])/2.0
        else:
            age_mesh = self.model_version_meta.age_mesh
            age_mesh = age_mesh.values[0].split(" ")
        age_mesh = [ "{:.5g}".format(float(a)) for a in age_mesh ]

        return age_mesh

    def get_integrand_bounds(self):
        model_version_meta = self.model_version_meta
        mpm = self.model_params

        # ETA
        integrand_df                     = self.assign_eta()
        integrand_df['min_cv_world2sup'] = model_version_meta['cv_global'].values[0]
        integrand_df['min_cv_sup2reg']   = model_version_meta['cv_super'].values[0]
        integrand_df['min_cv_reg2sub']   = model_version_meta['cv_region'].values[0]

        if 'cv_subreg' in model_version_meta.columns:
            integrand_df['min_cv_sub2atom'] = model_version_meta['cv_subreg'].values[0]
        else:
            integrand_df['min_cv_sub2atom'] = model_version_meta['cv_region'].values[0]

        age_mesh = self.get_age_mesh(use_default=True)
        age_mesh = " ".join(age_mesh)

        lvl_map = {
                2:'min_cv_world2sup',
                3:'min_cv_sup2reg',
                4:'min_cv_reg2sub',
                5:'min_cv_sub2atom'}
        for lvl in range(2,6):
            min_cv_override = mpm[(mpm.parameter_type_id==19) &
                    (mpm.cascade_level_id==lvl)]
            if len(min_cv_override)>0:
                for i, row in min_cv_override.iterrows():
                    integrand_df.ix[integrand_df.integrand==row['measure'],
                        lvl_map[lvl]] = row['mean']

        integrand_df = integrand_df.replace({0: 0.01})
        integrand_df['parent_age_grid'] = age_mesh

        return integrand_df

    def attach_country_covariate(self, covariate_id, asdr_cause_id=None):
        if asdr_cause_id is not None:
            cc_vid = self.model_version_meta.csmr_cod_output_version_id.values[0]
            query = """
                SELECT o.location_id, o.year_id, o.age_group_id, o.sex_id,
                    mean_death as mean_value
                FROM cod.output as o
                JOIN shared.age_group USING(age_group_id)
                WHERE output_version_id=%s
                AND o.age_group_id=27
                AND o.sex_id IN (1,2)
                AND cause_id=%s""" % (cc_vid, asdr_cause_id)

            covname = 'lnasdr_%s' % asdr_cause_id
            covdata = Importer.execute_select(query, 'cod')
            covdata['mean_value'] = np.log(covdata.mean_value)
            colname = 'raw_c_%s' % covname
            cnt_colname = 'x_c_%s' % covname
            print colname
        else:
            covnq = """
                SELECT covariate_name_short FROM shared.covariate
                WHERE covariate_id=%s """ % (covariate_id)
            covname = Importer.execute_select(covnq).values[0][0]
            colname = 'raw_c_%s' % covname
            cnt_colname = 'x_c_%s' % covname
            print colname
            dataq = """
                SELECT location_id, year_id, age_group_id, sex_id, mean_value
                FROM covariate.model
                JOIN shared.location USING(location_id)
                JOIN covariate.model_version USING(model_version_id)
                JOIN covariate.data_version USING(data_version_id)
                WHERE is_best=1 AND covariate_id=%s """ % (covariate_id)
            covdata = Importer.execute_select(dataq, 'cod')

            transform_type_id = self.model_params[
                self.model_params.country_covariate_id==covariate_id][
                        'transform_type_id'].values[0]

            if transform_type_id==1:
                covdata['mean_value'] = np.log(covdata.mean_value)
            elif transform_type_id==2:
                covdata['mean_value'] = np.log(covdata.mean_value/(1-covdata.mean_value))
            elif transform_type_id==3:
                covdata['mean_value'] = covdata.mean_value**2
            elif transform_type_id==4:
                covdata['mean_value'] = np.sqrt(covdata.mean_value)
            elif transform_type_id==5:
                covdata['mean_value'] = covdata.mean_value*1000

        lsvid = self.model_version_meta.location_set_version_id.values[0]
        lt = loctree.construct(lsvid)
        leaves = [l.id for l in lt.leaves()]
        covdata = covdata[covdata.location_id.isin(leaves)]

        if 3 not in covdata.sex_id.unique():
            bothdata = covdata[['location_id','year_id','mean_value']].groupby(
                ['location_id','year_id']).mean().reset_index()
            bothdata['sex_id'] = 3
            covdata = covdata.append(bothdata)
        for s in [1,2]:
            if s not in covdata.sex_id.unique():
                sexdata = covdata[covdata.sex_id==3]
                sexdata['sex_id'] = s
                covdata = covdata.append(sexdata)

        covdata.rename(columns={'mean_value':colname}, inplace=True)
        covdata['x_sex'] = covdata.sex_id.replace({
            1: 0.5, 2: -0.5, 3: 0})
        covdata = covdata[['location_id','year_id','x_sex',colname]]

        # Collapse to location-year-sex level (simple averaging)
        covdata = covdata.groupby(['location_id', 'year_id', 'x_sex'],
                as_index=False).mean()
        self.data = self.data.merge(covdata,
            on=['location_id','year_id','x_sex'],
            how='left')
        if len(self.mtall)>0:
            self.mtall = self.mtall.merge(covdata,
                on=['location_id','year_id','x_sex'],
                how='left')

        if len(self.covariate_data)==0:
            self.covariate_data = covdata
        else:
            self.covariate_data = self.covariate_data.merge(covdata,
                on=['location_id','year_id','x_sex'])

        if len(self.mtall)>0:
            covmean = (self.data[colname].append(self.mtall[colname])).mean()
        else:
            covmean = self.data[colname].mean()
        self.ccov_means[covname] = covmean
        #self.data[cnt_colname] = self.data[colname] - covmean
        #self.mtall[cnt_colname] = self.mtall[colname] - covmean

        return covname, covdata

    def get_effect_priors(self):
        """
        ----- UNMEASURED INTEGRAND DEFAULTS ----
        For "unmeasured" integrands (i.e. integrands where there is no
        data), create a random effect at every location level (subreg,
        region, super) with a gamma prior:
asd            defaults = {
                'integrand' : <<missing_integrand_name>>,
                'effect'    : 'gamma',
                'name'      : <<location_level>>,
                'lower'     : 1.0,
                'upper'     : 1.0,
                'mean'      : 1.0,
                'std'       : inf }
        ----------------------------------------

        ----- MEASURED INTEGRAND DEFAULTS ------
        For gamma (effect) priors on location (name), pull from
        model_parameters table where possible (parameter_type_ids 14,15,16).
        Otherwise, use the following gamma defaults for all measured
        integrands:
            defaults = {
                'integrand' : <<measured_integrand_name>>,
                'effec'    : 'gamma',
                'name'      : <<location_level>>,
                'lower'     : 1.0,
                'upper'     : 1.0,
                'mean'      : 1.0,
                'std'       : inf }

        For location random effect priors, which only apply to the
        locations in the dataset (and their respective parent
        locations), use the following defaults when not specified in the
        database:
            defaults = {
                'integrand' : <<measured_integrand_name not mtall>>,
                'effect'    : <<location level (super, region, or subreg)>>,
                'name'      : <<location_name>>,
                'lower'     : -2,
                'upper'     : 2,
                'mean'      : 0,
                'std'       : 1 }

        For beta sex prior, which applies to all measured integrands
        except for mtspecific, use the following defaults:
            defaults = {
                'integrand' : <<measured_integrand_name not mtspecific>>
                'effect'    : 'beta'
                'name'      : 'x_sex'
                'lower'     : -2.0
                'upper'     : 2.0
                'mean'      : 0.0
                'std'       : inf }

        For zeta prior, if not set in the model_parameters table, use
        the following defaults:
            defaults = {
                'integrand' : <<measured_integrand>>
                'effect'    : 'zeta'
                'name'      : 'a_local'
                'lower'     : 0.0
                'upper'     : 0.5
                'mean'      : 0.0
                'std'       : inf }

        For other beta priors (study covariates, country covariates,
        asdr covariates), there are no defaults. Use what is
        listed in the DB. Note that study covariates can also be
        zeta priors (in which case they are listed as study_zcov, as
        opposed to study_xcov)
        """

        mpm = self.model_params
        mis = self.measured_integrands()
        if self.single_param is None:
            try:
                mis.remove('mtall')
            except:
                print 'All cause mortality no longer part of the data file?'
            try:
                mis.remove('mtother')
            except:
                print 'mtother in the effects file causing problems?'
        else:
            mis = ['mtother']
        mlsets = self.measured_locations()

        #####################################################
        ## DEFAULTS
        #####################################################
        # Set location gamma defaults
        ep = []
        for integrand in self.integrand_pred:
            for loc_lvl in ['super','region','subreg']:
                defaults = {
                    'integrand' : integrand,
                    'effect'    : 'gamma',
                    'name'      : loc_lvl,
                    'lower'     : 1.0,
                    'upper'     : 1.0,
                    'mean'      : 1.0,
                    'std'       : inf }
                ep.append(defaults)

        # Location random effects
        for integrand in self.integrand_pred:
            for loc_lvl, mls in mlsets.iteritems():
                if loc_lvl=='atom':
                    pass
                else:
                    for n in ['none','cycle']:
                        cyc_none = {
                            'integrand' : integrand,
                            'effect'    : loc_lvl,
                            'name'      : n,
                            'lower'     : 0,
                            'upper'     : 0,
                            'mean'      : 0,
                            'std'       : inf}
                        ep.append(cyc_none)
                    if integrand in self.integrand_pred:
                        for ml in mls:
                            if ((self.model_version_meta['add_csmr_cause'].isnull().values[0]) &
                                (integrand=='mtspecific') &
                                (loc_lvl!='super')):
                                defaults = {
                                    'integrand' : integrand,
                                    'effect'    : loc_lvl,
                                    'name'      : ml,
                                    'lower'     : 0,
                                    'upper'     : 0,
                                    'mean'      : 0,
                                    'std'       : inf }
                            else:
                                defaults = {
                                    'integrand' : integrand,
                                    'effect'    : loc_lvl,
                                    'name'      : ml,
                                    'lower'     : -2,
                                    'upper'     : 2,
                                    'mean'      : 0,
                                    'std'       : 1 }
                            ep.append(defaults)

        # Beta sex priors
        mis_no_mtspec = list(set(mis)-set('mtspecific'))
        print mis_no_mtspec
        for integrand in self.integrand_pred:
            defaults = {
                'integrand' : integrand,
                'effect'    : 'beta',
                'name'      : 'x_sex',
                'lower'     : -2.0,
                'upper'     : 2.0,
                'mean'      : 0.0,
                'std'       : inf }
            ep.append(defaults)

        # Zeta priors
        for integrand in mis:
            defaults = {
                'integrand' : integrand,
                'effect'    : 'zeta',
                'name'      : 'x_local',
                'lower'     : 0.0,
                'upper'     : 0.5,
                'mean'      : 0.0,
                'std'       : inf }
            ep.append(defaults)

        #####################################################
        ## DB SETTINGS
        #####################################################
        # Apply other priors as specified in the database
        """
        1   Value prior
        2   Slope prior
        5   Study-level covariate fixed effect on integrand value (x-cov)
        6   Study-level covariate fixed effect on integrand variance (z-cov)
        7   Country-level covariate fixed effect
        8   ln-ASDR covariate fixed effect
        9   Location random effect
        10  Smoothness (xi)
        11  Heterogeneity (zeta1)
        12  Offset in the log normal transformation of rate smoothing (kappa)
        13  Offset in the log normal transformation of data fitting (eta)
        14  Multiplier of standard deviation for country random effects (gamma)
        15  Multiplier of standard deviation for region random effects (gamma)
        16  Multiplier of standard deviation for super region random effects (gamma)
        17  Exclude data for parameter
        18  Exclude prior data
        19  Min CV by integrand
        """

        # Country covariates
        ccovs = mpm[mpm.parameter_type_id==7]
        ccov_ids = list(pd.unique(ccovs.country_covariate_id))
        asdr_cause_ids = []
        if 8 in mpm.parameter_type_id.unique():
            for asdr_cause_id in self.model_params[
                    self.model_params.parameter_type_id==8]['asdr_cause'].unique():
                asdr_cause_ids.append(asdr_cause_id)
            ccovs = ccovs.append(mpm[mpm.parameter_type_id==8])

        for ccov_id in ccov_ids:
            ccov_name, ccov_data = self.attach_country_covariate(ccov_id)

            for i, row in ccovs[(ccovs.country_covariate_id==ccov_id)].iterrows():
                integrand = row['measure']
                if integrand in self.integrand_pred:
                    ccov = {
                        'integrand' : integrand,
                        'effect'    : 'beta',
                        'name'      : 'x_c_'+ccov_name,
                        'lower'     : row['lower'],
                        'upper'     : row['upper'],
                        'mean'      : row['mean'],
                        'std'       : inf }
                    ep.append(ccov)

                print ccov_name

        for asdr_cause_id in asdr_cause_ids:
            ccov_name, ccov_data = self.attach_country_covariate(-1, asdr_cause_id)

            for i, row in ccovs[(ccovs.asdr_cause==asdr_cause_id)].iterrows():
                integrand = row['measure']
                if integrand in self.integrand_pred:
                    ccov = {
                        'integrand' : integrand,
                        'effect'    : 'beta',
                        'name'      : 'x_c_'+ccov_name,
                        'lower'     : row['lower'],
                        'upper'     : row['upper'],
                        'mean'      : row['mean'],
                        'std'       : inf }
                    ep.append(ccov)

                print ccov_name

        # Study xcovs
        xcovs = mpm[mpm.parameter_type_id==5]
        xcovs['mean'] = xcovs['mean'].fillna((xcovs.lower+xcovs.upper)/2.)
        if len(xcovs)>0:
            for i, row in xcovs.iterrows():
                integrand = row['measure']
                if integrand in self.integrand_pred:
                    name = 'x_s_%s' % (row['study_covariate'])
                    xcov = {
                        'integrand' : integrand,
                        'effect'    : 'beta',
                        'lower'     : row['lower'],
                        'upper'     : row['upper'],
                        'mean'      : row['mean'],
                        'std'       : inf }
                    if name == 'x_s_sex':
                        xcov['name'] = 'x_sex'
                        ep = [i
                              if not (
                                  i['name'] == 'x_sex'
                                  and i['effect'] == 'beta'
                                  and i['integrand'] == integrand)
                              else xcov for i in ep]
                    else:
                        xcov['name'] = name
                        ep.append(xcov)

                    if name not in self.data.columns:
                        self.data[name] = 0

        # Study zcovs
        zcovs = mpm[mpm.parameter_type_id==6]
        zcovs['mean'] = zcovs['mean'].fillna((zcovs.lower+zcovs.upper)/2.)
        if len(zcovs)>0:
            for i, row in zcovs.iterrows():
                integrand = row['measure']
                if integrand in self.integrand_pred:
                    integrand = row['measure']
                    name = 'x_s_%s' % (row['study_covariate'])
                    zcov = {
                        'integrand' : integrand,
                        'effect'    : 'zeta',
                        'name'      : name,
                        'lower'     : row['lower'],
                        'upper'     : row['upper'],
                        'mean'      : row['mean'],
                        'std'       : inf }
                    if name == 'x_s_sex':
                        zcov['name'] = 'x_sex'
                    else:
                        zcov['name'] = name
                    ep.append(zcov)

                    if name not in self.data.columns:
                        self.data[name] = 0

        ep = pd.DataFrame(ep)
        self.study_covariates = list(self.data.filter(like='x_s_').columns)

        # Override location random effects
        loc_res = mpm[mpm.parameter_type_id==9]
        loc_res['location_id'] = loc_res.location_id.astype('float')
        for i, row in loc_res.iterrows():
            integrand = row['measure']
            conditions = (
                    (ep.integrand==integrand) &
                    (~ep.name.isin(['none','cycle'])) &
                    (ep.effect.isin(['subreg','region','super'])))
            if math.isnan(row['location_id']):
                this_conditions = conditions
            else:
                location_id = "{:.1f}".format(int(row['location_id']))
                this_conditions = conditions & (ep.name==location_id)
            ep.ix[this_conditions, "mean"] = row['mean']
            ep.ix[this_conditions, "lower"] = row['lower']
            ep.ix[this_conditions, "upper"] = row['upper']
            ep.ix[this_conditions, "std"] = row['std']

        # Override zeta
        zeta1s = mpm[mpm.parameter_type_id == 11]
        zeta1s['mean'] = zeta1s['mean'].fillna((zeta1s.lower+zeta1s.upper)/2.)
        for i, row in zeta1s.iterrows():
            integrand = row['measure']
            conditions = (ep.integrand == integrand) & (ep.name == 'x_local')
            ep.ix[conditions, 'mean'] = row['mean']
            ep.ix[conditions, 'lower'] = row['lower']
            ep.ix[conditions, 'upper'] = row['upper']

        # Override location gamma defaults if specified in DB
        subreg_gamma = mpm[(mpm.parameter_type_id==14) & (mpm.cascade_level_id==4)]
        reg_gamma = mpm[(mpm.parameter_type_id==14) & (mpm.cascade_level_id==3)]
        super_gamma = mpm[(mpm.parameter_type_id==14) & (mpm.cascade_level_id==2)]
        for val in ['mean','lower','upper']:
            for i, row in subreg_gamma.iterrows():
                conditions = ((ep.integrand==row['measure']) &
                    (ep.effect=='gamma') &
                    (ep.name.isin(['subreg'])))
                if row['measure'] in self.integrand_pred:
                    ep.ix[conditions, val] = subreg_gamma[val].values[0]
            for i, row in reg_gamma.iterrows():
                conditions = ((ep.integrand==row['measure']) &
                    (ep.effect=='gamma') &
                    (ep.name.isin(['region'])))
                if row['measure'] in self.integrand_pred:
                    ep.ix[conditions, val] = reg_gamma[val].values[0]
            for i, row in super_gamma.iterrows():
                conditions = ((ep.integrand==row['measure']) &
                    (ep.effect=='gamma') &
                    (ep.name.isin(['super'])))
                if row['measure'] in self.integrand_pred:
                    ep.ix[conditions, val] = super_gamma[val].values[0]

        lmap = gen_locmap(
                self.model_version_meta.location_set_version_id.values[0])
        if len(self.covariate_data) > 0:
            ccovs = list(
                    set(self.covariate_data.columns) -
                    set(['location_id', 'year_id', 'x_sex']))
            self.covariate_data = self.covariate_data.merge(
                    lmap, on='location_id', how='left')

            regcovs = self.covariate_data.groupby(
                    ['region', 'year_id', 'x_sex'])[ccovs].mean().reset_index()
            regcovs.rename(columns={'region': 'location_id'}, inplace=True)
            supcovs = self.covariate_data.groupby(
                    ['super', 'year_id', 'x_sex'])[ccovs].mean().reset_index()
            supcovs.rename(columns={'super': 'location_id'}, inplace=True)
            gcovs = self.covariate_data.groupby(
                    ['year_id', 'x_sex'])[ccovs].mean().reset_index()
            gcovs['location_id'] = '1.0'
            self.covariate_data = pd.concat([
                self.covariate_data, regcovs, supcovs, gcovs])

        return ep


    def get_rate_prior(self):
        """
        If not provided in the database, use the following defaults:
            d<<param>> = {
                'age'   : <<any age_start except the terminal age_start>>,
                'lower' : -inf,
                'upper' : inf,
                'mean'  : 0.0,
                'std'   : inf }

            chi = {
                'age'   : <<any age_start except the terminal age_start>>,
                'lower' : 0.0,
                'upper' : 5.0, ?? changed to 1.0
                'mean'  : 2.5, ?? changed to 0.5
                'std'   : inf })

            iota, omega, rho = {
                'age'   : <<any age_start except the terminal age_start>>,
                'lower' : 0.0,
                'upper' : 1.0,
                'mean'  : 0.5,
                'std'   : inf }

        Mapping from integrand names to rates
            integrand2rate = {
                'incidence' : 'iota' ,
                'remission' : 'rho'  ,
                'mtexcess'  : 'chi'  ,
                'mtother'   : 'omega'
            }
        """
        # Generate default frame
        ages_num = [ float(a) for a in self.age_mesh ]
        ages_str = self.age_mesh

        slope_defaults = pd.DataFrame({
            'age'   : ages_str,
            'lower' : -inf,
            'upper' : inf,
            'mean'  : 0.0,
            'std'   : inf })
        slope_defaults = slope_defaults[:-1]

        val_defaults = {}
        val_defaults['iota']  = pd.DataFrame({
            'age'   : ages_str,
            'lower' : 0.0,
            'upper' : 10.0,
            'mean'  : 5.0,
            'std'   : inf })
        val_defaults['rho']  = pd.DataFrame({
            'age'   : ages_str,
            'lower' : 0.0,
            'upper' : 10.0,
            'mean'  : 5.0,
            'std'   : inf })
        val_defaults['chi']  = pd.DataFrame({
            'age'   : ages_str,
            'lower' : 0.0,
            'upper' : 10.0,
            'mean'  : 5.0,
            'std'   : inf })
        if self.single_param in ['proportion','prevalence']:
            val_defaults['omega'] = pd.DataFrame({
                'age'   : ages_str,
                'lower' : 0.0,
                'upper' : 1.0,
                'mean'  : 0.5,
                'std'   : inf })
        elif self.single_param=='continuous':
            val_defaults['omega'] = pd.DataFrame({
                'age'   : ages_str,
                'lower' : 0.0,
                'upper' : inf,
                'mean'  : 1,
                'std'   : inf })
        else:
            val_defaults['omega'] = pd.DataFrame({
                'age'   : ages_str,
                'lower' : 0.0,
                'upper' : 10.0,
                'mean'  : 5.0,
                'std'   : inf })

        rp_df = []
        for t in ['iota', 'rho', 'chi', 'omega']:
            type_slope = slope_defaults.copy()
            type_slope['type'] = 'd'+t
            rp_df.append(type_slope)
            type_val = val_defaults[t].copy()
            type_val['type'] = t
            rp_df.append(type_val)
        rp_df = pd.concat(rp_df)

        # Override defaults if specified in the database
        mpm = self.model_params

        val_pri = mpm[mpm.parameter_type_id==1]
        if len(val_pri)>0:
            val_pri['mean']  = val_pri['mean'].fillna((val_pri.lower+val_pri.upper)/2.0)
            val_pri['lower'] = val_pri.lower.fillna(val_pri['mean'])
            val_pri['upper'] = val_pri.upper.fillna(val_pri['mean'])

        slope_pri = mpm[mpm.parameter_type_id==2]
        if self.single_param is not None:
            val_pri['measure'] = 'mtother'
            slope_pri['measure'] = 'mtother'
        if len(slope_pri)>0:
            slope_pri['mean']  = slope_pri['mean'].fillna((slope_pri.lower+slope_pri.upper)/2.0)
            slope_pri['lower'] = slope_pri.lower.fillna(slope_pri['mean'])
            slope_pri['upper'] = slope_pri.upper.fillna(slope_pri['mean'])

        rp_df['age'] = rp_df.age.astype('float')
        for integrand, rate in integrand_rate_map.iteritems():
            ivp = val_pri[val_pri.measure==integrand]
            isp = slope_pri[slope_pri.measure==integrand]
            for a in ages_num:
                ivp_mlu = ivp.ix[(ivp.age_start<=a) & (ivp.age_end>=a), ['mean','lower','upper']]
                isp_m = isp.ix[(isp.age_start<=a) & (isp.age_end>=a), 'mean']

                if len(ivp_mlu)>0:
                    rp_df.ix[(rp_df.type==rate) & (rp_df.age==a), "lower"] = ivp_mlu['lower'].values[0]
                    rp_df.ix[(rp_df.type==rate) & (rp_df.age==a), "upper"] = ivp_mlu['upper'].values[0]
                    rp_df.ix[(rp_df.type==rate) & (rp_df.age==a), "mean"] = ivp_mlu['mean'].values[0]
                if len(isp_m)>0:
                    if isp_m.values[0]==1:
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "lower"] = 0
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "upper"] = inf
                    elif isp_m.values[0]==-1:
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "lower"] = -inf
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "upper"] = 0
                    else:
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "lower"] = -inf
                        rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a), "upper"] = inf

        # Enforce slope priors
        for integrand, rate in integrand_rate_map.iteritems():
            for i, a in enumerate(ages_num[:-1]):
                next_age = ages_num[i+1]
                this_mean = rp_df.ix[(rp_df.type==rate) & (rp_df.age==a),
                    "mean"].values[0]
                next_mean = rp_df.ix[(rp_df.type==rate) & (rp_df.age==next_age),
                    "mean"].values[0]

                if rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a),
                        "lower"].values[0] == 0:
                    next_mean = np.clip(next_mean, a_min=this_mean,
                            a_max=inf)
                elif rp_df.ix[(rp_df.type=='d'+rate) & (rp_df.age==a),
                        "upper"].values[0] == 0:
                    next_mean = np.clip(next_mean, a_min=-inf,
                            a_max=this_mean)

                rp_df.ix[(rp_df.type==rate) & (rp_df.age==next_age),
                    "mean"] = next_mean

        # If this is a single parameter model, set all rates
        # except omega to zero
        if self.single_param is not None:
            rp_df.ix[~rp_df.type.isin(['omega','domega']), 'mean'] = 0
            rp_df.ix[~rp_df.type.isin(['omega','domega']), 'lower'] = 0
            rp_df.ix[~rp_df.type.isin(['omega','domega']), 'upper'] = 0
            rp_df.ix[~rp_df.type.isin(['omega','domega']), 'std'] = inf

            if self.single_param=='proportion':
                o_low = rp_df.ix[rp_df.type=='omega', 'lower']
                o_upp = rp_df.ix[rp_df.type=='omega', 'upper']
                rp_df.ix[rp_df.type=='omega', 'lower'] = o_low.clip(lower=0)
                rp_df.ix[rp_df.type=='omega', 'upper'] = o_upp.clip(upper=1)

        return rp_df

    def get_simple_prior(self):
        """
        Generate the simple smoothness priors. Use the integrand to
        greek map in the rate prior to map the database 'smoothness'
        overrides. """
        def_p_zero = pd.DataFrame([{
            'name'  : 'p_zero',
            'lower' : 0,
            'upper' : 0,
            'mean'  : 0,
            'std'   : inf}])

        if self.single_param is not None:
            def_omega = pd.DataFrame([{
                'name'  : 'xi_omega',
                'lower' : 0.3,
                'upper' : 0.3,
                'mean'  : 0.3,
                'std'   : inf}])
        else:
            def_omega = pd.DataFrame([{
                'name'  : 'xi_omega',
                'lower' : 1,
                'upper' : 1,
                'mean'  : 1,
                'std'   : inf}])

        def_other = pd.DataFrame({
            'name'  : ['xi_iota', 'xi_rho', 'xi_chi'],
            'lower' : 0.3,
            'upper' : 0.3,
            'mean'  : 0.3,
            'std'   : inf})

        sp = pd.concat([def_p_zero, def_omega, def_other])

        mpm = self.model_params
        smooth_df = mpm[mpm.parameter_type_id==10]
        if self.single_param is not None:
            smooth_df['measure'] = 'mtother'
        for integrand in integrand_rate_map.keys():
            if integrand in smooth_df.measure.values:
                lower = smooth_df.ix[smooth_df.measure==integrand, "lower"].values[0]
                upper = smooth_df.ix[smooth_df.measure==integrand, "upper"].values[0]
                mean = (lower+upper)/2.0
                rate = integrand_rate_map[integrand]

                sp.ix[sp.name=='xi_'+rate, "lower"] = lower
                sp.ix[sp.name=='xi_'+rate, "upper"] = upper
                sp.ix[sp.name=='xi_'+rate, "mean"] = mean

        if self.model_version_meta['birth_prev'].values[0]==1:
            sp.ix[sp.name=='p_zero', "lower"] = 0
            sp.ix[sp.name=='p_zero', "upper"] = 1
            sp.ix[sp.name=='p_zero', "mean"] = 0.01

        return sp[['name','lower','upper','mean','std']]

    def get_value_prior(self):
        """ Most come from user inputs and the kappas
        should come from the integrand file """
        etas = self.assign_eta()
        mvm = self.model_version_meta

        value_params = {}
        for integrand, rate in integrand_rate_map.iteritems():
            if integrand in etas.integrand.values:
                kappa = etas.ix[etas.integrand==integrand, "eta"].values[0]
                value_params["kappa_"+rate] = kappa
            else:
                value_params["kappa_"+rate] = 1e-5
        value_params['kappa_omega'] = 1e-5

        for i, eta_row in etas.iterrows():
            value_params['eta_%s' % eta_row['integrand']] = eta_row['eta']

        value_params['sample_interval'] = mvm.sample_interval.values[0]
        value_params['num_sample'] = mvm.num_sample.values[0]
        value_params['integrate_step'] = mvm.integrate_step.values[0]
        value_params['random_seed'] = mvm.random_seed.values[0]
        value_params['integrate_method'] = mvm.integration_type.values[0]
        value_params['integrate_method'] = value_params['integrate_method'].lower().replace(" ","_")
        # value_params['condition'] = mvm.sequela_name.values[0]
        value_params['watch_interval'] = value_params['num_sample']/100
        value_params['data_like'] = 'in_data_file'
        value_params['prior_like'] = likelihood_map[
                self.model_version_meta.prior_likelihood.values[0]]

        value_params = pd.DataFrame({
            'name'  : value_params.keys(),
            'value' : value_params.values()})

        return value_params

    def get_study_cov_ids(self):
        query = """
            SELECT study_covariate_id, study_covariate
            FROM epi.study_covariate"""
        df = Importer.execute_select(query, 'epi')
        return df

    def get_country_cov_ids(self):
        query = """
            SELECT covariate_id, covariate_name_short
            FROM shared.covariate"""
        df = Importer.execute_select(query, 'epi')
        return df

    def get_measure_ids(self):
        query = """
            SELECT measure_id, measure
            FROM shared.measure"""
        df = Importer.execute_select(query, 'epi')
        return df

    def get_age_weights(self):
        query = """
            SELECT age_group_id, age_group_weight_value as weight
            FROM shared.age_group_weight
            JOIN shared.gbd_round USING(gbd_round_id)
            WHERE gbd_round=2015
            AND age_group_weight_value IS NOT NULL"""
        df = Importer.execute_select(query, 'epi')
        return df
