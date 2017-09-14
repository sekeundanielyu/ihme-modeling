import pandas as pd
import argparse
import sqlalchemy as sa
idx = pd.IndexSlice

##############################################################
## Function for querying DBs
##############################################################
def queryToDF(query, host = 'ADDRESS', db = '', user = 'USERNAME', 
			pwd = 'PASSWORD', select = True):
	if db == '':
		conn_string = ADDRESS.format(user = user, 
			pwd = pwd, host = host)
	else:
		conn_string = ADDRESS.format(user = user, 
			pwd = pwd, host = host, db = db)
	engine = sa.create_engine(conn_string)
	conn = engine.connect()

	query = sa.text(query)
    
	result = conn.execute(query) 

	if not select:
		conn.close()
		return result
        
	df = pd.DataFrame(result.fetchall())
	conn.close()
	if len(df) == 0:
		return pd.DataFrame()
	df.columns = result.keys()
	assert(result.rowcount > 0)

	return df

##############################################################
## Pulls 2015 births data for desired years and locations.
## Returns births
##############################################################

def get_births(cfr_df):
	births_dir = 'FILEPATH'
	births_df = pd.read_stata(births_dir)
	births_df = births_df.loc[births_df['sex'] != 'both'] ## no sex = both
	
	births_df = births_df.drop(['sex', 'ihme_loc_id', 'source', 'location_name'], axis = 1)
	births_df = births_df.loc[births_df['year'].isin([1990, 1995, 2000, 2005, 2010, 2016])]
	births_df = births_df.loc[births_df['location_id'].isin(cfr_df['location_id'].unique())]
	births_df = births_df.rename(columns = {'sex_id': 'sex'})
	births_df = births_df.set_index(col_list)
	births_df = births_df.sortlevel()
	return births_df

##############################################################
## Pulls CFR and 28 day prevalence data for desired years and 
## locations. Returns births, 28 day prev, and CFR
##############################################################
def get_days_cfr_dfs(birth_prev, cfr, acause):
	data_dir = FILEPATH
    
	cfr_df = pd.read_csv(FILEPATH)
	cfr_df = cfr_df.rename(columns = {'draw_1000' : 'draw_0'})
	cfr_df = cfr_df.loc[cfr_df['year'].isin([1990, 1995, 2000, 2005, 2010, 2016])]
    
	days_df = pd.read_stata(FILEPATH)
	days_df = days_df.drop(['age_group_id', 'measure_id', 'modelable_entity_id'], axis = 1)
	days_df = days_df.drop_duplicates()
	days_df = days_df.loc[days_df['location_id'].isin(cfr_df['location_id'].unique())]
	days_df = days_df.rename(columns = {'year_id': 'year', 'sex_id': 'sex'})
	days_df = days_df.set_index(col_list)
	days_df = days_df.sortlevel()
    
	births_df = get_births(cfr_df)
	cfr_df = cfr_df.set_index(col_list)
	cfr_df = cfr_df.sortlevel()
    
	return births_df, days_df, cfr_df

##############################################################
## Pulls mild and moderate draws for desired years. Returns
## mild and moderate draws
##############################################################	
def get_mild_modsev_dfs(mild_prop, modsev_prop, acause):
	data_dir = 'FILEPATH'
    
	mild_df = pd.read_csv(FILEPATH)
	mild_df = mild_df.rename(columns = {'draw_1000' : 'draw_0'})
	mild_df = mild_df.loc[mild_df['year'].isin([1990, 1995, 2000, 2005, 2010, 2016])]
	mild_df = mild_df.set_index(col_list)
	mild_df = mild_df.sortlevel()

	modsev_df = pd.read_csv(FILEPATH)
	modsev_df = modsev_df.rename(columns = {'draw_1000' : 'draw_0'})
	modsev_df = modsev_df.loc[modsev_df['year'].isin([1990, 1995, 2000, 2005, 2010, 2016])]
	modsev_df = modsev_df.set_index(col_list)
	modsev_df = modsev_df.sortlevel()
    
	return mild_df, modsev_df

