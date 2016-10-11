from __future__ import division
import pandas as pd
import numpy as np
import os
import sys
import pytest
import itertools
sys.path.append(os.getcwd())
from summarizers import pct_change, transform_metric, get_pop
from get_pct_change_helpers.metric import define_metric
from transmogrifier.gopher import draws


class TestMath(object):
    pop = get_pop({'year_id': [1990, 2015], 'sex_id': 1,
                   'age_group_id': 1, 'location_id': 1}).set_index('year_id')
    draw_cols = ['draw_%s' % i for i in xrange(1000)]

    def fake_data(self):
        df_list = []
        for year, val in {1990: 1, 2015: 2}.iteritems():
            draws = {'draw_%s' % i: val for i in xrange(1000)}
            d = {'location_id': 1, 'year_id': year,
                 'age_group_id': 1, 'sex_id': 1}
            d.update(draws)
            df = pd.DataFrame(d, index=[0])
            df_list.append(df)
        fake_data = pd.concat(df_list)
        return fake_data

    def test_pct_change_reg(self):
        df = self.fake_data()
        df = pct_change(df, 1990, 2015, 'pct_change')
        assert np.allclose(df[self.draw_cols], 1)

    def test_pct_change_arc(self):
        df = self.fake_data()
        df = pct_change(df, 1990, 2015, 'arc')
        assert np.allclose(df[self.draw_cols], 0.027726)

    def test_transform_metric_1to3(self):
        df = self.fake_data()
        df = transform_metric(df, to_id=3, from_id=1).set_index('year_id')
        assert np.allclose(df.ix[1990, self.draw_cols],
                           (1 / self.pop.ix[1990, 'pop_scaled']))
        assert np.allclose(df.ix[2015, self.draw_cols],
                           (2 / self.pop.ix[2015, 'pop_scaled']))

    def test_transform_metric_3to1(self):
        df = self.fake_data()
        df = transform_metric(df, to_id=1, from_id=3).set_index('year_id')
        assert np.allclose(df.ix[1990, self.draw_cols],
                           (1 * self.pop.ix[1990, 'pop_scaled']))
        assert np.allclose(df.ix[2015, self.draw_cols],
                           (2 * self.pop.ix[2015, 'pop_scaled']))


class TestInputs():
    '''Cycles through all possible inputs and verify different combos result
    in expected results/exceptions'''

    sources = ['dalynator', 'como', 'codem', 'epi', 'dismod', 'risk']
    metric_ids = [1, 2, 3]
    change_types = ['arc', 'pct_change_rate', 'pct_change_num']
    # make all combinations of metric_ids (of any length)
    all_metric_combos = []
    for i in xrange(1, len(metric_ids) + 1):
        els = [list(x) for x in itertools.combinations(metric_ids, i)]
        all_metric_combos.extend(els)

    def fake_data(self, metric_id=1):
        ''' return a dataframe of fake data in the shape that the
        pct change function expects. The df has one row per metric id
        specified '''
        metric_id = np.atleast_1d(metric_id)
        df_list = []
        for year, val in {1990: 1, 2015: 2}.iteritems():
            draws = {'draw_%s' % i: val for i in xrange(1000)}
            # makes one row per metric_id supplied
            d = {'location_id': [1 for i in metric_id],
                 'year_id': [year for i in metric_id],
                 'age_group_id': [1 for i in metric_id],
                 'sex_id': [1 for i in metric_id],
                 'metric_id': [m for m in metric_id]}
            d.update(draws)
            df = pd.DataFrame(d)
            df_list.append(df)
        fake_data = pd.concat(df_list)
        return fake_data

    @pytest.mark.parametrize("source,metric_id",
                             itertools.product(sources, metric_ids))
    def test_define_metric_input(self, source, metric_id):
        ''' run define_metric over all possible combinations of metric
        ids and sources and assert expected failures '''
        df = self.fake_data(metric_id)

        valid_sources = ['dalynator', 'como', 'codem', 'epi', 'dismod']
        if source not in valid_sources:
            with pytest.raises(AssertionError):
                define_metric(df, source)
        else:
            define_metric(df, source)

    def gen_inputs():
        ''' For all sources, generate an assortment of inputs that
        could be given to the pct_change function'''

        # wip
        test_input = ({'cause_ids': [294]},
                      [1],
                      [1],
                      1990,
                      2015,
                      [3],
                      'best',
                      'dalynator',
                      109,
                      [1, 2, 3],
                      [22],
                      'pct_change_num')
        return test_input

    args = ("gbd_id_dict, measure_ids, location_ids, start_year,"
            "end_year, sex_ids, status, source, version, metric_ids,"
            "age_group_ids, change_type")
    test_inputs = gen_inputs()

    @pytest.mark.parametrize(args, [test_inputs])
    def test_diff_input(self, gbd_id_dict, measure_ids, location_ids,
                        start_year, end_year, sex_ids, status, source, version,
                        metric_ids, age_group_ids, change_type):
        ''' run pct_change on all the different inputs given, and verify
        the results match the value obtained after manually doing the math on
        one draw
        (Or perhaps only validate inputs that we already know the answer
        to and can use a db lookup to compare?)'''
        # Get draws
        df = draws(
            gbd_id_dict,
            measure_ids=measure_ids,
            location_ids=location_ids,
            year_ids=[start_year, end_year],
            age_group_ids=age_group_ids,
            sex_ids=sex_ids,
            status=status,
            source=source,
            include_risks=True,
            version=version).reset_index(drop=True)
        # standardize all inputs by transforming everything to rate space
        df = define_metric(df, source)
        if 1 in df.metric_id.unique():
            df.loc[df.metric_id == 1] = transform_metric(
                df.loc[df.metric_id == 1], to_id=3, from_id=1)

        # calculate pct_change
        # drop any 2's. transform only 3's.
        if change_type == 'pct_change_num':
            df = transform_metric(df[df.metric_id == 3], to_id=1, from_id=3)
        if change_type in ['pct_change_rate', 'pct_change_num']:
            change_type = 'pct_change'
        change_df = pct_change(df, start_year, end_year, change_type)

        # validate change_df result here...
        return change_df
