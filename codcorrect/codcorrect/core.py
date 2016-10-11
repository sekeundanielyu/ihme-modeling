import sqlalchemy as sql
import pandas as pd
import logging
import json
import getpass

def run_query(sql_statement, server=DEFAULT_SERVER_NAME, database=DEFAULT_DB):
    engine = sql.create_engine(CONNECTION_STRING)
    connection = engine.raw_connection()
    result_df = pd.read_sql(sql_statement, connection)
    connection.close()
    return result_df


def read_json(file_path):
    json_data = open(file_path)
    data = json.load(json_data)
    json_data.close()
    return data


def write_json(json_dict, file_path):
    je = open(file_path,'w')
    je.write(json.dumps(json_dict))
    je.close()


def get_credentials(key, credential_path=None):
    if credential_path==None:
        credential_path = USER_CREDENTIALS_PATH
    c = read_json(credential_path)
    return c[key]['user'], c[key]['password']


class Envelope(object):
    def __init__(self, data, index_columns, pop_column, data_columns):
        self.data = data
        self.index_columns = index_columns
        self.pop_column = pop_column
        self.data_columns = data_columns

    def reshape_long(self):
        data = self.data.copy(deep=True)
        data = data[self.index_columns + [self.pop_column] + self.data_columns]
        data = pd.melt(data, id_vars=self.index_columns + [self.pop_column],
                       var_name='draw', value_name='envelope')
        return data
