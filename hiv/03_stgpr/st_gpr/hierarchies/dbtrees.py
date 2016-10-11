import sqlalchemy
import tree
import pandas as pd
from functools32 import lru_cache


@lru_cache(maxsize=32)
def loctree(location_set_version_id, location_set_id=None):
    """ Constructs and returns a tree representation of the location
    hierarchy specified by location_set_version_id """
    mysql_server = (
            'mysql+pymysql://strConnection
            '@modeling-epi-db.ihme.washington.edu:3306'
            '/?charset=utf8&use_unicode=0')
    e = sqlalchemy.create_engine(mysql_server)
    c = e.connect()

    if location_set_id is not None:
        query = """
            SELECT  location_id,
                    parent_id,
                    is_estimate,
                    location_name,
                    location_name_short,
                    map_id,
                    location_type
            FROM shared.location_hierarchy
            JOIN shared.location USING(location_id)
            JOIN shared.location_type
                ON location.location_type_id = location_type.location_type_id
            WHERE location_set_id=%s """ % (location_set_id)
    else:
        query = """
        SELECT location_id, parent_id, is_estimate,
            location_hierarchy_history.location_name,
            location_hierarchy_history.location_name_short,
            location_hierarchy_history.map_id,
            location_hierarchy_history.location_type
        FROM shared.location_hierarchy_history
        JOIN shared.location USING(location_id)
        LEFT JOIN shared.location_type
            ON location_hierarchy_history.location_type_id =
            location_type.location_type_id
        WHERE location_set_version_id=%s """ % (location_set_version_id)

    locsflat = pd.read_sql(query, c.connection)
    lt = tree.parent_child_to_tree(locsflat, 'parent_id', 'location_id')
    return lt
