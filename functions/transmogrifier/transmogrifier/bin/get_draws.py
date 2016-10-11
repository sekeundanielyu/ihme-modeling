# Parse arguments from get_draws.ado and return draw results
from gopher import draws
from stata import to_dct
import sys
import argparse
import json


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

parser = argparse.ArgumentParser(description='Retrieve draws')
parser.add_argument('gbd_id_dict', type=str)
parser.add_argument('source', type=str)
parser.add_argument('--measure_ids', type=all_parser, nargs="*",
                    default=[])
parser.add_argument('--location_ids', type=all_parser, nargs="*",
                    default=[])
parser.add_argument('--year_ids', type=all_parser, nargs="*",
                    default=[])
parser.add_argument('--age_group_ids', type=all_parser, nargs="*",
                    default=[])
parser.add_argument('--sex_ids', type=all_parser, nargs="*",
                    default=[])
parser.add_argument('--metric_ids', type=all_parser, nargs="*",
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

# convert kwargs from a list of single key dicts to one dict with
# multiple keys, if any specified from get_draws.ado
for d in args.pop('kwargs'):
    for k, v in d.iteritems():
        args[k] = v

# Get draws
try:
    df = draws(
        gbd_id_dict,
        measure_ids=args.pop('measure_ids'),
        location_ids=args.pop('location_ids'),
        year_ids=args.pop('year_ids'),
        age_group_ids=args.pop('age_group_ids'),
        sex_ids=args.pop('sex_ids'),
        status=status,
        source=args.pop('source'),
        include_risks=args.pop('include_risks'),
        **args)

except Exception as e:
    # catch all exceptions, because we need to write something to stdout
    # no matter what error. Get_draws.ado creates a pipe and reads from
    # it -- if nothing is written to the pipe, stata hangs
    print "Encountered error while reading draws: {}".format(e)
    raise

# stream results to sys.stdout for get_draws.ado to read in
# Use a dct because stata is faster at reading those
to_dct(df=df, fname=sys.stdout, include_header=True)
