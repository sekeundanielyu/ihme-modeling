import pandas as pd
import logging
from codcorrect.core import read_json
import codcorrect.log_utilities as l
import argparse
import sys

"""
    Appends all diagnostics together
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


if __name__ == '__main__':

    # Get command line arguments
    output_version_id = parse_args()

    # Set paths
    parent_dir = PARENT_DIRECTORY
    log_dir = parent_dir + r'/logs'

    # Start logging
    l.setup_logging(log_dir, 'append_diagnostics', output_version_id)

    try:
        # Read in helper files
        print "Reading in helper files"
        logging.info("Reading in helper files")
        config, location_ids = read_helper_files(parent_dir)

        # Read in summary files
        print "Reading in diagnostic files"
        logging.info("Reading in diagnostic files")
        data = []
        for location_id in location_ids:
            file_path = parent_dir + r'/diagnostics/diagnostics_{location_id}.csv'.format(location_id=location_id)
            print "Reading in {}".format(file_path)
            logging.info("Reading in {}".format(file_path))
            temp = pd.read_csv(file_path)
            temp = temp.ix[temp['year_id'].isin([1990, 1995, 2000, 2005, 2010, 2013, 2015])]
            data.append(temp)
        print "Concatinating diagnostic files"
        logging.info("Concatinating in diagnostic files")
        data = pd.concat(data)

        # Format for upload
        data['output_version_id'] = output_version_id
        diagnostic_table_fields = ['output_version_id', 'location_id', 'year_id', 'sex_id',
                                   'age_group_id', 'cause_id', 'mean_before',
                                   'mean_after']
        data = data[diagnostic_table_fields]

        # Save
        print "Save single diagnostic file"
        logging.info("Save single diagnostic file")
        file_path = parent_dir + r'/_temp/upload_diagnostics.csv'
        data.to_csv(file_path, index=False)

        logging.info('All done!')
    except:
        logging.exception('uncaught exception in append_diagnostics.py')
