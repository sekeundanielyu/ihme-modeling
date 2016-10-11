# # Spike Detection for Shocks causes
#
# Purpose: Detect spikes in time series data by measuring pct diff between
# points

import pandas as pd
import numpy as np
from itertools import islice


# #####DeathTriangle class for calculating pct diff of three points
class DeathTriangle:
    ''' Functions to run on points of three in a time series'''

    # a dictionary of dictionaries from year to deaths
    deaths_dict = {}
    # a sorted list of the three years in the death triangle
    ordered_years = []
    avg_deaths = 0
    threshold = 0
    pct_diff = 0

    def __init__(self, deaths_dict, threshold):
        # there must be only three points in a triangle
        assert len(deaths_dict) == 3
        for death_count in deaths_dict.values():
            # just make sure the deaths are positive
            assert death_count >= 0
        for year in deaths_dict.keys():
            # just make sure it looks like a year
            assert year >= 1900 & year <= 2050
        self.deaths_dict = deaths_dict
        self.threshold = threshold

        self.ordered_years = sorted(deaths_dict.keys())
        self.avg_deaths = self.__calc_avg_deaths()
        self.pct_diff = self.calc_pct_diff()

    def get_years(self):
        ''' return the sorted list of years in the triangle'''
        return self.ordered_years

    def set_threshold(self, t):
        ''' set the threshold used for calculating if this is a spike '''
        self.threshold = t

    def calc_pct_diff(self):
        """Calculate the percent difference between mid year and neighbors"""
        y1 = self.ordered_years[0]
        y2 = self.ordered_years[1]
        y3 = self.ordered_years[2]
        d1 = self.deaths_dict[y1]
        d2 = self.deaths_dict[y2]
        d3 = self.deaths_dict[y3]
        diff1 = (d2 - d1) / d1
        diff2 = (d2 - d3) / d3
        return min(diff1, diff2)

    def is_spike(self, spike_type='pct'):
        ''' Its a spike if it is over the threshold'''
        return self.pct_diff > self.threshold

    def get_vertex_year(self):
        """Get the middle year"""
        return self.ordered_years[1]

    def __calc_avg_deaths(self):
        ''' calculate the average deaths in the dataset '''
        total_deaths = 0.0
        num_years = 1.0 * len(self.ordered_years)
        for year in self.ordered_years:
            total_deaths = total_deaths + self.deaths_dict[year]
        avg = total_deaths / num_years
        assert avg > 0
        return avg


# define query grabber
execfile('db_tools.py')


def get_data_for_cause_location(acause, location_id):
    query = '''
        SELECT
            acause,
            sex_id as sex,
            year_id as year,
            age_group_id as age,
            cf_raw,
            cf_corr,
            cf_rd,
            cf_final,
            sample_size
        FROM
            cod.cm_data
        INNER JOIN
            cod.cm_data_version dv USING(data_version_id)
        INNER JOIN
            shared.cause USING (cause_id)
        WHERE
            dv.status = 1
            AND dv.data_type_id=9
            AND age_group_id=22
            AND sex_id BETWEEN 1 AND 2
            AND year_id BETWEEN 1980 AND 2014
            AND acause='{a}'
            AND location_id={l}
    '''.format(a=acause, l=location_id)
    data = queryToDF(query)
    return data


acauses = ['inj_mech_other', 'inj_fires', 'inj_trans_other',
           'inj_trans_road_4wheel', 'inj_poisoning']

locations = sorted(list(pd.read_csv(
    'completeness_groups.csv').query('group==1').ihme_loc_id.unique()))
for ihme_loc_id in locations:
    for acause in acauses:
        location_id = queryToDF('''
            SELECT location_id
            FROM shared.location_hierarchy_history
            WHERE ihme_loc_id="{}"
            AND location_set_version_id=69'''.format(
            ihme_loc_id)).ix[0, 'location_id']
        data = get_data_for_cause_location(acause, location_id)
        if len(data) <= 0:
            continue
        # create deaths column out of sample size
        data['deaths'] = data['cf_final'] * data['sample_size']
        # the percentage difference between a point and its two neighbors that
        # justifies an outlier
        threshold = .40
        # create a dictionary of year to deaths
        # currently only looks at the aggregate of all ages and both sexes
        time_series = dict(pd.pivot_table(
            data, index='year', values='deaths', aggfunc=np.sum))
        if len(time_series) >= 3 and max(time_series.values()) >= 50:
            for i in range(3, len(time_series) + 1):
                input = {j: time_series[j] for j in islice(
                    iter(sorted(time_series)), i - 3, i)}
                dt = DeathTriangle(input, threshold)
                if dt.is_spike() and dt.avg_deaths > 10:
                    # each output is an outlier, to be set in the cod database
                    print "{l},{a},{y},{i},{p}".format(
                        l=ihme_loc_id,
                        a=acause,
                        y=dt.get_vertex_year(),
                        i=input,
                        p=dt.pct_diff)