##############################################################
## Pulls at birth, 0-6 days, and 7-27 days prevalence for
## desired years and locations. Returns at birth prev, 0-6
## prev, and 7-27 prev
##############################################################	
def get_other_modsev_dfs(birth_prev, acause):
	data_dir = FILEPATH
	
	cfr_df = pd.read_csv(FILEPATH)
	cfr_df = cfr_df.rename(columns = {'draw_1000' : 'draw_0'})
	cfr_df = cfr_df.loc[cfr_df['year'].isin([1990, 1995, 2000, 2005, 2010, 2016])]
	
	at_birth_df = pd.read_stata(FILEPATH)
	at_birth_df = at_birth_df.drop(['age_group_id', 'measure_id', 'modelable_entity_id'], axis = 1)
	at_birth_df = at_birth_df.drop_duplicates()
	at_birth_df = at_birth_df.loc[at_birth_df['location_id'].isin(cfr_df['location_id'].unique())]
	at_birth_df = at_birth_df.rename(columns = {'year_id': 'year', 'sex_id': 'sex'})
	at_birth_df = at_birth_df.set_index(col_list)
	at_birth_df = at_birth_df.sortlevel()
	
	oh_six_df = pd.read_stata(FILEPATH)
	oh_six_df = oh_six_df.drop(['age_group_id', 'measure_id', 'modelable_entity_id'], axis = 1)
	oh_six_df = oh_six_df.drop_duplicates()
	oh_six_df = oh_six_df.loc[oh_six_df['location_id'].isin(cfr_df['location_id'].unique())]
	oh_six_df = oh_six_df.rename(columns = {'year_id': 'year', 'sex_id': 'sex'})
	oh_six_df = oh_six_df.set_index(col_list)
	oh_six_df = oh_six_df.sortlevel()
	
	seven_df = pd.read_stata(FILEPATH)
	seven_df = seven_df.drop(['age_group_id', 'measure_id', 'modelable_entity_id'], axis = 1)
	seven_df = seven_df.drop_duplicates()
	seven_df = seven_df.loc[seven_df['location_id'].isin(cfr_df['location_id'].unique())]
	seven_df = seven_df.rename(columns = {'year_id': 'year', 'sex_id': 'sex'})
	seven_df = seven_df.set_index(col_list)
	seven_df = seven_df.sortlevel()
	
	return at_birth_df, oh_six_df, seven_df

##############################################################
## Get counts for a specific severity (mild, modsev)
##############################################################	
def counts_sev(days_df, cfr_df, inputs, acause_dict, births_df):
	for df, name in inputs:
		cfr_join = cfr_df.applymap(lambda x: 1 - x)
		prev_df = days_df.multiply(cfr_join)
		prev_df = prev_df.multiply(df)
		prev_df = prev_df.multiply(births_df['births'], axis = 'index')
		prev_df = prev_df.sortlevel()
    	
		acause_dict[name] = prev_df
    
	return acause_dict

##############################################################
## Get total symptomatic count and total count
##############################################################	
def counts_total(days_df, cfr_df, acause_dict, births_df):
	cfr_join = cfr_df.applymap(lambda x: 1 - x)
	total_df = days_df.multiply(cfr_join)
	all_df = total_df
	total_df = total_df.multiply(0.9)
	total_df = total_df.multiply(births_df['births'], axis = 'index')
	all_df = all_df.multiply(births_df['births'], axis = 'index')
	total_df = total_df.sortlevel()
	all_df = all_df.sortlevel()
	
	acause_dict['total_symp_count'] = total_df
	acause_dict['total_count'] = all_df
	
	return acause_dict

##############################################################
## Merge most detailed status of locations onto a dataframe
##############################################################
def merge_most_detailed(df):
	query = '''
		SELECT location_id, most_detailed
		FROM ADDRESS
		WHERE location_set_version_id = 153
		AND location_set_id = 35
	'''
	detailed = queryToDF(query, host = 'ADDRESS')
	detailed = detailed.drop_duplicates()
	m = df.merge(detailed, on = 'location_id', how = 'left')
	assert len(m) == len(df), 'wrong length'
	return m

##############################################################
## Return only most detailed locations for mild, modsev, and
## symptomatic counts
##############################################################
def most_detailed(cause_dict):
	for prop_type in ['mild_count', 'modsev_count', 'total_symp_count']:
		detailed_df = cause_dict[prop_type]
		detailed_df = detailed_df.reset_index()
		detailed_df = merge_most_detailed(detailed_df)
		detailed_df = detailed_df.reset_index()
		detailed_df = detailed_df.drop('index', axis = 1)
		detailed_df = detailed_df.set_index(col_list)
		detailed_df = detailed_df.loc[detailed_df['most_detailed'] == 1]
		detailed_df = detailed_df.drop('most_detailed', axis = 1)
		cause_dict[prop_type] = detailed_df
	return cause_dict

##############################################################
## Merge parent_id and level onto a dataframe
##############################################################
def merge_detailed_loc(df):
	query = '''
		SELECT location_id, parent_id, level
		FROM ADDRESS
		WHERE location_set_version_id = 153
		AND location_set_id = 35
	'''
	detailed = queryToDF(query, host = 'ADDRESS')
	detailed = detailed.drop_duplicates()
	m = df.merge(detailed, on = 'location_id', how = 'left')
	assert len(m) == len(df), 'wrong length'
	return m

##############################################################
## Scales prevalence according to severity.
##############################################################
def rescale_prev(cause_dict):
	squeeze_dict = cause_dict
	summed = squeeze_dict['mild_count'] + squeeze_dict['modsev_count']
	too_big_pre = summed[(summed - squeeze_dict['total_symp_count']) > 0.5]    
	too_big_rows = too_big_pre.dropna(how = 'all')
	print '%s country-year-sexes have proportions greater than the total!' % (len(too_big_rows))
	too_big_cols = too_big_rows.dropna(how='all', axis=1)
	print 'Of those, %s columns have proportions greater than the total!' % (len(too_big_cols.columns))
    
	if len(too_big_rows) == 0:
		no_more_squeezing = True
	else:
		no_more_squeezing = False
		scale_factor = squeeze_dict['total_symp_count'] / summed
		scale_factor = scale_factor.applymap(lambda x: min(1, x))
        
		for prop_type in ['mild_count', 'modsev_count']:
			squeeze_dict[prop_type] = squeeze_dict[prop_type] * scale_factor 
	return no_more_squeezing, squeeze_dict

