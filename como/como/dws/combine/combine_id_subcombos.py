import pandas as pd
import MySQLdb

# Read dw file
standard_dws = pd.read_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/02_standard/dw.csv")
standard_dws = standard_dws.append(pd.read_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/combined_dws.csv"))

# Read in combinations map
combinations = pd.read_excel("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/01_code/combine_dws/id_subcombos_map.xlsx", sheetname="Sheet1")

# Combine DWs
drawcols = [ 'draw'+str(i) for i in range(1000) ]
combined_dws = []
for (healthstate, age_start, age_end), rows in combinations.groupby(['healthstate', 'age_start', 'age_end']):

	healthstates_to_combine = rows[['healthstates_to_combine','proportion']].merge(standard_dws, left_on='healthstates_to_combine', right_on='healthstate')

	print healthstates_to_combine

	# Reweight by specified proportions
	healthstates_to_combine.loc[:, drawcols] = (1 - (healthstates_to_combine.loc[:, drawcols].as_matrix()*healthstates_to_combine[['proportion']].as_matrix()))

	# Subset to draws for constituent healthstates
	draws_to_combine = healthstates_to_combine.filter(like='draw')

	# Combine using multiplicative equation
	combined_draws = 1 - draws_to_combine.prod()

	# Add to output data frame
	out_row = {'healthstate':healthstate, 'age_start':age_start, 'age_end':age_end}
	out_row.update(combined_draws)

	combined_dws.append(pd.DataFrame(data=[out_row]))

combined_dws = pd.concat(combined_dws)

# Merge on healthstate_ids
conn = MySQLdb.connect('strConn'))
healthstate_ids = pd.read_sql("SELECT healthstate, healthstate_id FROM healthstates WHERE cause_version=2", conn)
conn.close()

combined_dws = combined_dws.merge(healthstate_ids, how='left')

# Output to file
drawcols = ['draw'+str(i) for i in range(1000)]
col_order = ['healthstate_id','healthstate','age_start','age_end']
col_order.extend(drawcols)

combined_dws[col_order].to_csv("/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/combined_id_dws.csv", index=False)
combined_dws[col_order].to_csv("/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/combined_id_dws.csv", index=False)
