import os
import gopher
import argparse
import uuid
import platform


def all_parser(s):
    try:
        s = int(s)
        return s
    except:
        return s
parser = argparse.ArgumentParser(description='Retrieve estimates')
parser.add_argument('gbd_team', type=str)
parser.add_argument('--gbd_id', type=int, default=None)
parser.add_argument('--model_version_id', type=int, default=None)
parser.add_argument('--measure_ids', type=all_parser, nargs="*",
                    default=['all'])
parser.add_argument('--location_ids', type=all_parser, nargs="*",
                    default=['all'])
parser.add_argument('--year_ids', type=all_parser, nargs="*",
                    default=['all'])
parser.add_argument('--age_group_ids', type=all_parser, nargs="*",
                    default=['all'])
parser.add_argument('--sex_ids', type=all_parser, nargs="*",
                    default=['all'])
parser.add_argument('--status', type=str, default='best')
args = vars(parser.parse_args())

# Get version ids for constructing a CSV temporary directory
if args['gbd_team'] == 'cod':
    gbd_id_field = 'cause_id'
elif args['gbd_team'] == 'epi':
    gbd_id_field = 'modelable_entity_id'
else:
    raise Exception("invalid gbd_team argument provided")

if args['model_version_id'] is None:
    vids = gopher.version_id(**{
        gbd_id_field: args['gbd_id'], 'status': args['status']})
else:
    vids = [args['model_version_id']]

# Get estimates
df = gopher.estimates(
    args['gbd_team'],
    gbd_id=args['gbd_id'],
    model_version_id=args['model_version_id'],
    measure_ids=args['measure_ids'],
    location_ids=args['location_ids'],
    year_ids=args['year_ids'],
    age_group_ids=args['age_group_ids'],
    sex_ids=args['sex_ids'],
    status=args['status'])

# Create a temporary location for the CSV file
strvids = [str(v) for v in vids]
if platform.system() == 'Linux':
    csvroot = '/ihme/gbd/WORK/10_gbd/00_library/tmp_littlecsvs'
elif platform.system() == 'Windows':
    csvroot = 'J:/temp/central_comp/est_temp_littlecsvs'
csvdir = '%s/%s/%s/%s' % (
    csvroot, gbd_id_field, args['gbd_id'], "".join(strvids)[:10])
try:
    os.makedirs(csvdir)
except:
    pass
fileuuid = str(uuid.uuid4())
filename = '%s.csv' % fileuuid

# Save the CSV and return its full path
filepath = '%s/%s' % (csvdir, filename)
df.to_csv(filepath, index=False)
print filepath
