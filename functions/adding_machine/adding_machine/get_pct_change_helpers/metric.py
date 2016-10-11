# functions related to metric id transformations
import pandas as pd
import os


def define_metric(df, source):
    """Add metric_id to the df if it isn't already in there"""
    valid_sources = ['dalynator', 'codem', 'epi', 'como', 'dismod']
    assert source in valid_sources, "Must pass one of %s" % valid_sources
    if 'metric_id' not in df.columns:
        met_map = pd.read_csv('%s/bin/get_pct_change_helpers/'
                              'source_metric_map.csv'
                              % os.path.dirname(os.path.dirname(
                                  os.path.dirname(os.path.abspath(__file__)))))
        metric_id = met_map.set_index('source').ix['%s' % source, 'metric_id']
        df['metric_id'] = metric_id
    df = df.sort_values(by='metric_id').reset_index(drop=True)
    return df

