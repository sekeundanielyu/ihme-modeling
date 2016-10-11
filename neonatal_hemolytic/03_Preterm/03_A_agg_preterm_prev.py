######################################################################################################
## NEONATAL HEMOLYTIC MODELING
## PART 3: Preterm
## Part A: Prevalence of Preterm birth complications
## 6.18.14
## We get preterm birth prevalence by summing the birth prevalences we calculated for preterm in our 
## preterm custom models. 
#####################################################################################################

import pandas as pd
import os 

pd.set_option('display.max_rows', 10)
pd.set_option('display.max_columns', 10)

if os.path.isdir('J:/'):
	j = 'J:'
elif os.path.isdir('/home/j/'):
	j = '/home/j'
else:
	print 'Where am I supposed to go?'

working_dir = '%s/WORK/04_epi/02_models/01_code/06_custom/neonatal/data' %j

in_dir = '%s/02_analysis/neonatal_preterm/draws' %working_dir
out_dir = '%s/01_prep/neonatal_hemolytic/03_preterm' %working_dir

for group_idx in range(1,4):

	print "getting group %s" %group_idx

	fname = 'neonatal_preterm_ga%s_draws.csv' %group_idx

	print "reading data"
	bprev = pd.read_csv('%s/%s' %(in_dir, fname))

	#drop years before 1980
	bprev = bprev[bprev['year']>=1980]

	bprev = bprev.set_index(['iso3', 'location_id', 'year', 'sex'])

	print "adding"
	if group_idx==1:
		summed_bprev = bprev
	else:
		summed_bprev = summed_bprev + bprev

summed_bprev.sortlevel(inplace=True)

#replace draw 1000 with draw 0
try:
	summed_bprev.rename(columns={'draw_1000':'draw_0'}, inplace=True)
except:
	pass

print "saving final"
summed_bprev.to_csv('%s/preterm_aggregate_birth_prevalence.csv' %out_dir)



