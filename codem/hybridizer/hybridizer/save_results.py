import sqlalchemy as sql
import pandas as pd
from hybridizer.core import run_query, execute_statement
import datetime
import logging
import os


class ModelData(object):

    def __init__(self, model_version_id, data_draws, index_columns, envelope_column, pop_column, data_columns, location_set_id):
        self.model_version_id = model_version_id
        self.data_draws = data_draws
        self.index_columns = index_columns
        self.envelope_column = envelope_column
        self.pop_column = pop_column
        self.data_columns = data_columns
        self.location_set_id = location_set_id

        self.location_hierarchy = self.get_location_hierarchy()

        self.data_summaries = None
        self.model_folder = None
        self.age_group_id_start = None
        self.age_group_id_end = None
        self.acause = None
        self.sex_id = None
        self.user = None

        self.get_model_details()
        self.get_model_folder()
        self.check_missing_locations()

    def get_model_details(self):
        sql_query = """SELECT
                           mv.model_version_id,
                           mv.cause_id,
                           c.acause,
                           mv.sex_id,
                           mv.inserted_by
                       FROM
                           cod.model_version mv
                       JOIN
                           shared.cause c USING (cause_id)
                       WHERE
                           model_version_id = {};""".format(self.model_version_id)
        model_data = run_query(sql_query)
        self.acause = model_data.ix[0, 'acause']
        self.sex_id = model_data.ix[0, 'sex_id']
        self.user = model_data.ix[0, 'inserted_by']

    def get_age_range(self):
        self.age_group_id_start = self.data_draws.ix[(self.data_draws['age_group_id']>=2)&
                                                     (self.data_draws['age_group_id']<=21),
                                                     'age_group_id'].min()
        self.age_group_id_end = self.data_draws.ix[(self.data_draws['age_group_id']>=2)&
                                                   (self.data_draws['age_group_id']<=21),
                                                   'age_group_id'].max()
        self.age_group_id_start = int(self.age_group_id_start)
        self.age_group_id_end = int(self.age_group_id_end)

    def get_model_folder(self):
        self.model_folder = [MODEL_FOLDER,
                             self.acause,
                             str(self.model_version_id)]
        self.model_folder = '/'.join(self.model_folder)
        print self.model_folder

    @staticmethod
    def format_draws(self, data):
        keep_columns = self.index_columns + [self.envelope_column, self.pop_column] + self.data_columns
        return data[keep_columns]

    def get_location_hierarchy(self):
        sql_query = """SELECT
                           location_id,
                           level,
                           parent_id,
                           most_detailed
                       FROM
                           shared.location_hierarchy_history lhh
                       JOIN
                           shared.location_set_version lsv USING (location_set_version_id)
                       WHERE
                           lhh.location_set_id = {location_set_id} AND
                           lsv.gbd_round = 2015 AND
                           lsv.end_date IS NULL;""".format(location_set_id=self.location_set_id)
        location_hierarchy_history = run_query(sql_query)
        return location_hierarchy_history

    def get_most_detailed_locations(self):
        location_hierarchy_history = self.location_hierarchy.copy(deep=True)
        location_hierarchy_history = location_hierarchy_history.ix[
            location_hierarchy_history['most_detailed']==1]
        return location_hierarchy_history['location_id'].drop_duplicates().tolist()

    def check_missing_locations(self):
        draw_locations = self.data_draws['location_id'].drop_duplicates().tolist()
        most_detailed_locations = self.get_most_detailed_locations()
        if len(set(most_detailed_locations) - set(draw_locations)) > 0:
            print "The following locations as missing from the draws {}".format(', '.join([str(x) for x in list(set(most_detailed_locations) - set(draw_locations))]))
        else:
            print "No missing locations!"

    def aggregate_locations(self):
        if self.location_hierarchy is None:
            self.location_hierarchy = self.get_location_hierarchy()
        self.data_draws = self.format_draws(self, self.data_draws)
        self.check_missing_locations()
        data = self.data_draws.copy(deep=True)
        data = data.ix[data['location_id'].isin(self.get_most_detailed_locations())]
        data = pd.merge(data,
                        self.get_location_hierarchy(),
                        on='location_id',
                        how='left')
        max_level = data['level'].max()
        print max_level
        # Loop through
        data = self.format_draws(self, data)
        for level in xrange(max_level, 0, -1):
            print "Level:", level
            data = pd.merge(data,
                            self.location_hierarchy[['location_id',
                                                     'level',
                                                     'parent_id']
                                                   ],
                            on='location_id',
                            how='left')
            temp = data.ix[data['level']==level].copy(deep=True)
            temp['location_id'] = temp['parent_id']
            temp = self.format_draws(self, temp)
            temp = temp.groupby(self.index_columns).sum().reset_index()
            data = pd.concat([self.format_draws(self, data), temp]).reset_index(drop=True)
        self.data_draws = data

    def save_draws(self):
        sex_dict = {1: 'male', 2: 'female'}
        draws_filepath = self.model_folder + "/draws/deaths_{sex_name}.h5".format(sex_name=sex_dict[self.sex_id])
        if not os.path.exists(self.model_folder + "/draws"):
            os.makedirs(self.model_folder + "/draws")
        # self.data_draws.to_csv(draws_filepath.replace('.h5', '.csv'), index=False)
        self.data_draws.to_hdf(draws_filepath,
                               'data',
                               mode='w',
                               format='table',
                               data_columns=['location_id',
                                             'year_id',
                                             'sex_id',
                                             'age_group_id',
                                             'cause_id'])
        print "Draws saved!"

    def generate_all_ages(self):
        self.data_draws = self.data_draws.ix[self.data_draws['age_group_id']!=22]
        data = self.format_draws(self, self.data_draws)
        data = data.ix[(data['age_group_id']>=2)&(data['age_group_id']<=21)]
        data['age_group_id'] = 22
        data = data.groupby(self.index_columns).sum().reset_index()
        self.data_draws = pd.concat([self.data_draws, data])
        print "All ages generated!"

    def generate_age_standardized(self):
        print "Getting age-weights"
        sql_query = """SELECT
                           age_group_id,
                           age_group_weight_value
                       FROM
                           shared.age_group_weight agw
                       JOIN
                           shared.gbd_round USING (gbd_round_id)
                       WHERE
                           gbd_round = 2015;"""
        age_standard_data = run_query(sql_query)
        print "Prepping draws for merge"
        self.data_draws = self.data_draws.ix[self.data_draws['age_group_id']!=27]
        data = self.format_draws(self, self.data_draws)
        data = data.ix[(data['age_group_id']>=2)&(data['age_group_id']<=21)]
        print "Merging on age-weights"
        data = pd.merge(data,
                        age_standard_data,
                        on='age_group_id')
        print "Making adjusted rate"
        for c in self.data_columns:
            data[c] = data[c] * data['age_group_weight_value'] / data[self.pop_column]
        print "Collapsing to generate ASR"
        data['age_group_id'] = 27
        data = data.groupby(self.index_columns).sum().reset_index()
        print "Merging with original data"
        self.data_draws = pd.concat([self.data_draws, data])
        print "Age-standardized rates generated!"

    def generate_summaries(self):
        # Copy draws
        data = self.data_draws.copy(deep=True)
        # Convert to cause fractions
        for c in self.data_columns:
            data.ix[data['age_group_id']!=27, c] = data.ix[data['age_group_id']!=27, c] / data.ix[data['age_group_id']!=27, self.envelope_column]
        data = data[self.index_columns + self.data_columns]
        # Generate mean, lower, and upper
        data['mean_cf'] = data[self.data_columns].mean(axis=1)
        data['lower_cf'] = data[self.data_columns].quantile(0.025, axis=1)
        data['upper_cf'] = data[self.data_columns].quantile(0.975, axis=1)
        # Generate other columns
        data['model_version_id'] = self.model_version_id
        data['date_inserted'] = datetime.datetime.now()
        data['inserted_by'] = self.user
        data['last_updated'] = datetime.datetime.now()
        data['last_updated_by'] = self.user
        data['last_updated_action'] = 'INSERT'
        self.data_summaries = data.ix[:, self.index_columns + ['model_version_id',
                                                               'mean_cf',
                                                               'lower_cf',
                                                               'upper_cf',
                                                               'date_inserted',
                                                               'inserted_by',
                                                               'last_updated',
                                                               'last_updated_by',
                                                               'last_updated_action']
                                     ].copy(deep=True)
        print "Summaries calculated!"

    def save_summaries(self):
        summary_filepath = self.model_folder + "/summaries.csv"
        self.data_summaries.to_csv(summary_filepath, index=False)

    def upload_summaries(self):
        data = self.data_summaries.copy(deep=True)
        data = data[['model_version_id', 'year_id', 'location_id', 'sex_id',
                     'age_group_id', 'mean_cf', 'lower_cf', 'upper_cf',
                     'date_inserted', 'inserted_by', 'last_updated',
                     'last_updated_by', 'last_updated_action']
                    ].reset_index(drop=True)
        DB = CONNECTION_STRING
        engine = sql.create_engine(DB); con = engine.connect().connection
        data.to_sql("model", con, flavor="mysql", if_exists="append", index=False, chunksize=15000)
        con.close()

    def update_status(self):
        sql_statement = "UPDATE cod.model_version SET status = {status_code} WHERE model_version_id = {model_version_id}".format(status_code=1, model_version_id=self.model_version_id)
        execute_statement(sql_statement)
        print "Status updated!"
