#!/usr/bin/env python

# Parse arguments from get_pct_change.ado and return draw results
from adding_machine.summarizers import (get_estimates, pct_change,
                                        transform_metric)
from adding_machine.get_pct_change_helpers.metric import define_metric
import argparse
import json
from transmogrifier.gopher import draws
from transmogrifier.stata import to_dct
import pandas as pd
import sys

pd.options.mode.chained_assignment = None


def kwarg_parser(s):
    ''' take a string argument of the form param1:arg1
            and return {'param1': 'arg1'}
    '''
    if ':' not in s:
        raise RuntimeError('invalid kwarg format')
    else:
        parsed = s.split(':')
        key = parsed[0]
        value = parsed[1]
        return {key: value}


def all_parser(s):
    try:
        s = int(s)
        return s
    except:
        return s


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Calculate pct change')
    parser.add_argument('gbd_id_dict', type=str)
    parser.add_argument('--source', type=str, required=True)
    parser.add_argument('--change_type', type=str, required=True)
    parser.add_argument('--year_start_id', type=all_parser, required=True)
    parser.add_argument('--year_end_id', type=all_parser, required=True)
    parser.add_argument('--measure_ids', type=all_parser, nargs="*",
                        default=[])
    parser.add_argument('--location_ids', type=all_parser, nargs="*",
                        default=[])
    parser.add_argument('--age_group_ids', type=all_parser, nargs="*",
                        default=[])
    parser.add_argument('--sex_ids', type=all_parser, nargs="*",
                        default=[])
    parser.add_argument('--status', type=str, default='best')
    parser.add_argument('--include_risks', dest='include_risks',
                        action='store_true')
    parser.add_argument('--kwargs', type=kwarg_parser, nargs='*', default=[])
    parser.set_defaults(include_risks=False)
    args = vars(parser.parse_args())

    # convert string dict to real dict
    gbd_id_dict = json.loads(args.pop('gbd_id_dict'))

    # Try to cast status to an integer, otherwise leave as string
    try:
        status = int(float(args['status']))
    except:
        status = args['status']
    args.pop('status')

    source = args['source']
    change_type = args['change_type']
    start_year = int(args['year_start_id'])
    end_year = int(args['year_end_id'])
    age_group_ids = args['age_group_ids']

    # Make sure the args are set up for percent change
    assert (end_year > start_year), "Yr end must be more recent than yr start"
    assert (source != 'risk'), "Risk as a source is not supported."

    # convert kwargs from a list of single key dicts to one dict with
    # multiple keys, if any specified from get_pct_change.ado
    for d in args.pop('kwargs'):
        for k, v in d.iteritems():
            args[k] = v

    # Get draws
    try:
        df = draws(
            gbd_id_dict,
            measure_ids=args.pop('measure_ids'),
            location_ids=args.pop('location_ids'),
            year_ids=[start_year, end_year],
            age_group_ids=args.pop('age_group_ids'),
            sex_ids=args.pop('sex_ids'),
            status=status,
            source=args.pop('source'),
            include_risks=args.pop('include_risks'),
            **args).reset_index(drop=True)
    except Exception as e:
        # catch all exceptions, because we need to write something to stdout
        # no matter what error. Get_pct_change.ado creates a pipe and reads
        # from it -- if nothing is written to the pipe, stata hangs
        print "Encountered error while reading draws: {}".format(e)
        raise

    # If they want age-std, make sure that's possible
    if 27 in age_group_ids:
        assert change_type != 'pct_change_num', ('Cant calc pct_change_num '
                                                 'for age-std')
        assert 27 in df.age_group_id.unique(), ('Cant calc change in age-std '
                                                'rates because age-std draws '
                                                'dont exist from this source. '
                                                'Try another.')

    # standardize all inputs by transforming everything to rate space
    df = define_metric(df, source)
    if 1 in df.metric_id.unique():
        df.loc[df.metric_id == 1] = transform_metric(df.loc[df.metric_id == 1],
                                                     to_id=3, from_id=1)

    # find index (non draw) columns
    try:
        df.drop(['envelope', 'pop'], axis=1, inplace=True)
    except:
        pass
    draw_cols = list(df.filter(like='draw').columns)
    index_cols = list(set(df.columns) - set(draw_cols + ['year_id']))

    # calculate pct_change
    if change_type == 'pct_change_num':  # drop any 2's. transform only 3's.
        df = transform_metric(df[df.metric_id == 3], to_id=1, from_id=3)
    if change_type in ['pct_change_rate', 'pct_change_num']:
        change_type = 'pct_change'
    change_df = pct_change(df, start_year, end_year, change_type, index_cols)

    # summarize
    summ_df = get_estimates(change_df)
    summ_df.drop('mean', axis=1, inplace=True)
    summ_df.rename(columns={'pct_change_means': 'mean'}, inplace=True)

    # stream results to sys.stdout for get_pct_change.ado to read in
    # Use a dct because stata is faster at reading those
    to_dct(df=summ_df, fname=sys.stdout, include_header=True)
