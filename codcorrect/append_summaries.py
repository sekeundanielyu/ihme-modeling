import pandas as pd
import logging
from codcorrect.core import write_json, read_json
import codcorrect.log_utilities as l
import argparse
import sys

"""
    Appends all summaries together
"""

def parse_args():
    """ Parse command line arguments """
    parser = argparse.ArgumentParser()
    parser.add_argument("--output_version_id", type=str)

    args = parser.parse_args()
    output_version_id = args.output_version_id

    return output_version_id


def read_helper_files(parent_dir):
    """ Read in and return helper DataFrames.

        Returns:
        DataFrame containing cause hierarchy used for aggregation
    """

    # Config file
    config = read_json(parent_dir + r'/_temp/config.json')

    # Location hierarchy
    location_hierarchy = pd.read_csv(parent_dir + r'/_temp/location_hierarchy.csv')
    location_ids = location_hierarchy['location_id'].drop_duplicates().tolist()

    return config, location_ids


def save_upload_outputs(data, max_rows=20000000):
    """ Save output files for upload """
    logger = logging.getLogger('summary.save_upload_outputs')
    try:
        output_files = []
        data.index = data.index / max_rows
        data.index = data.index.astype('int64')
        for i in data.index.drop_duplicates().tolist():
            file_path = parent_dir + r'/_temp/upload_summaries_{}.csv'.format(i)
            print "Saving {}".format(file_path)
            logger.info("Saving {}".format(file_path))
            temp = data.ix[i].copy(deep=True)
            temp.to_csv(file_path, index=False)
            output_files.append(file_path)
        return output_files
    except Exception as e:
        logger.exception('Failed to save output files: {}'.format(e))




if __name__ == '__main__':

    # Get command line arguments
    output_version_id = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'append_summaries', output_version_id)

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, location_ids = read_helper_files(parent_dir)

        # Read in summary files
        print "Reading in summary files"
        logging.info("Reading in summary files")
        # for location_id in location_ids:
        #     file_path = parent_dir + r'/summaries/summary_{location_id}.csv'.format(location_id=location_id)
        #     print "Reading in {}".format(file_path)
        #     logging.info("Reading in {}".format(file_path))
        #     data.append(pd.read_csv(file_path))
        all_files = ["{p}/summaries/summary_{l}.csv".format(p=parent_dir, l=location_id) for location_id in location_ids]
        pool = Pool(20)
        data = pool.map(pd.read_csv, all_files)
        pool.close()
        pool.join()
        print "Concatinating summary files"
        logging.info("Concatinating in summary files")
        data = pd.concat(data).reset_index(drop=True)

        # Make sure all data columns have values
        print "Filling in blank values"
        cols = ['{}_{}{}'.format(b, t, a) for t in ['cf', 'death'] for b in ['mean', 'lower', 'upper'] for a in ['', '_with_shocks']]
        cols.append('model_version_id')
        for c in cols:
            data[c] = data[c].fillna(0)

        # Save
        print "Save single summary files"
        logging.info("Save single summary files")
        output_files = save_upload_outputs(data)
        write_json(output_files, parent_dir + r'/_temp/output_upload.json')

        logging.info('All done!')
    except:
        logging.exception('uncaught exception in append_summaries.py')
