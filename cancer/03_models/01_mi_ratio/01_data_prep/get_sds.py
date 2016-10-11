# -*- coding: utf-8 -*-
"""
Purpose: formats data used in CoD upload for cancer_db.

"""

## import functions
import pandas as pd
import platform
import sqlalchemy as sa
    
 ## define root   
root = "/home/j" if platform.system() == 'Linux' else "J:"

## start connection
conn_string = [connection string]
engine = sa.create_engine(conn_string)
conn = engine.connect()

## upload new data
print "     running queries..."
query ='''
     SELECT m.year_id, m.location_id, m.mean_value as SDS 
        from covariate.model m 
      INNER JOIN 
        covariate.model_version mv
        on m.model_version_id = mv.model_version_id and mv.is_best = 1
      INNER JOIN
      	covariate.data_version dv 
          on mv.data_version_id = dv.data_version_id
      INNER JOIN
      	shared.covariate c
      	 on dv.covariate_id = c.covariate_id and c.covariate_name_short = 'sds'
      INNER JOIN
         shared.location_hierarchy_history h
          on m.location_id = h.location_id and h.location_type like 'admin%'
	    INNER JOIN shared.location_set_version v ON h.location_set_version_id = v.location_set_version_id AND v.location_set_id = 8 AND isnull(v.end_date)
          ;
'''
result = conn.execute(sa.text(query))
sds = pd.DataFrame(result.fetchall())
sds.columns = ['year', 'location_id', 'SDS']
if sds.SDS[sds.duplicated(['location_id', 'year'])].count() != 0: quit

## close connection
conn.close()

## format output
print("saving...")
sds.to_csv(root+ "/WORK/07_registry/cancer/03_models/01_mi_ratio/02_data/sds.csv", index = False)
