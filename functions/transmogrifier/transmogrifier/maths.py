import pandas as pd
import numpy as np


def _scale(df, scalar):
    """ Scalar scaling function for apply usage """
    s = df.sum()
    s = s.replace({0: 1})
    return df/s.values*scalar


def _scale_series(df, scalar_series):
    """ Vector scaling function for apply usage """
    s = df.sum()
    s = s.replace({0: 1})
    return df/s.values*scalar_series.values


def scale(df, value_cols, group_cols=None, scalar=None, scalar_series=None,
          scalar_df=None):
    """
    Scales the value_cols of df so that their sum across rows is equal to
    the scalar or scalar series. Returns the scaled DataFrame, which has
    the same shape as df.

    Either a scalar or scalar_series must be provided, but not both.

    Arguments:
        df (DataFrame): The DataFrame to be scaled. Will not be modified.
        value_cols (list): The columns to be scaled.
        group_cols (list): The groups within which scaling should be
                applied. If a scalar_df is specified, this argument
                is required.
        scalar (number): The value to which the value_cols will be scaled.
        scalar_series (Series): A series of the same length as value_cols
                specifying what each value_col should be scaled to. Note that
                this is order dependent, i.e. the values must be in the same
                order as the value_cols to which they will be applied.
        scalar_df (DataFrame): A DataFrame whose value_cols specify
                what values each group should be scaled to. This is a
                convenience for calling merge_scale, see that function
                for more details.

    Returns:
        A scaled DataFrame having the same shape as df.
    """
    value_cols = np.atleast_1d(value_cols)
    if scalar is not None:
        scaled_df = df.copy()
        scaled_df = scaled_df.reset_index(drop=True)
        assert ~(scaled_df[value_cols] < 0).any().any(), """
            Can't scale values that are less than zero"""
        if group_cols is not None:
            scaled_df[value_cols] = scaled_df.groupby(group_cols)[
                    value_cols].apply(_scale, scalar)
        else:
            scaled_df[value_cols] = _scale(scaled_df[value_cols], scalar)

    elif scalar_series is not None:
        scaled_df = df.copy()
        scaled_df = scaled_df.reset_index(drop=True)
        assert ~(scaled_df[value_cols] < 0).any().any(), """
            Can't scale values that are less than zero"""
        if group_cols is not None:
            scaled_df[value_cols] = scaled_df.groupby(group_cols)[
                    value_cols].apply(_scale_series, scalar_series)
        else:
            scaled_df[value_cols] = _scale_series(
                    scaled_df[value_cols], scalar_series)

    elif scalar_df is not None:
        scaled_df = merge_scale(df, scalar_df, group_cols, value_cols)

    return scaled_df


def split(proportion_df, value_cols, series_to_split):
    """
    Splits the series_to_split across multiple rows based on the proportions
    specified in proportion_df. Returns a DataFrame of the same shape as
    proportion_df.

    Arguments:
        proportion_df (DataFrame): A DataFrame containing the proportions
                to apply to series_to_split.
        value_cols (list): The columns in proportion_df that contain the
                proportions to apply to series_to_split. This must be
                the same length as series_to_split.
        series_to_split (Series): The series_to_split, 'nuff said.

    Returns:
        A DataFrame which is basically just the product of proportion_df
        and series_to_split.
    """

    split_df = proportion_df.copy()
    split_df[value_cols] = split_df[value_cols]*series_to_split.values
    return split_df


def merge_scale(to_scale_df, scalar_series_df, group_cols, value_cols):
    """
    Scales groups of rows in to_scale_df to values specified in
    scalar_series_df. Retuns a DataFrame having the same shape as
    to_scale_df.

    Arguments:
        to_scale_df (DataFrame): The DataFrame to be scaled.
        scalar_series_df (DataFrame): A DataFrame whose rows are unique
                on group_cols, and whose value_cols specify the series
                to scale that group to.
        group_cols (list): The columns identifying the scaling groups
                in to_scale_df.
        value_cols (list): The columns to be scaled.

    Returns:
        A DataFrame whose groups are scaled to the values specified
        in scalar_series_df.
    """

    group_cols = list(np.atleast_1d(group_cols))
    assert len(scalar_series_df[group_cols].drop_duplicates()) == len(
            scalar_series_df), '''Group columns must uniquely identify
            rows in scalar_series_df'''
    scaled_df = merge_split(
            scalar_series_df, to_scale_df, group_cols, value_cols)
    return scaled_df


