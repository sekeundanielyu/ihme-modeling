# Functions for accessing dalynator hdf draws
import pandas as pd
import re
import os
import multiprocessing as mp
from functools import partial

# Code is designed to read files based on this specification.
# Should make it easier to add new sources -- just need to create new spec
dalynator_spec = {'prefix': 'draws',
                  'extension': 'h5',
                  'sep': '_',
                  'key': 'data',
                  'name_cols': ['location_id', 'year_id'],  # ordering matters
                  'query_cols': ['location_id',  # ordering doesn't matter
                                 'year_id',
                                 'age_group_id',
                                 'sex_id',
                                 'cause_id',
                                 'rei_id',
                                 'metric_id',
                                 'measure_id']}


def read_files(file_list, spec, **kwargs):
    ''' given list of files, draw spec, and any optional columns to
    query/constrain, read all relevant draws into memory.

    If num_workers specified, can use multiprocessing to speed up I/O

    Returns:
        Dataframe
    '''
    regex = re.compile(build_file_regex(spec, **kwargs))
    where = make_where_clause(spec, **kwargs)
    matching_files = [f for f in file_list if regex.match(f.split('/')[-1])]
    if not matching_files:
        raise RuntimeError(
            'No files found matching regex {} (ie {})'.format(
                regex.pattern, file_list[0]))

    if kwargs.get('verbose'):
        print 'found {} files to query'.format(len(matching_files))
        print 'using the following constraints per file: {}'.format(where)

    # need to curry read_hdf because Pool.map only exceptions functions
    # with one argument
    curried_read_hdf = partial(pd.read_hdf, key=spec['key'], where=where)
    curried_read_hdf = partial(read_file, curried_read_hdf, spec)

    # Possibly read files concurrently, if num_workers specified
    # otherwise read serially
    num_workers = kwargs.get('num_workers')
    if num_workers:
        pool = mp.Pool(int(num_workers))
        df_list = pool.map(curried_read_hdf, matching_files)
        pool.close()
        pool.join()
        return pd.concat(df_list)
    else:
        return pd.concat([curried_read_hdf(f) for f in matching_files])

def read_file(read_func, spec, f):
    ''' Since sometimes a file is missing a column (ie, como and measure_id)
        We'll need to check it all ids in file name are included in column
        headers. If not, add them
    '''
    # use draw spec to get columns present in file name, and their position in
    # the file name
    column_idx = {col: idx for idx, col in enumerate(spec['name_cols'])}
    column_vals = f.split('/')[-1].split(spec['sep'])

    df = read_func(f)
    for col in column_idx.keys():
        if col not in df.columns:
            df[col] = column_vals[column_idx[col]]
    return df

def make_where_clause(spec, **kwargs):
    """ given draw_file specification and column with values to keep, build up a
    where clause

    IE {'location_id': [1],
        'age_group_id': [2]} -> 'location_id in 1 and age_group_id in 2'}

    Returns:
        string
    """
    where = []
    for col_to_query in spec['query_cols']:
        ids = kwargs.get(col_to_query)
        if ids:
            where.append('{} in [{}]'.format(col_to_query,
                                             ','.join([str(i) for i in ids])))

    # If boolean include_risks is false, then failing to
    # specify rei_id means you don't want attributable results.
    # Otherwise, it means you want all rei results
    if not kwargs.get('rei_id') and not kwargs.get('include_risks'):
        where.append('rei_id == 0')

    return " & ".join(where)


def build_file_regex(spec, **kwargs):
    """
    given a  description of how the files are indexed/named,
    and a set of colums to query, create a regex
    that matches files we intend to query

    Returns:
        string
    """

    prefix = spec['prefix']
    extension = spec['extension']
    sep = spec['sep']

    # [1,2] -> "(1|2)" if column is in kwargs, otherwise match any id
    id_regexes = ('(' + '|'.join(map(str, kwargs[col])) + ')'
                  if col in kwargs else '([0-9]*)' for col in spec['name_cols'])

    if prefix:
        full_regex = prefix + sep + sep.join(id_regexes) + '.' + extension
    else:
        full_regex = sep.join(id_regexes) + '.' + extension

    return full_regex


def draws(**kwargs):
    ''' given a dalynator version id and columns/values to constrain,
    read all h5s and return a dataframe

    arguments:
        any columns you with to constrain with (ie cause_ids=[294])

    Returns:
        dataframe
    '''
    # if a specific version is specified, ignore status
    if 'version' in kwargs:
        version = kwargs['version']
    else:
        version = find_dalynator_version(kwargs.get('status', 'best'))

    draw_dir = '/share/central_comp/dalynator/{}/draws/hdfs'.format(version)

    # if columns are specified as plural, strip off trailing 's' so that we can
    # build a query using proper name (ie sex_ids -> sex_id)
    for key in kwargs.keys():
        if key.endswith('_ids') and kwargs[key]:
            # update key so it's missing trailing s if it's not the empty list
            kwargs[key[0:-1]] = kwargs.pop(key)

    # files are stored like draw_dir/loc_id/file_name.h5
    if kwargs.get('location_id'):
        location_dirs = [os.path.join(draw_dir, str(loc_id))
                         for loc_id in kwargs['location_id']]
    else:
        location_dirs = [os.path.join(draw_dir, d)
                         for d in os.listdir(draw_dir)]
    files = [os.path.join(location_dir, f) for location_dir in location_dirs
             for f in os.listdir(os.path.join(draw_dir, location_dir))]
    df = read_files(files, dalynator_spec, **kwargs)

    return df


def find_dalynator_version(status='best'):
    '''
        if Status is "best", return dalynator version id
        associated with compare_version_id currently marked best.

        If status is "latest", return dv_id associated with most recent
        gbd.compare_version marked best or active

        Note that latest version could be best version
    '''
    from gopher import query
    assert status == 'best' or status == 'latest', ("status should be best "
                                                    "or latest")

    # get best or latest compare_version_id
    if status == 'best':
        q = """
        select
        compare_version_id
        from gbd.compare_version
        where
        gbd_round_id = 3
        and
        compare_version_status_id = 1"""
        result = query("gbd", q)
        if result.empty:
            raise RuntimeError('no best compare_version found')
    elif status == 'latest':
        q = """
        SELECT
        compare_version_id
        from gbd.compare_version
        where
        gbd_round_id = 3
        and
        compare_version_status_id in (1, 2)
        order by date_inserted desc
        limit 1"""
        result = query("gbd", q)
        if result.empty:
            raise RuntimeError('No compare versions marked latest or best')
    cv_id = result.compare_version_id.item()

    # given a cv_id, find the dv_id
    q = """select distinct(val) as dalynator_version_id
    from
    gbd.gbd_process_version_metadata gpvm
    join
    gbd.gbd_process_version gpv using (gbd_process_version_id)
    join
    gbd.compare_version_output cvo using (gbd_process_version_id)
    where
    cvo.compare_version_id = {}
    and
    gpvm.metadata_type_id = 5 """.format(cv_id)
    try:
        res = query("gbd", q)
        dv_id = int(res.dalynator_version_id.item())
    except ValueError as e:
        raise RuntimeError(
            ("Either 0 or more than one dalnator_version found for "
             "compare_version {}, (found {})".format(
                 cv_id, str(res.dalynator_version_id.tolist()))))

    return dv_id
