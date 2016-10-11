import sqlalchemy as sql
import pandas as pd
import logging

def run_query(sql_statement, server=DATABASE_HOST, database="cod"):
    engine = sql.create_engine(CONNECTION_STRING)
    connection = engine.raw_connection()
    result_df = pd.read_sql(sql_statement, connection)
    connection.close()
    return result_df


def insert_row(insert_object, engine):
    connection = engine.connect()
    result = connection.execute(insert_object)
    connection.close()
    return int(result.inserted_primary_key[0])


def execute_statement(sql_statement, server=DATABASE_HOST, database="cod"):
    engine = sql.create_engine(CONNECTION_STRING)
    connection = engine.connect()
    try:
        print connection.execute(sql_statement)
    except:
        pass
    connection.close()
