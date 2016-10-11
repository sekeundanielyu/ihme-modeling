import sqlalchemy
import pandas as pd
from config import settings


def query(server, query):
    """ Convience for querying the db servers """
    cstr = settings['conn_strs'][server]
    eng = sqlalchemy.create_engine(cstr)
    res = pd.read_sql(query, eng)
    return res
