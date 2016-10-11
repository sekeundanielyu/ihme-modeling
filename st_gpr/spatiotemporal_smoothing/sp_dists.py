###########################################################
### Project: ubCov
### Purpose: Generate spatial distances
###########################################################

import pandas as pd
import numpy as np
from hierarchies import dbtrees


def calc_spatial_distances(location_set_version_id, o_locs, level):	
	o_locs = np.atleast_1d(o_locs).ravel()
	lflat = pd.read_csv("/home/j/WORK/01_covariates/common/ubcov_central/_modules/04_model/_db/level_hierarchy.csv")
	lflat = lflat[['location_id', 'level_0', 'level_1', 'level_2', 'level_3', 'level_4', 'level_5']]
	lflat = lflat.rename(columns= {'location_id':'leaf_node'})

	leaf_lvls = []
	for lvl in range(3,level+1):
		leaf_lvls.append(lvl)
	leaf_lvls.reverse()

	o_locdf = pd.DataFrame({'leaf_node': o_locs})
	o_locdf = o_locdf.merge(lflat, on='leaf_node')
	d_df = []
	for lvl in leaf_lvls:
		leaf_df = lflat[lflat['level_%s' % lvl].notnull()]
		d0_locs = (
			np.atleast_2d(leaf_df['level_%s' % lvl].values).T ==
			np.atleast_2d(o_locdf['level_%s' % lvl].values)).astype(int)
		d_locs = d0_locs
		d1_locs = (
			np.atleast_2d(leaf_df['level_%s' % (lvl-1)].values).T ==
			np.atleast_2d(o_locdf['level_%s' % (lvl-1)].values)).astype(int)
		d_locs = d_locs + d1_locs
		d2_locs = (
			np.atleast_2d(leaf_df['level_%s' % (lvl-2)].values).T ==
			np.atleast_2d(o_locdf['level_%s' % (lvl-2)].values)).astype(int)
		d_locs = d_locs + d2_locs
		if lvl > 3:
			d3_locs = (
				np.atleast_2d(leaf_df['level_%s' % (lvl-3)].values).T ==
				np.atleast_2d(o_locdf['level_%s' % (lvl-3)].values)).astype(int)
			d_locs = d_locs + d3_locs
		if lvl > 4:
			d4_locs = (
				np.atleast_2d(leaf_df['level_%s' % (lvl-4)].values).T ==
				np.atleast_2d(o_locdf['level_%s' % (lvl-4)].values)).astype(int)
			d_locs = d_locs + d4_locs
		d_df.append(pd.DataFrame(
				d_locs.T, columns=leaf_df['level_%s' % lvl].values,
				index=o_locs))

	d_df = pd.concat(d_df, axis=1)
	d_df = d_df.fillna(0)
	
	return d_df
