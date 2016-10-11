import operator
import numpy as np

"""
All helper functions in this file return a tuple:
    (test result, additional info about failures)
"""


def has_all_draw_cols(df):
    dcs = ['draw_%s' % i for i in range(1000)]
    return (len(set(dcs)-set(df.columns)) == 0, list(set(dcs)-set(df.columns)))


def has_valid_range(
        df,
        val_cols,
        lower=-np.inf,
        upper=np.inf,
        lower_inclusive=True,
        upper_inclusive=True):

    if lower_inclusive:
        lo = operator.le
    else:
        lo = operator.lt
    if upper_inclusive:
        uo = operator.ge
    else:
        uo = operator.gt
    return (
            (uo(df[val_cols], lower) & lo(df[val_cols], upper)).all().all(),
            '')


def has_no_null_values(df, val_cols):
    return (df[val_cols].notnull().all().all(), '')


def has_all_demographic_combos(df):
    pass

def has_all_locations(dir, location_set_id):
    pass


def has_all_years(df):
    pass


def has_all_age_groups(df):
    pass


def has_all_sexes(df):
    pass
