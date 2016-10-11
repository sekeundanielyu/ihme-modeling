import numpy as np
import pandas as pd


def wtd_sum(opdf, index_cols, value_cols, weight_col, normalize='auto'):
    """Convenience wrapper for weighted summation in a DataFrame"""
    opdf = opdf.reset_index(drop=True)
    if normalize == 'auto':
        opdf[weight_col] = opdf.groupby(index_cols)[weight_col].transform(
            lambda x: x/x.sum())

    newvals = opdf[value_cols].values*opdf[[weight_col]].values
    newvals = pd.DataFrame(newvals, index=opdf.index, columns=value_cols)
    opdf.drop(value_cols, axis=1, inplace=True)
    opdf = opdf.join(newvals)
    return opdf.groupby(index_cols)[value_cols].aggregate(np.sum)


def wtd_mean(opdf, index_cols, value_cols, weight_col, normalize='auto'):
    """Convenience wrapper for weighted averaging in a DataFrame"""
    if normalize == 'auto':
        opdf[weight_col] = opdf.groupby(index_cols)[weight_col].transform(
            lambda x: x/x.sum())
    newvals = opdf[value_cols].values*opdf[[weight_col]].values
    newvals = pd.DataFrame(newvals, index=opdf.index, columns=value_cols)
    opdf.drop(value_cols, axis=1, inplace=True)
    opdf = opdf.join(newvals)
    return opdf.groupby(index_cols)[value_cols].aggregate(np.mean)


def aggregate(
        df, value_cols, index_cols=None, operator='sum',
        collapse_col=None, **kwargs):
    """
    Groups rows in df by the index_cols and aggregates the
    value_cols using the specified operator. If the operator requires
    additional arguments, they can be passed as kwargs.

    Arguments:
        df (DataFrame): The DataFrame to be aggregated
        value_cols (list): The list of columns containing values to be
                aggregated
        index_cols (list): Thie list of columns that specify grouped rows
        operator (str or function): Either a string specifying one of the
                built-in operations (sum, wtd_sum, or wtd_mean) or a
                function handle that defines how the value_cols should
                be aggregated.
        collapse_col (optional, str): Instead of specifying a set of
                index_cols, you can specify a single column to be "collapsed"
                across. The index_cols will be assumed to be any columns
                in df that aren't value_cols and aren't collapse_col.

    Returns:
        A DataFrame with one row per group (as defined by index_cols)
    """
    assert (index_cols is not None) or (collapse_col is not None), """
        Either index_cols or collapse_col must be specified"""
    assert not ((index_cols is not None) and (collapse_col is not None)), """
        Cannot specify both index_cols and collapse_col, choose one"""

    # Basically, force conversion of index and value args to lists
    [value_cols, index_cols] = map(
        lambda x: [x]
        if isinstance(x, basestring)
        else x, [value_cols, index_cols])

    if collapse_col is not None:
        assert isinstance(collapse_col, basestring), """Collapse column must be
            a string"""
        index_cols = list(set(df.columns)-set(value_cols+[collapse_col]))

    # Make a copy of the df to operate on, to protect against side-effects
    opdf = df.copy()
    # Operate!
    if operator == 'sum':
        return opdf.groupby(index_cols)[value_cols].aggregate(
            np.sum).reset_index()
    elif operator == 'wtd_sum':
        return wtd_sum(opdf, index_cols, value_cols, **kwargs).reset_index()
    elif operator == 'wtd_mean':
        return wtd_mean(opdf, index_cols, value_cols, **kwargs).reset_index()
    else:
        return opdf.groupby(index_cols)[value_cols].apply(
            operator, **kwargs).reset_index()
