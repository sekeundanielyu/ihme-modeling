"""

Description: 

"""
import numpy as np
import scipy as sp
from scipy import stats
import pandas as pd
import os 
import scipy.spatial
#import pdb

thispath = os.path.dirname(__file__)
    
def mad(x):
    return stats.nanmedian(np.abs(x - stats.nanmedian(x)))

## Smoother Class
class Smoother: 
        
    def __init__(self, dataset, timevar='year', agevar='age', spacevar='ihme_loc_id', datavar='observed_data', modelvar='stage1_prediction', snvar=None, ssvar = 'cases'):
        
        self.gbd_ages = [0, 0.01, 0.1, 1]
        self.gbd_ages.extend(range(5,85,5))
        
        self.age_map = { value:idx for idx,value in enumerate(self.gbd_ages) }

        # No default age and time weights. Must be set explicitly.
        self.a_weights = None
        self.t_weights = None
        
        ## Assume an input data set with default variable names
        self.timevar = timevar
        self.agevar = agevar
        self.spacevar = spacevar     
        self.datavar = datavar
        self.modelvar = modelvar
        self.ssvar = ssvar
        self.snvar = snvar
        
        # Bind the data and stage 1 models, reogranizing for smoothing
        self.inputset = dataset 
        self.data = dataset.ix[pd.notnull(dataset[datavar])]
        self.stage1 = dataset.ix[pd.notnull(dataset[modelvar])].drop_duplicates()
        self.data.loc[:,'resid'] = self.data[self.datavar] - self.data[self.modelvar]
        #self.data.loc[:, 'resid'] = self.data[self.datavar].sub(self.data[self.modelvar], fill_value = 0)
        self.stage1 = self.stage1.sort([self.spacevar, self.agevar, self.timevar])

        # Default years / ages to predict
        self.p_startyear = np.min(self.stage1.year)
        self.p_endyear = np.max(self.stage1.year)
        
        self.p_ages = sorted(pd.unique(self.stage1[self.agevar]))
        self.results = pd.DataFrame(data={
            self.timevar: np.tile(range(self.p_startyear,self.p_endyear+1),len(self.p_ages)).T,
            self.agevar:  np.repeat(self.p_ages,self.p_endyear-self.p_startyear+1,axis=0)})
        
        # Set default smoothing parameters
        self.lambdaa=1.0
        self.omega=2
        self.zeta=0.9
        self.sn_weight=0.2
                
    # Generate time weights
    def time_weights(self, no_data = False):

        if(no_data == True):
            lambdaa = self.lambdaa_no_data
        else:
            lambdaa = self.lambdaa

        p_years = np.asanyarray([[i for i in range(self.p_startyear,self.p_endyear+1)]], dtype=float)
        o_years = np.asanyarray([self.data[self.timevar].values])
        
        # Pre-compute weights for each time-distance
        t_weights_lookup = {}
        for i in range(self.p_startyear,self.p_endyear+1):
            t_weights_lookup[i] = {}
            for j in range(self.p_startyear,self.p_endyear+1):
                t_weights_lookup[i][j] = (1 - (abs(float(i-j)) / (max(abs(i-self.p_startyear),abs(i-self.p_endyear))+1))**lambdaa)**3
            
        t_weights= sp.spatial.distance.cdist(p_years.T, o_years.T, lambda u, v: t_weights_lookup[u[0]][v[0]])
        self.t_weights = t_weights
        
        return t_weights
        
    # Generate age weights
    def age_weights(self):
        p_ages = np.asanyarray([ sorted([self.age_map[k] for k in self.p_ages]) ])
        o_ages = np.asanyarray([[ self.age_map[i] for i in self.data[self.agevar] ]])
        
        # Pre-compute weights for each age-distance
        a_weights_lookup = {}
        for i in range(0,np.int(np.max(self.age_map.values())-np.min(self.age_map.values())+2)):
            a_weights_lookup[i] = 1 / np.exp(self.omega*i)
            a_weights_lookup[-i] = a_weights_lookup[i]
        
        a_weights = sp.spatial.distance.cdist(p_ages.T, o_ages.T, lambda u, v: a_weights_lookup[u[0]-v[0]])
        self.a_weights = a_weights
        
        return a_weights
    
    # This will generate a spatial-relatedness matrix based on the GBD region/super-regions.  
    # Arbitrary spatial-relatedness matrices will be accepted by the space-weighting function, but they must be of this form.
    def gbd_spacemap(self,locs):
        
        gbd_regions = pd.read_csv("/home/j/WORK/07_registry/cancer/00_common/data/modeled_locations.csv")
        
        p_locs = pd.DataFrame([locs],columns=['ihme_loc_id'])
        o_locs = self.data[[self.spacevar]]
        
        # Make sure the data doesn't get misaligned, since the matrix lookups are not order invariant
        p_locs = pd.merge(p_locs,gbd_regions,left_on=self.spacevar,right_on='ihme_loc_id')
        o_locs.loc[:, 'data_order'] = o_locs.reset_index().index
        o_locs = pd.merge(o_locs,gbd_regions,left_on=self.spacevar,right_on='ihme_loc_id').sort('data_order').reset_index()
        
        in_country = (np.asmatrix(p_locs['location_id']).T==np.asmatrix(o_locs['location_id'])).astype(int)
        in_region = (np.asmatrix(p_locs['region_id']).T==np.asmatrix(o_locs['region_id'])).astype(int)
        in_sr = (np.asmatrix(p_locs['super_region_id']).T==np.asmatrix(o_locs['super_region_id'])).astype(int)
    
        spacemap = in_country + in_region + in_sr
        
        return np.array(spacemap)
        
    # This will generate a spatial-relatedness matrix based on the GBD region for subnational locations.  
    # Arbitrary spatial-relatedness matrices will be accepted by the space-weighting function, but they must be of this form.
    def gbd_subnl_spacemap(self,locs):
        
        gbd_regions = pd.read_csv("/home/j/WORK/07_registry/cancer/00_common/data/modeled_locations.csv")
        national_locations = gbd_regions.loc[~gbd_regions.ihme_loc_id.str.contains('_'),['ihme_loc_id', 'location_id']]
        national_locations.columns = ['parent_iso3', 'national_location_id']
        gbd_regions['parent_iso3'] = gbd_regions.ihme_loc_id[:3]        
        gbd_regions = pd.merge(gbd_regions, national_locations, how='left', on='parent_iso3')
        
        p_locs = pd.DataFrame([locs],columns=['ihme_loc_id'])
        o_locs = self.data[[self.spacevar]]
        
        # Make sure the data doesn't get misaligned, since the matrix lookups are not order invariant
        p_locs = pd.merge(p_locs,gbd_regions,left_on=self.spacevar,right_on='ihme_loc_id')
        o_locs.loc[:, 'data_order'] = o_locs.reset_index().index
        o_locs = pd.merge(o_locs,gbd_regions,left_on=self.spacevar,right_on='ihme_loc_id').sort('data_order').reset_index()
        
        in_subdiv = (np.asmatrix(p_locs['location_id']).T==np.asmatrix(o_locs['location_id'])).astype(int)
        in_country = (np.asmatrix(p_locs['national_location_id']).T==np.asmatrix(o_locs['national_location_id'])).astype(int)
        in_region = (np.asmatrix(p_locs['region_id']).T==np.asmatrix(o_locs['region_id'])).astype(int)
    
        spacemap = in_subdiv + in_country + in_region
        
        return np.array(spacemap)
