import os
import pandas as pd
import itertools
from multiprocessing import Pool
import sys
sys.path.append("/home/j/WORK/04_epi/02_models/01_code/02_severity/01_code/prod")
import gbd_utils
gbd = gbd_utils.GbdConventions()

# Set the como version
como_version = sys.argv[1]

# Get envelope
counts_directory = "/clustertmp/WORK/04_epi/03_outputs/02_results/%s/diagnostics/" % (como_version)
envelope = pd.read_csv("/clustertmp/WORK/02_mortality/04_outputs/02_results/envelope.csv")
envelope = envelope[['iso3','year','age','sex_name','pop_scaled']]
envelope['age'] = envelope.age.round(2).astype('str')
envelope.rename(columns={'sex_name':'sex'}, inplace=True)
envelope['sex'] = envelope.sex.apply(lambda x: x.lower())

def process_country_file(iso):

	print iso

	dfs = []
	errors = []
	for year in gbd.get_year_list():
		for sex in ['male','female']:

			try:
				df = pd.read_csv("%s/comos_%s_%s_%s.csv" % (counts_directory, iso, year, sex))
				df['age'] = df.age.round(2).astype('str')
				df['year'] = year
				df['iso3'] = iso
				df['sex'] = sex
				df = df.merge(envelope)
			
				num_simulants = df[['age','mean_people']].groupby('age').sum().reset_index()
				num_simulants.rename(columns={'mean_people':'num_simulants'}, inplace=True)
				df = df.merge(num_simulants)

				df['scaled_people'] = df['mean_people'] * df['pop_scaled'] / df['num_simulants']
				dfs.append(df)
			except Exception, e:
				dfs.append(pd.DataFrame(columns=['iso3','year','age','sex','num_diseases','scaled_people']))
				errors.append(e)
				print e

	dfs = pd.concat(dfs)

	return dfs[['iso3','year','age','sex','num_diseases','scaled_people']], errors

# Extract discrete bins
location_meta = gbd.get_locations(include_dev_status=True, include_locname=True)
isos = location_meta.local_id

pool = Pool(30)
chunksize = int(len(isos)/(30*2.))
compiled_counts = pool.map(process_country_file, isos, chunksize=chunksize)
pool.close()
pool.join()
pool.terminate()

errors = [ c[1] for c in compiled_counts ]
errors = list(itertools.chain(*errors))
compiled_counts = [ c[0] for c in compiled_counts ]

print 'Concatentating...'
compiled_counts = pd.concat(compiled_counts)
location_meta.rename(columns={'local_id':'iso3'}, inplace=True)
compiled_counts = compiled_counts.merge(location_meta, on='iso3')
compiled_counts.loc[compiled_counts.dev_status=='D1','plot_group'] = 'developed'
compiled_counts.loc[(compiled_counts.dev_status=='D0') & (compiled_counts.superregion!='S3'),'plot_group'] = 'developing no-SSA'
compiled_counts.loc[compiled_counts.superregion=='S3','plot_group'] = 'SSA'

# Create output directory
versioned_dir = "/home/j/WORK/04_epi/03_outputs/01_code/01_como/dev/condition_counts/v%s" % (como_version)
try: os.makedirs(versioned_dir)
except Exception, e: print e

# Collapse to global sums by year
print 'Collapsing global...'
global_by_year = compiled_counts[['year','num_diseases','scaled_people']].groupby(['year','num_diseases']).sum()
global_by_year = global_by_year.reset_index()

global_by_year[['year','num_diseases','scaled_people']].to_csv("%s/global_cond_counts.csv" % (versioned_dir), index=False)

# Collapse to global sums by year, age, and sex
print 'Collapsing global by age...'
global_by_yas = compiled_counts[['year','age','sex','num_diseases','scaled_people']].groupby(['year','age','sex','num_diseases']).sum()
global_by_yas = global_by_yas.reset_index()

global_by_yas[['year','age','sex','num_diseases','scaled_people']].to_csv("%s/global_cond_counts_yas.csv"  % (versioned_dir), index=False)

# Collapse to dev status by year, age, and sex
print 'Collapsing dev statuses...'
dev_by_yas = compiled_counts[['year','age','sex','plot_group','num_diseases','scaled_people']].groupby(['year','age','sex','plot_group','num_diseases']).sum()
dev_by_yas = dev_by_yas.reset_index()
dev_by_yas[['year','age','sex','plot_group','num_diseases','scaled_people']].to_csv("%s/dev_cond_counts_yas.csv"  % (versioned_dir), index=False)

# Collapse to dev status by year, age, and sex
print 'Collapsing specific locations...'
# Create output directory
location_dir = "/home/j/WORK/04_epi/03_outputs/01_code/01_como/dev/condition_counts/v%s/locations" % (como_version)
try: os.makedirs(location_dir)
except Exception, e: print e

# for l, df in compiled_counts.groupby('iso3'):
# 	print l
# 	df = df[['location_name','year','age','sex','plot_group','num_diseases','scaled_people']].groupby(['location_name','year','age','sex','plot_group','num_diseases']).sum()
# 	df = df.reset_index()
# 	df[['location_name','year','age','sex','plot_group','num_diseases','scaled_people']].to_csv("%s/%s_cond_count_yas.csv"  % (location_dir, l), index=False)

# 	os.system(' '.join(['R','<','figure_conditions_per_person.r','--no-save','--args',str(como_version), str(41), l]))