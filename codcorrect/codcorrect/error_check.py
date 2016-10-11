import sqlalchemy as sql
import pandas as pd
import logging
import sys
from codcorrect.restrictions import expand_id_set


def check_data_format(data, required_columns, fail=False):
    """
       Iterates through a DataFrame and verifies that
       A) column exists
       B) column contains no nulls

       If either are false, writes issue to log.
    """
    if not isinstance(required_columns, list):
        raise TypeError("required_columns must be a list")

    logger = logging.getLogger('error_check.check_data_format')
    return_code = True
    for col in required_columns:
        if col in data.columns:
            if len(data.ix[data[col].isnull()]) > 0:
                logger.warn((
                    "There are {missing_values} missing values in column {col}".
                    format(missing_values=len(data.ix[data[col].isnull()]),
                            col=col)))
                return_code = False
        else:
            logger.warn("Column {col} is missing".format(col=col))
            return_code = False
    if fail:
        try:
            assert return_code, 'Formatting errors found in data'
        except AssertionError as e:
            logging.exception('Formatting errors found in data')
            sys.exit()
        return return_code
    else:
        return return_code


def tag_zeros(data, data_columns, tag_column='tag'):
    """ This function tags rows of data that only have 0s """
    data[tag_column] = data[data_columns].min(axis=1)
    data.ix[data[tag_column]==0, tag_column] = data.ix[data[tag_column]==0, data_columns].max(axis=1)
    data.ix[data[tag_column]==0, tag_column] = True
    data.ix[data[tag_column]!=True, tag_column] = False
    return data


def missing_check(data, data_columns, fail=False, save_missing_filepath=None):
    data = tag_zeros(data, data_columns, tag_column='missing')
    return_code = data.ix[data['missing']==True].empty

    logger = logging.getLogger('error_check.missing_check')

    try:
        assert return_code, 'Missing data'
    except AssertionError as e:
        if save_missing_filepath:
            data.ix[data['missing']==True].to_csv(save_missing_filepath)
        if fail:
            logger.exception('Missing data found')
            sys.exit()
        else:
            logger.warning('Missing data found')
        return return_code
    return return_code


def exclusivity_check(data, unique_columns, fail=False, save_overlap_filepath=None):
    udata = data.ix[:, unique_columns].copy(deep=True)
    udata['c'] = 1
    udata = udata.groupby(unique_columns).count().reset_index()
    return_code = udata.ix[udata['c']>1].empty

    logger = logging.getLogger('error_check.exclusivity_check')

    try:
        assert return_code, 'Non-unique data found'
    except AssertionError as e:
        if save_overlap_filepath:
            pd.merge(data, udata.ix[udata['c']>1, unique_columns + ['c']], on=unique_columns, how='inner').sort(unique_columns).to_csv(save_overlap_filepath)
        if fail:
            logger.exception('Non-unique data found')
            sys.exit()
        else:
            logger.warning('Non-unique data found')
        return return_code
    return return_code


def save_diagnostics(before_data, after_data, index_columns, data_columns, location_id, parent_dir):
    logger = logging.getLogger('error_check.save_diagnostics')

    try:
        before_data['mean_before'] = before_data[data_columns].mean(axis=1)
        after_data['mean_after'] = after_data[data_columns].mean(axis=1)

        data = pd.merge(before_data[index_columns + ['mean_before']], after_data[index_columns + ['mean_after']], on=index_columns, how='outer')
        data.to_csv(parent_dir + r'/diagnostics/diagnostics_{location_id}.csv'.format(location_id=location_id), index=False)
    except Exception as e:
        logger.exception('Failed to save diagnostics: {}'.format(e))
        sys.exit()


def check_envelope(envelope_data, eligible_location_ids, eligible_year_ids, eligible_sex_ids, eligible_age_group_ids):
    # Make sure data is above 0
    print "Making sure all draws are above 0"
    data_columns = ['env_{}'.format(x) for x in xrange(1000)]
    data_columns += ['pop']
    envelope_data['min'] = envelope_data[data_columns].min(axis=1)
    print "Minimum envelope value: {}".format(envelope_data['min'].min())
    if envelope_data['min'].min() <= 0:
        print "ERROR: Draw/pop values in envelope that are less than or equal to 0"
        sys.exit()
    # Make sure all unique IDs are present
    print "Checking for unique IDs in envelope"
    uid_template = pd.DataFrame(eligible_location_ids, columns=['location_id'])
    uid_template = expand_id_set(uid_template, eligible_year_ids, 'year_id')
    uid_template = expand_id_set(uid_template, eligible_age_group_ids, 'age_group_id')
    uid_template = expand_id_set(uid_template, eligible_sex_ids, 'sex_id')
    envelope_data['_check'] = 1
    envelope_data = pd.merge(uid_template, envelope_data, on=['location_id', 'year_id', 'sex_id', 'age_group_id'], how='left')
    if len(envelope_data.ix[envelope_data['_check'].isnull()]) > 0:
        print "ERROR: Missing unique IDs from envelope"
        sys.exit()
    else:
        print "No missing unique IDs in envelope"