#        
    # Generate spaceweights
    def space_weights(self, loc, no_data=False):
        
        self.time_weights(no_data)

        # Generate spatial weights based on the GBD regions/superregions
        if len(loc) != 3: 
            spacemap = self.gbd_subnl_spacemap(loc)
        else:
            spacemap = self.gbd_spacemap(loc)
            
        if (self.t_weights != None and self.a_weights != None):
            # Align time weights with a prediction space that is sorted by age group, then year
            t_weights = np.tile(self.t_weights.T,len(self.p_ages)).T
            
            # Align age weights with a prediction space that is sorted by age group, then year
            a_weights = np.repeat(self.a_weights,self.p_endyear-self.p_startyear+1,axis=0)
        
            weights = t_weights * a_weights
            
        elif self.t_weights!=None:
            t_weights = np.tile(self.t_weights.T,len(self.p_ages)).T
            weights = t_weights

        elif self.a_weights!=None:
            a_weights = np.repeat(self.a_weights,self.p_endyear-self.p_startyear+1,axis=0)
            weights = a_weights

        else:
            return None
        
        ## Set zeta based on data availability
        if (no_data == True):
            zeta = self.zeta_no_data
        else:
            zeta = self.zeta

        sp_weights = {  3: zeta,
                        2: zeta*(1-zeta),
                        1: (1-zeta)**2,
                        0: 0 }
            

        # Normalize to 1  
        normalized_weights = np.zeros(weights.shape)
        for spatial_group in np.unique(spacemap): 
            sp_grp_mask = (spacemap==spatial_group).astype(int)
           
           ## Add weights
            case_weights = self.data['cases']
            sp_grp_mask = np.multiply(sp_grp_mask, case_weights.values)

            # Add ss weights by element_wise vector multiplication to normalize by sample size
            if (np.sum(weights*sp_grp_mask)>0):
                normalized_weights = normalized_weights + (((sp_weights[spatial_group] * (weights*sp_grp_mask)).T / (np.sum(weights*sp_grp_mask,axis=1)))).T   
               
        self.final_weights = normalized_weights

        return normalized_weights
    
    # Add the weighted-average of the residuals back into the original predictions
    def smooth(self, locs=None):
        if locs==None:
            locs = pd.unique(self.stage1[self.spacevar])
            
        for location in locs:
            print location

            # Generate space weights
            if (len(self.data[self.data['ihme_loc_id'] == location]) == 0):
                self.space_weights(location, no_data = True)
            else:
                self.space_weights(location, no_data = False)
        
            # Smooth
            prior = self.stage1[(self.stage1[self.spacevar]==location)].drop_duplicates(subset=[self.timevar,self.agevar])[self.modelvar]
        
            smooth = np.array(prior) + np.sum(np.array(self.data['resid'])*self.final_weights, axis=1)
            
            self.results.loc[:, location] = smooth
        
        return smooth
        
    # Method to set ST parameters
    def set_params(self, params, values):
        for i,param in enumerate(params):
            self[param] = values[i]
    
    # Merge the ST results back onto the input dataset
    def format_output(self, include_mad=False):
        
        melted = pd.melt(self.results,id_vars=[self.agevar,self.timevar],var_name=self.spacevar,value_name='st_prediction')
        merged = pd.merge(self.inputset,melted,on=[self.agevar,self.timevar,self.spacevar],how='left')
        
        if include_mad:
            # Calculate residuals
            merged['st_resid'] = merged[self.datavar] - merged['st_prediction']
        
            # Calculate MAD estimates at various geographical levels
            mad_global = mad(merged.st_resid)
            mad_regional = merged.groupby('region_id').agg({'st_resid': mad}).reset_index().rename(columns={'st_resid':'mad_regional'})
            mad_national = merged.groupby('ihme_loc_id').agg({'st_resid': mad}).reset_index().rename(columns={'st_resid':'mad_national'})
            
            merged['mad_global'] = mad_global
            merged = pd.merge(merged,mad_regional,on="region_id",how="left")
            merged = pd.merge(merged,mad_national,on="ihme_loc_id",how="left")
            
            merged['mad_regional'].fillna(np.median(merged["mad_regional"]),inplace=True)
            merged['mad_national'].fillna(np.median(merged["mad_national"]),inplace=True)
        
        return merged