def merge_split(
        to_split_df, proportion_df, group_cols, value_cols, force_scale=True):
    """
    Splits rows in to_split_df based on proportions specified in
    proportion_df. The values of groups in proportion_df are
    automatically scaled to 1 before a split is applied, unless force_scale
    is explicitly set to False.
    Retuns a DataFrame having the same shape as proportion_df.

    Arguments:
        to_split_df (DataFrame): The DataFrame to be split, whose rows
                are unique on group_cols, and whose value_cols specify
                the proportions to split on.
        proportion_df (DataFrame): A DataFrame containing the proprtions
                to use to split out each group identified by group_cols
        group_cols (list): The columns identifying the groups
                in to_split_df.
        value_cols (list): The columns to be split / proportions to
                split to..
        force_scale (bool): Defaults to True. Sets whether the proportions
            will be forced to scale to 1 before application.

    Returns:
        A DataFrame whose groups are split according to the values
        specified in proportion_df.
    """
    if force_scale:
        this_proportion_df = scale(
                proportion_df, value_cols, group_cols=group_cols, scalar=1)
    else:
        this_proportion_df = proportion_df
    split_df = to_split_df[group_cols+value_cols].merge(
            this_proportion_df, on=group_cols, suffixes=('.x', '.y'))

    assert len(split_df) == len(proportion_df), '''Merge columns must uniquely
        specify rows in each of the input DataFrames'''

    x_cols = [vc+'.x' for vc in value_cols]
    y_cols = [vc+'.y' for vc in value_cols]

    split_df.reset_index(drop=True, inplace=True)
    join_df = pd.DataFrame(
            split_df[x_cols].values*split_df[y_cols].values,
            index=split_df.index,
            columns=value_cols)
    split_df = split_df.join(join_df)
    split_df = split_df[proportion_df.columns]
    return split_df


def interpolate(
        start_df, end_df, id_cols, time_col, value_cols,
        start_year, end_year, rank_df=None, interp_method='popgrowth'):
    """
    Interpolates the time period between start_df and end_df. Returns
    a DataFrame containing all the years between start_year and
    end_year.

    Arguments:
        start_df (DataFrame): DataFrame with starting values
        end_df (DataFrame): DataFrame with end of period values
        id_cols (list): List of column names which uniquely identify rows
                in start_df and end_df
        time_col (str): Column where the time value will be stored
                in the output DataFrame
        value_cols (list): List of columns with values to be interpolated
        start_year (int): Year corresponding to start_df's values
        end_year (int): Year corresponding to end_df's values
        interp_method (str): Interpolation method to use... right now,
                only 'popgrowth' is implemented:

                    rate = ln(value_t1/value_t0)/(t1-t0)

                Others TODO:

    Returns:
        A DataFrame whose value_cols contain the interpolated values
        for the period between start_df and end_df. The returned frame
        includes the values of start_df and end_df, re-ordered to match
        the specified reference.
    """
    id_cols = list(set(id_cols) - set([time_col]))
    if rank_df is None:
        rank_df = end_df.copy()
    assert (start_df[id_cols+value_cols].shape ==
            end_df[id_cols+value_cols].shape ==
            rank_df[id_cols+value_cols].shape), """
            start_df, end_df, and rank_df must be the same shape """

    start_df = start_df.sort(id_cols)
    end_df = end_df.sort(id_cols)
    rank_df = rank_df.sort(id_cols)
    assert ((start_df[id_cols] == end_df[id_cols]) &
            (start_df[id_cols] == rank_df[id_cols])).all().all(), """
            id_cols in start_df, end_df, and rank_df must be alignable"""
    start_mat = start_df[value_cols].values
    end_mat = end_df[value_cols].values
    rank_mat = rank_df[value_cols].values

    # Re-order draws based on the rank (reference) df
    ranks = np.argsort(rank_mat, axis=1)
    rank_order = np.argsort(ranks, axis=1)
    nrows, ncols = rank_mat.shape
    rows = np.tile(np.array(range(nrows)), (ncols, 1)).T
    start_mat.sort(axis=1)
    start_mat = start_mat[rows, rank_order]
    end_mat.sort(axis=1)
    end_mat = end_mat[rows, rank_order]

    t_df = start_df.sort(id_cols)
    t_df.reset_index(drop=True, inplace=True)
    t_df.drop(value_cols, axis=1, inplace=True)

    # Interpolate
    tspan = end_year-start_year
    if interp_method == 'popgrowth':
        start_mat[start_mat == 0] = 1e-12
        end_mat[end_mat == 0] = 1e-12
        r_mat = np.log(end_mat/start_mat)/tspan
    else:
        r_mat = np.log(end_mat/start_mat)/tspan

    interp_df = []
    for t in range(0, tspan+1):
        t_df = start_df.sort(id_cols)
        t_df.reset_index(drop=True, inplace=True)
        t_df.drop(value_cols, axis=1, inplace=True)
        join_df = pd.DataFrame(
                start_mat*np.exp(r_mat*t),
                index=t_df.index,
                columns=value_cols)
        t_df = t_df.join(join_df)
        t_df[time_col] = start_year+t
        interp_df.append(t_df)
    interp_df = pd.concat(interp_df)
    interp_df.reset_index(drop=True, inplace=True)
    return interp_df
