import pandas as pd

# Read in compiled draw files
epi_draws = pd.read_csv("/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/epilepsy_any_dws.csv")
epi_combo_draws = pd.read_csv("/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/combined_epilepsy_dws.csv")
epi_draws = epi_draws.append(epi_combo_draws)

# Directories to write to
save_dirs = ["/home/j/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/epilepsy_by_country", "/clustertmp/WORK/04_epi/03_outputs/01_code/02_dw/03_custom/epilepsy_by_country"]

# Columns to output
drawcols = ['draw'+str(i) for i in range(1000)]
col_order = ['iso3','year','healthstate_id','healthstate']
col_order.extend(drawcols)

for iso_year, df in epi_draws.groupby(['iso3','year']):
	iso3 = iso_year[0]
	year = iso_year[1]

	print '%s %s' % (iso3, year)
	for save_dir in save_dirs:
		df[col_order].to_csv('%s/epilepsy_dws_%s_%s.csv' % (save_dir, iso3, year), index=False)