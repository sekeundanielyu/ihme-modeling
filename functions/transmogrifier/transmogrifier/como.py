from dalynator import read_files
import pandas as pd
import os


# defines how to read cause level h5 files
cause_spec = {'prefix': None,
              'extension': 'h5',
              'sep': '_',
              'key': 'draws',
              # ordering matters for name_cols
              'name_cols': ['measure_id', 'location_id', 'year_id',
                            'sex_id'],
              'query_cols': ['location_id',  # ordering doesn't matter
                             'year_id',
                             'age_group_id',
                             'sex_id',
                             'cause_id']}


def copy_dict(source_dict, diffs):
    """Returns a copy of source_dict, updated with the new key-value
       pairs in diffs.

       Used to update draw specs that are very similar"""
    result = dict(source_dict)
    result.update(diffs)
    return result


def make_other_draw_specs(cause_spec):
    ''' rei and sequela level draw specs are almost identical to
        cause spec, with a few differences in query cols'''
    # rei spec is cause spec with rei_id added to query_cols
    rei_spec = copy_dict(cause_spec,
                         {'query_cols': cause_spec['query_cols'] + ['rei_id']})

    # sequela spec is cause spec with sequela_id added to query_cols and
    # cause_id removed
    seq_query_cols = [col for col
                      in cause_spec['query_cols'] if col != 'cause_id']
    seq_query_cols = seq_query_cols + ['sequela_id']
    seq_spec = copy_dict(cause_spec,
                         {'query_cols': seq_query_cols})
    return rei_spec, seq_spec


def draws(**kwargs):
    ''' given a como version id and columns/values to constrain,
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
        version = find_como_version(kwargs.get('status', 'best'))

    kwargs.update({'include_risks': True})

    # create rei and sequela specs from cause spec
    rei_spec, seq_spec = make_other_draw_specs(cause_spec)

    # if columns are specified as plural, strip off trailing 's' so that we can
    # build a query using proper name (ie sex_ids -> sex_id)
    for key in kwargs.keys():
        if key.endswith('_ids') and kwargs[key]:
            # update key so it's missing trailing s if it's not the empty list
            kwargs[key[0:-1]] = kwargs.pop(key)

    base_dir = '/ihme/centralcomp/como/{}/draws'.format(version)

    rei_and_cause_args = copy_dict(kwargs, {'sequela_id': []})
    sequela_args = copy_dict(kwargs, {'cause_id': [], 'rei_id': []})

    df_list = []
    for key in ['cause_id', 'rei_id', 'sequela_id']:
        if kwargs.get(key):
            files = get_files(key, os.path.join(base_dir, key[0:-3]))
            if key == 'sequela_id':
                df_list.append(read_files(files, seq_spec, **sequela_args))
            elif key == 'rei_id':
                df_list.append(read_files(files, rei_spec,
                                          **rei_and_cause_args))
            elif key == 'cause_id' and not kwargs.get('rei_id'):
                df_list.append(read_files(files, cause_spec,
                                          **rei_and_cause_args))
    df = pd.concat(df_list)
    idx_cols = df.filter(regex='_id$').columns.tolist()
    draw_cols = df.filter(regex='^draw_').columns.tolist()
    return df[idx_cols + sorted(draw_cols)]


def get_files(gbd_id_field, base_dir):
    ''' sequela_id, cause_id, and rei_id are all saved under acute/chronic/total
        folders. This returns the full file paths to all files under those 3
        categories '''
    files = []
    child_dirs = ['acute', 'chronic', 'total']
    for child_dir in child_dirs:
        tmp_dir = os.path.join(base_dir, child_dir)
        files_in_tmp = os.listdir(tmp_dir)
        full_paths = [os.path.join(tmp_dir, f) for f in files_in_tmp]
        for f in full_paths:
            files.append(f)
    return files


def find_como_version(status):
    ''' if Status is "best", return como version id currently marked best.
        If status is "latest", return cv_id most recently added to
        epi.output_version if that is marked best or active

        Note that latest version could be best version
    '''
    from gopher import query
    assert status == 'best' or status == 'latest', ("status should be best "
                                                    "or latest")

    if status == 'best':
        q = """
            SELECT
            pvm.val as como_version_id from gbd.gbd_process_version gpv
            JOIN
            gbd.gbd_process_version_metadata pvm using (gbd_process_version_id)
            JOIN
            gbd.compare_version_output cvo using (gbd_process_version_id)
            JOIN
            gbd.compare_version cv on cv.compare_version_id = cvo.compare_version_id
            WHERE
            gbd_process_id = 1
            and metadata_type_id = 4
            and cv.gbd_round_id = 3
            and cv.compare_version_status_id = 1
            order by gpv.date_inserted desc
            limit 1"""
        result = query("gbd", q)
        if result.empty:
            raise RuntimeError('no best como version found')
    elif status == 'latest':
        q = """
            SELECT
            pvm.val as como_version_id from gbd.gbd_process_version gpv
            JOIN
            gbd.gbd_process_version_metadata pvm using (gbd_process_version_id)
            WHERE
            gbd_process_id = 1
            and metadata_type_id = 4
            order by gpv.date_inserted desc
            limit 1
            """
        result = query("gbd", q)
        if result.empty:
            raise RuntimeError('No como versions found marked latest or '
                               'best')
    return result.como_version_id.item()