##############################################################
## Iteratively runs the rescale_prev function, checks that
## mild + modsev is not larger than symptomatic
##############################################################
def scale_total(acause_dict):
	counter = 0
	no_more = False
	while no_more == False:
		no_more, acause_dict = rescale_prev(acause_dict)
		counter += 1
	summed = acause_dict['mild_count'] + acause_dict['modsev_count']
	too_big = summed[(summed - acause_dict['total_symp_count']) > 0.5]
	too_big = too_big.dropna(how = 'all', axis = 1)
	too_big = too_big.dropna(how = 'all', axis = 0)
    
	if not too_big.empty:
		print 'Error: not scaled correctly'
	return acause_dict

##############################################################
## Saves scaled mild and modsev counts
##############################################################
def save_scale(acause_dict, acause, birth_prev):
	for prop_type in ['mild_count', 'modsev_count']:
		prev_df = acause_dict[prop_type]
		prev_df = prev_df[draw_cols]
		test_outdir = FILEPATH
		prev_df.to_csv(FILEPATH)
	
##############################################################
## Calculates scaled prevalence for mild, 28 day modsev, and
## total
##############################################################	
def final_prev(acause_dict, births_df):
	for prop_type, prop_prev in zip(['mild_count', 'modsev_count', 'total_count'], ['mild_prev', '28_28_modsev_prev', 'total_prev']):
		acause_dict[prop_prev] = acause_dict[prop_type].div(births_df['births'], axis = 'index')
	return acause_dict

##############################################################
## Calculate asymptomatic prevalence as total minus mild and 
## 28 day modsev
##############################################################
def calc_asymp(acause_dict):
	acause_dict['asymp_prev'] = (acause_dict['total_prev'] - acause_dict['mild_prev']) - acause_dict['28_28_modsev_prev']
	return acause_dict
	
##############################################################
## Calculate modsev prevalence for at birth, 0-6 days, and 
## 7-27 days
##############################################################
def calc_modsevs(acause_dict, inputs):
	for df, prop_type in inputs:
		acause_dict[prop_type] = (df - acause_dict['mild_prev']) - acause_dict['asymp_prev']
	return acause_dict

##############################################################
## Saves mild and asymptomatic prevalence (same across all 
## ages), as well as at birth, 0-6, 7-27, and 28 day modsev
## prevalence
##############################################################
def save_prev(acause_dict, acause, birth_prev):
	for prop_type in ['mild_prev', '0_0_modsev_prev', '0_7_modsev_prev', '7_28_modsev_prev', '28_28_modsev_prev', 'asymp_prev']:
		prev_df = acause_dict[prop_type]
		prev_df = prev_df[draw_cols]
		test_outdir = FILEPATH
		prev_df.to_csv(FILEPATH)
	
if __name__ == '__main__':
	parser = argparse.ArgumentParser()
	parser.add_argument("birth_prev", help = "birth_prev", dUSERt = 2525, type = int)
	parser.add_argument("cfr", help = "cfr", dUSERt = 'cfr', type = str)
	parser.add_argument("mild_prop", help = "mild_prop", dUSERt = 'long_mild', type = str)
	parser.add_argument("modsev_prop", help = "modsev_prop", dUSERt = 'long_modsev', type = str)
	parser.add_argument("acause", help = "acause", dUSERt = 'neonatal_enceph', type = str)
	args = parser.parse_args()
	birth_prev = args.birth_prev
	cfr = args.cfr
	mild_prop = args.mild_prop
	modsev_prop = args.modsev_prop
	acause = args.acause

	parent_dir = FILEPATH
	code_dir = FILEPATH
	
	col_list = ['year', 'location_id', 'sex']
	draw_cols = ['draw_%s' % i for i in range(0, 1000)]

	births_df, days_df, cfr_df = get_days_cfr_dfs(birth_prev, cfr, acause)
	at_birth_df, oh_six_df, seven_df = get_other_modsev_dfs(birth_prev, acause)
	mild_df, modsev_df = get_mild_modsev_dfs(mild_prop, modsev_prop, acause)
	acause_dict = {}
	counts_list = zip([mild_df, modsev_df], ['mild_count', 'modsev_count'])
	acause_dict = counts_sev(days_df, cfr_df, counts_list, acause_dict, births_df)
	acause_dict = counts_total(days_df, cfr_df, acause_dict, births_df)
	acause_dict = most_detailed(acause_dict)
	acause_dict = scale_total(acause_dict)
	save_scale(acause_dict, acause, birth_prev)
	acause_dict = final_prev(acause_dict, births_df)
	acause_dict = calc_asymp(acause_dict)
	modsev_list = zip([at_birth_df, oh_six_df, seven_df], ['0_0_modsev_prev', '0_7_modsev_prev', '7_28_modsev_prev'])
	acause_dict = calc_modsevs(acause_dict, modsev_list)
	save_prev(acause_dict, acause, birth_prev)