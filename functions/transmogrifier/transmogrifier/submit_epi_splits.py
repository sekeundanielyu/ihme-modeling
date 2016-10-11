import os
from cluster_utils import submitter
import argparse

this_path = os.path.dirname(os.path.abspath(submitter.__file__))
this_path = os.path.normpath(os.path.join(this_path, ".."))

if __name__ == "__main__":

    def all_parser(s):
        try:
            s = int(s)
            return s
        except:
            return s
    parser = argparse.ArgumentParser(
        description='Launch job to split a parent cod model')
    parser.add_argument('source_meid', type=int)
    parser.add_argument('--target_meids', type=all_parser, nargs="*")
    parser.add_argument('--prop_meids', type=all_parser, nargs="*")
    parser.add_argument(
            '--split_meas_ids',
            type=all_parser,
            nargs="*",
            default=[5, 6])
    parser.add_argument('--prop_meas_id', type=int, default=18)
    parser.add_argument(
        '--output_dir',
        type=str,
        default="/ihme/gbd/WORK/10_gbd/00_library/epi_splits_sp")
    args = vars(parser.parse_args())

    runfile = "%s/epi.py" % this_path
    params = [args['source_meid'], "--target_meids"]
    params.extend(args['target_meids'])
    params.append("--prop_meids")
    params.extend(args['prop_meids'])
    params.append("--split_meas_ids")
    params.extend(args['split_meas_ids'])
    params.append("--prop_meas_id")
    params.append(args['prop_meas_id'])
    params.append("--output_dir")
    params.append(args['output_dir'])
    submitter.submit_job(
        runfile,
        'sme_%s' % args['source_meid'],
        parameters=params,
        project='proj_custom_models',
        slots=40,
        memory=60,
        supress_trailing_space=True)
