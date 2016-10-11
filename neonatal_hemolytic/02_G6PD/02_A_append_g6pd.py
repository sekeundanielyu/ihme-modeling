######################################################################################################
## NEONATAL HEMOLYTIC MODELING
## PART 2: G6PD
## Part A: Prevalence of G6PD
## 6.9.14

## We get G6PD prevalence from the GBD Dismod models of congenital G6PD (modeled by Nick Kassebaum in
## GBD2013).  This script simply finds the outputs for the Dismod model number Nick gave me, and 
## appends them all into one big dataset for use in my later code.  
#####################################################################################################

import pandas as pd 
import os 
import sys
import re

pd.set_option('display.max_rows', 10)
pd.set_option('display.max_columns', 10)

#############
## SETUP
#############

model_id = 9264

## where do the dismod outputs live? 
small_file_dir = '/clustertmp/WORK/04_epi/02_models/02_results/hemog_g6pd/cases/_asymp/%s/draws' %model_id

## useful regex function to return a matched string if such a string exists, and an empty string otherwise
def find_thing(string, regex):
	hunt = re.compile(regex)
	find = hunt.search(string)
	try:
		found = find.group() 
	except:
		found = ''
	return found

#############
## APPENDING
#############

# find and count elements of the directory
# note that this file will contain much more than just prevalence 
# (also incidence, etc), and that later in the script we specify 
# that it's just prevalence we want
file_list = os.listdir(small_file_dir)
file_count = len(file_list)

print "%s files found in file!" %file_count

#set up empty dataframe onto which you will append all these files
all_files = pd.DataFrame()

#ok, here we go with the looping
for file_idx, filen in enumerate(file_list):

	if not filen.startswith('prevalence'):
		file_idx +=1
		continue

	if file_idx%100==0:
		print "file %d of %d" %(file_idx, file_count)

	#regex to extract all the values we want from the file name
	iso3 = find_thing(filen, '[A-Z]{3}')
	year = find_thing(filen, '[1-2][0-9]{3}' )
	location_id = find_thing(filen, '[3-5][0-9]{2,3}')
	sex = find_thing(filen, '(fe)?male')

	#create new dataframe
	new_df = pd.read_csv('%s/%s' %(small_file_dir, filen))

	new_df['year'] = int(year)
	new_df['sex'] = sex

	#if this is a subnational, we want the iso3 to be of the format 
	# "{parent_iso3}_{location_id}"
	if location_id!='':
		new_df['iso3'] = iso3 + "_" + location_id
	else:
		new_df['iso3'] = iso3

	#this is a check to make sure there isn't something weird about the column format of the smaller dataset
	complete_cols = set(all_files.columns)
	new_df_cols = set(new_df.columns)

	if (complete_cols!= new_df_cols) and (complete_cols!=set()):
		print 'COLUMN MISMATCH FOR %s' %filen
		BREAK

	#append to big file
	all_files = all_files.append(new_df)

#get rid of all age>0
all_files = all_files[all_files['age']==0]
all_files.drop('age', axis=1, inplace=True)

#make sex numeric
all_files['sex'] = all_files['sex'].map({'male':1, 'female':2})

all_files = all_files.set_index(['iso3', 'year', 'sex'])
all_files = all_files.sortlevel()

#get rid of india subnats
try:
	all_files.drop(['IND_4637', 'IND_4638'], inplace=True)
except:
	pass

out_dir = '/home/j/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/01_prep/neonatal_hemolytic/02_g6pd'

all_files.to_csv('%s/g6pd_model_%s_prev.csv' %(out_dir, model_id))


