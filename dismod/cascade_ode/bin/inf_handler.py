import os
import pandas as pd
from warnings import warn

inf = float('inf')

def float_inf(df):
    "Converts _inf (type str) df items to -inf (type float)"
    for k in df:
        if df[k].dtype == object and any(df[k] == '_inf'):
            tmp = df[k].replace('_inf', -inf).astype(float)
            try:
                df[:,k] = tmp
            except:
                warn("Could not convert '%s' to type 'float'" % (k,))
    return df

def object_inf(df):
    "Converts -inf (type float) df items to '_inf' (type str)"
    for k in df:
        if df[k].dtype == float and any(df[k] == -inf):
            try:
                tmp = df[k].replace(-inf,'_inf').astype(object)
                df.loc[:,k] = tmp
            except Exception, ex:
                warn("Could not convert '%s' to type 'object'" % (k,))
                raise
    return df

if __name__ == '__main__':
    d = {'lower' : pd.Series([1., 2., 3.], index=['a', 'b', 'c']),
         'upper' : pd.Series([5., '_inf', 3.], index=['a', 'b', 'c'])}
    df = pd.DataFrame(d)
    df = float_inf(df)
    assert (object not in df.dtypes), "Forward conversion failed."
    df = object_inf(df)
    print df.dtypes










