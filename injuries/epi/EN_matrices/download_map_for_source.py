import requests
import json
import sys
import pandas as pd


# CHANGE THESE AS NECESSARY
if not len(sys.argv)>=3:
    print 'USAGE: python download_map_for_source.py CODE_SYSTEM OUTPUT_FOLDER [OUTPUT_TYPE]'
    sys.exit()
# use either "ICD10" or "ICD9_detail"
code_system = sys.argv[1]
if code_system not in ["ICD10", "ICD9_detail"]:
    print 'ERROR: use ICD10 or ICD9_detail for code system argument'
    sys.exit()
# use the unix-based filepath where you want the result stored
output_folder = sys.argv[2]
if "J:/" in output_folder:
    print 'looks like you are trying to use a windows filepath - use /home/j/ and run this on the cluster'
    sys.exit()
# output type
if len(sys.argv)==4:
    output_type = sys.argv[3]
    if not output_type in ['stata', 'csv']:
        print 'ERROR: output type must be either "stata" or "csv"'
        sys.exit()
else:
    output_type = 'stata'

# DON'T CHANGE THESE
causes_filepath = "/home/j/WORK/00_dimensions/03_causes/gbd2015_causes_all.dta"
url = "http://garbageviz-web-d01.ihme.washington.edu/api"
map_df = []
cause_set_version_id = 16
map_type_id = 1


# Pull causes
causes_df = pd.read_stata(causes_filepath)
causes_df = causes_df[['cause_id', 'acause', 'cause_name']]

# Get list of all cscsmt_ids
response = requests.get(url+"/cscsmt/")
cscsmt_df = pd.DataFrame(response.json())
cscsmt_df['cscsmt_id'] = cscsmt_df['cscsmt_id'].map(lambda x: int(x))

# Get map types
response = requests.get(url+"/map_types")
maptypes_df = pd.DataFrame(response.json())

# Get code systems
response = requests.get(url+"/code_system")
cs_df = pd.DataFrame(response.json())
cs_df['code_system_id'] = cs_df['code_system_id'].map(lambda x: int(x))

for cs in cs_df.ix[cs_df['name']==code_system, 'code_system_id'].tolist():
    # Pull code list
    response = requests.get(url+"/code_system/{}/codes/".format(cs))
    codes_df = pd.DataFrame(response.json())

    # Bring in maps for each cscsmt_id
    temp = []
    for cscsmt_id in cscsmt_df.ix[(cscsmt_df['code_system_id']==cs)&(cscsmt_df['cause_set_version_id']==cause_set_version_id), 'cscsmt_id'].drop_duplicates():
        # Get maps for source
        response = requests.get(url+"/cscsmt/{}/maps".format(cscsmt_id))
        temp.append(pd.DataFrame(response.json()))
    temp = pd.concat(temp)

    # Merge on map_type info
    temp = pd.merge(temp, cscsmt_df, on='cscsmt_id')
    temp = pd.merge(temp, maptypes_df, on='map_type_id')

    # Merge on causes
    temp = pd.merge(temp, causes_df, on='cause_id')
           
    # Reshape map_type name wide
    temp = temp.ix[:, ['code_id', 'code_system_id', 'name', 'acause', 'cause_name']].rename(columns={'name': 'map_type_name'})
    temp = temp.set_index(['code_id', 'code_system_id', 'map_type_name'])
    temp = temp.unstack(level=-1)
    temp.columns = ['_'.join(col).strip() for col in temp.columns.values]
    for mt in ['YLL', 'YLD']:
        temp = temp.rename(columns={'acause_{}'.format(mt): '{}_cause'.format(mt.lower()), 'cause_name_{}'.format(mt): '{}_cause_name'.format(mt.lower())})
    temp = temp.reset_index()

    # Merge on code information
    temp = pd.merge(temp, codes_df[['code_id', 'value', 'name', 'sort']], on='code_id').rename(columns={'value':'cause_code', 'name':'cause_name'})

    # Merge on code system information
    temp = pd.merge(temp, cs_df, on='code_system_id')

    # Remove decimals if needed
    temp.ix[temp['remove_decimal']==True, 'cause_code'] = temp.ix[temp['remove_decimal']==True, 'cause_code'].map(lambda x: x.replace('.',''))

    # Reformat and add to maps
    temp = temp.sort('sort').reset_index(drop=True).ix[:, ['source_label', 'cause_code', 'cause_name', 'yll_cause', 'yll_cause_name', 'yld_cause']].fillna('')
    map_df.append(temp)

map_df = pd.concat(map_df).reset_index(drop=True)

# Remove source label if they are all blank
keep_vars = ['cause_code', 'cause_name', 'yll_cause', 'yll_cause_name']
if len(map_df.ix[map_df['source_label']!='']) > 0:
    keep_vars.append('source_label')
    
# Remove YLD causes if they are all blank
if len(map_df.ix[map_df['yld_cause']!='']) > 0:
    keep_vars.append('yld_cause')
    keep_vars.append('yld_cause_name')
map_df = map_df.ix[:, keep_vars].fillna('')

# Make cause names no greater than 244 characters
map_df['cause_name'] = map_df['cause_name'].map(lambda x: x[:243])
    
# Make sure all columns are formatted as strings
for c in map_df.columns:
    for i in map_df.index:
        try:
            a = str(map_df.ix[i, c])
        except:
            map_df.ix[i, c] = ''
    map_df[c] = map_df[c].astype('str')
    
for c in cs_df.columns:
    for i in cs_df.index:
        try:
            a = str(cs_df.ix[i, c])
        except:
            cs_df.ix[i, c] = ''
    cs_df[c] = cs_df[c].astype('str')
    
# Save
if output_type=='stata':
    map_df.to_stata(output_folder+"/map_{}.dta".format(code_system), write_index=False)
else:
    map_df.to_csv(output_folder+"/map_{}.csv".format(code_system), index=False)
