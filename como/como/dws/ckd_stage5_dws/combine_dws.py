import pandas as pd
from multiprocessing import Pool
import sys
sys.path.append("/home/j/WORK/04_epi/02_models/01_code/02_severity/01_code/prod")
import gbd_utils
gbd = gbd_utils.GbdConventions()

# Load population files
pop = pd.read_csv("/snfs3/WORK/02_mortality/04_outputs/02_results/envelope.csv")
pop = pop[['iso3','year','age','sex','pop_scaled']]
pop['age'] = pop.age.round(2).astype('str')

# Load excess mortality draws
dfs = []
for l in gbd.get_locations().local_id:
	for s in ['male','female']:
		for y in [2013]:

			print l, s, y

			df = pd.read_csv("/snfs3/WORK/04_epi/02_models/02_results/ckd/stage5/_parent/33315/draws/mtexcess_%s_%s_%s.csv" % (l,y,s))
			
			df['iso3'] = l
			df['year'] = y
			if s=='male':
				df['sex'] = 1
			else:
				df['sex'] = 2
			
			df = df[df.age<=80]
			dfs.append(df)

dfs = pd.concat(dfs)
dfs['age'] = dfs.age.round(2).astype('str')

# Merge pops and get global average duration
dfs = dfs.merge(pop)
for c in dfs.filter(like='draw').columns:
	dfs[c] = dfs[c]*dfs['pop_scaled']

durs = dfs.groupby(['year']).sum().reset_index()
for c in durs.filter(like='draw').columns:
	# Duration is 1/em in this case
	durs[c] = 1/(durs[c]/durs['pop_scaled'])

# Get DW draws
dws = pd.read_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv")
dws = dws[dws.healthstate.isin(['cancer_terminal_untr','ckd_iv'])]

ckd4_prop = durs.copy()
term_prop = durs.copy()
# Get proportions CKD4 vs terminal
for c in durs.filter(like='draw').columns:
	term_prop[c] = (2/12.)/durs[c]
	ckd4_prop[c] = 1-term_prop[c]

	term_prop.clip(upper=1)
	ckd4_prop[c].clip(lower=0)

ckd4_dw = ckd4_prop.copy()
term_dw = term_prop.copy()
for i in [ str(s) for s in range(1000)]:
	ckd4_dw['draw_'+i] = ckd4_dw['draw_'+i] * dws.ix[dws.healthstate=='ckd_iv', 'draw'+i].values[0]
	term_dw['draw_'+i] = term_dw['draw_'+i] * dws.ix[dws.healthstate=='cancer_terminal_untr', 'draw'+i].values[0]

combined_dw = ckd4_prop.copy()
for c in combined_dw.filter(like='draw').columns:
	combined_dw[c] = ckd4_dw[c] + term_dw[c]
combined_dw['mean'] = combined_dw.filter(like='draw').mean(axis=1)
combined_dw['sd'] = combined_dw.filter(like='draw').std(axis=1)

pd.melt(combined_dw, ['year','sex','mean','sd','pop_scaled']).to_csv('combined_dw_draws.csv', index=False)