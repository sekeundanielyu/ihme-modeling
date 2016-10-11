import numpy as np
import pandas as pd
import MySQLdb

import sys
sys.path.append('/home/j/WORK/04_epi/02_models/01_code/02_severity/01_code/prod')
import gbd_utils
gbd = gbd_utils.GbdConventions()

# Read dw file
standard_dws = pd.read_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv")
gen_med_dw = standard_dws[standard_dws.healthstate=="generic_medication"]

# Get % symptomatic urolithiasis to apply to generic_medication
symp_urolith_prop = pd.read_csv("/home/j/WORK/04_epi/01_database/02_data/urinary_urolithiasis/04_models/gbd2013/chronic_urolithiasis_DW_iso3_distribution.csv")
symp_urolith_prop = symp_urolith_prop[symp_urolith_prop.year.isin([1990,1995,2000,2005,2010,2013])].reset_index(drop=True)

# Draw generation function
def beta_draws(row):
	row = pd.DataFrame([row])
	sd = abs((row.upper - row.lower)/(2*1.96))
	mean = row.proportion_dw
	sample_size = mean*(1-mean)/sd**2
	alpha = mean*sample_size
	beta = (1-mean)*sample_size
	draws = pd.Series(np.random.beta(alpha, beta, size=1000))

	return draws

# Generate proportion draws
prop_draws = symp_urolith_prop.apply(beta_draws, axis=1)

# Multiply DW draws by proportions 
weighted_dws = pd.DataFrame(gen_med_dw.filter(like='draw').as_matrix() * prop_draws.as_matrix())
weighted_dws.columns = ['draw'+str(i) for i in range(1000)]

# Format output and write to file
symp_urolith_prop = symp_urolith_prop.join(weighted_dws)
symp_urolith_prop = symp_urolith_prop.merge(gbd.get_locations()[['location_id','local_id']])

symp_urolith_prop['healthstate'] = "urolith_symp"
symp_urolith_prop['healthstate_id'] = 822
symp_urolith_prop = symp_urolith_prop[['local_id','year','healthstate_id','healthstate']+['draw'+str(i) for i in range(1000)]]
symp_urolith_prop.rename(columns={'local_id':'iso3'}, inplace=True)
symp_urolith_prop.to_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/urolith_symp_dws.csv", index=False)
symp_urolith_prop.to_csv("/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/urolith_symp_dws.csv", index=False)