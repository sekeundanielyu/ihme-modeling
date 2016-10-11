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
    parser.add_argument('source_cause_id', type=int)
    parser.add_argument('--target_cause_ids', type=all_parser, nargs="*")
    parser.add_argument('--target_meids', type=all_parser, nargs="*")
    parser.add_argument(
        '--output_dir',
        type=str,
        default="/ihme/gbd/WORK/10_gbd/00_library/cod_splits_sp")
    args = vars(parser.parse_args())

    runfile = "%s/cod.py" % this_path
    params = [args['source_cause_id'], "--target_cause_ids"]
    params.extend(args['target_cause_ids'])
    params.append("--target_meids")
    params.extend(args['target_meids'])
    params.append("--output_dir")
    params.append(args['output_dir'])
    submitter.submit_job(
        runfile,
        'sc_%s' % args['source_cause_id'],
        parameters=params,
        project='proj_custom_models',
        slots=40,
        memory=60,
        supress_trailing_space=True)
