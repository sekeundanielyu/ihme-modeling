import pandas as pd
import sqlalchemy as sql
from codcorrect.core import run_query, write_json, read_json, get_credentials
from codcorrect.database import get_best_model_version, get_best_envelope_version
from codcorrect.database import get_best_shock_models
from codcorrect.database import get_cause_hierarchy_version, get_cause_hierarchy, get_cause_metadata
from codcorrect.database import get_location_hierarchy_version, get_location_hierarchy, get_location_metadata
from codcorrect.database import get_age_weights, get_spacetime_restrictions
from codcorrect.database import new_diagnostic_version, wipe_diagnostics
from codcorrect.database import upload_diagnostics, upload_summaries
from codcorrect.database import unmark_best, mark_best, update_status
from codcorrect.io import change_permission
from codcorrect.restrictions import expand_id_set
from codcorrect.restrictions import get_eligible_age_group_ids, get_eligible_sex_ids
from codcorrect.error_check import check_envelope
from codcorrect.database import create_new_output_version_row
from codcorrect.agg import loctree as lt
from codcorrect.submit_jobs import Task, TaskList
import os
import subprocess
import time
import datetime
import argparse

"""
Example usage:

python launch.py [output_version_id], where output_version_id is the number you
want to create. If output_version_id == new, the current max version + 1 will
be used.

This is the version I'm using to test:
python launch.py _test
"""

def parse_args():
    """
        Parse command line arguments

        Arguments are output_version_id

        Returns:
        string
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("output_version_id", type=str)
    parser.add_argument("-y", "--years", default="est",
                        help="years to correct: est(imation), full", type=str,
                        choices=["est","full"])
    parser.add_argument("-r", "--resume", help="Resume run of CoDCorrect",
                        action="store_true")
    parser.add_argument("-appsum", "--append_summaries", help="Append summaries",
                        action="store_true")
    parser.add_argument("-upsum", "--upload_summaries", help="Upload summaries",
                        action="store_true")
    parser.add_argument("-updiag", "--upload_diagnostics",
                        help="Upload diagnostics", action="store_true")
    parser.add_argument("-b", "--best",
                        help="Mark best", action="store_true")
    # Parse arguments
    args = parser.parse_args()
    output_version_id = args.output_version_id
    resume = args.resume
    append_summaries_status = args.append_summaries
    upload_summary_status = args.upload_summaries
    upload_diagnostics_status = args.upload_diagnostics
    best = args.best
    # Determine years to correct
    if args.years == "est":
        codcorrect_years = [1990, 1995, 2000, 2005, 2010, 2013, 2015]
    elif args.years == "full":
        codcorrect_years = range(1980, 2016)
    # Print arguments
    print "output_version_id: {}".format(output_version_id)
    print "codcorrect_years: {}".format(','.join([str(x) for x in codcorrect_years]))
    print "resume: {}".format(resume)
    print "upload summaries: {}".format(upload_summary_status)
    print "upload diagnostics: {}".format(upload_diagnostics_status)
    print "mark best: {}".format(best)
    # Return outputs
    return output_version_id, codcorrect_years, resume, append_summaries_status, upload_summary_status, upload_diagnostics_status, best


def set_up_folders(output_directory, output_directory_j, output_version_id='new'):
    """
       Create a new CoDCorrect id, and then set up _temp, scalars, draws
       returns parent directory string
    """
    if output_version_id == 'new':
        output_version_id = new_CoDCorrect_version()

    new_folders = ['_temp', 'input_data', 'draws', 'shocks', 'models',
                   'unaggregated', 'unaggregated/unscaled',
                   'unaggregated/rescaled', 'unaggregated/shocks',
                   'aggregated', 'aggregated/unscaled',
                   'aggregated/rescaled', 'aggregated/shocks',
                   'debug', 'diagnostics', 'logs', 'summaries']

    for folder in new_folders:
        directory = '{d}/{v}/{f}'.format(d=output_directory, v=output_version_id, f=folder)
        if not os.path.exists(directory):
           os.makedirs(directory)
        directory = '{d}/{v}/{f}'.format(d=output_directory_j, v=output_version_id, f=folder)
        if not os.path.exists(directory):
           os.makedirs(directory)
    return '{d}/{v}'.format(d=output_directory, v=output_version_id)


def save_temp_data(best_models, eligible_data, parent_dir):
    """
       Save csv of best models and eligible data for use as
       inputs by other processes
    """
    best_models.to_csv(parent_dir + r'/_temp/best_models.csv',index=False)
    eligible_data.to_csv(parent_dir + r'/_temp/eligible_data.csv',index=False)
    return None


def prepare_envelope():
    # Get best envelope version
    envelope_version_id = get_best_envelope_version()
    print "Best envelope version: {}".format(envelope_version_id)
    # Read in file
    file_path = ENVELOPE_DRAWS_PATH
    envelope = pd.read_csv(file_path)
    # Keep only what we need
    envelope = envelope[['location_id', 'year_id', 'sex_id', 'age_group_id', 'pop']+['env_{}'.format(x) for x in xrange(1000)]]
    # Filter to just the most-detailed
    envelope = envelope.ix[(envelope['location_id'].isin(eligible_location_ids))&
                           (envelope['year_id'].isin(eligible_year_ids))&
                           (envelope['sex_id'].isin(eligible_sex_ids))&
                           (envelope['age_group_id'].isin(eligible_age_group_ids))].reset_index(drop=True)
    # Check envelope
    check_envelope(envelope, eligible_location_ids, eligible_year_ids,
                   eligible_sex_ids, eligible_age_group_ids)
    # Save
    print "Saving envelope draws"
    envelope = envelope.sort(['location_id', 'year_id', 'sex_id', 'age_group_id']).reset_index(drop=True)
    envelope.to_hdf(parent_dir + r'/_temp/envelope.h5', 'draws', mode='w',
                    format='table',
                    data_columns=['location_id', 'year_id', 'sex_id', 'age_group_id'])
    # Make means and save
    print "Saving envelope summaries"
    envelope['envelope'] = envelope[['env_{}'.format(x) for x in xrange(1000)]].mean(axis=1)
    envelope = envelope[['location_id', 'year_id', 'sex_id', 'age_group_id', 'pop', 'envelope']]
    envelope = envelope.sort(['location_id', 'year_id', 'sex_id', 'age_group_id']).reset_index(drop=True)
    envelope.to_hdf(parent_dir + r'/_temp/envelope.h5', 'summary', mode='a',
                    format='table',
                    data_columns=['location_id', 'year_id', 'sex_id', 'age_group_id'])
    return envelope_version_id


def generate_rescale_jobs(task_list, code_directory, log_directory, locations, resume=False):
    """ Generate one job for each location-sex for the most-detailed set of locations """
    for location_id in locations:
        for sex_name in ['male', 'female']:
            job_name = "correct-{}-{}-{}".format(location_id, sex_name, output_version_id)
            job_command = ["{c}/python_shell.sh".format(c=code_directory),
                           "{c}/correct.py".format(c=code_directory),
                           "--output_version_id", str(output_version_id),
                           "--location_id", str(location_id),
                           "--sex_name", sex_name]
            job_log = "{ld}/correct_{v}_{lid}_{sn}.txt".format(v=output_version_id,
                                                             ld=log_directory,
                                                             lid=location_id,
                                                             sn=sex_name)
            job_project = "proj_codcorrect"
            job_slots = 15
            job_dependencies = []
            task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_shock_jobs(task_list, code_directory, log_directory, locations, resume=False):
    """ Generate one job for each location-sex for the most-detailed set of locations """
    for location_id in locations:
        for sex_name in ['male', 'female']:
            job_name = "shocks-{}-{}-{}".format(location_id, sex_name, output_version_id)
            job_command = ["{c}/python_shell.sh".format(c=code_directory),
                           "{c}/shocks.py".format(c=code_directory),
                           "--output_version_id", str(output_version_id),
                           "--location_id", str(location_id),
                           "--sex_name", sex_name]
            job_log = "{ld}/shocks_{v}_{lid}_{sn}.txt".format(v=output_version_id,
                                                             ld=log_directory,
                                                             lid=location_id,
                                                             sn=sex_name)
            job_project = "proj_codcorrect"
            job_slots = 10
            job_dependencies = []
            task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_cause_aggregation_jobs(task_list, code_directory, log_directory, locations, resume=False):
    """ Generate one job for each location for the most-detailed set of locations """
    for location_id in locations:
        job_name = "agg-cause-{}-{}".format(location_id, output_version_id)
        job_command = ["{c}/python_shell.sh".format(c=code_directory),
                       "{c}/aggregate_causes.py".format(c=code_directory),
                       "--output_version_id", str(output_version_id),
                       "--location_id", str(location_id)]
        job_log = "{ld}/agg_cause_{v}_{lid}_{sn}.txt".format(v=output_version_id,
                                                             ld=log_directory,
                                                             lid=location_id,
                                                             sn="both")
        job_project = "proj_codcorrect"
        job_slots = 20
        job_dependencies = ["{}-{}-{}-{}".format(process, location_id, sex_name, output_version_id) for sex_name in ["male", "female"] for process in ["correct", "shocks"]]
        task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_location_aggregation_jobs(task_list, code_directory, log_directory, location_data, resume=False):
    """ Generate one job for each location """
    max_location_hierarchy = location_data.ix[location_data['is_estimate']==1, 'level'].max()
    for level in xrange(max_location_hierarchy, 0, -1):
        parent_location_ids = [location_id for location_id in location_data.ix[location_data['level']==level, 'parent_id'].drop_duplicates()]
        for location_id in parent_location_ids:
            job_name = "agg-location-{}-{}".format(location_id, output_version_id)
            job_command = ["{c}/python_shell.sh".format(c=code_directory),
                           "{c}/aggregate_locations.py".format(c=code_directory),
                           "--output_version_id", str(output_version_id),
                           "--location_id", str(location_id)]
            job_log = "{ld}/agg_location_{v}_{lid}_{sn}.txt".format(v=output_version_id,
                                                             ld=log_directory,
                                                             lid=location_id,
                                                             sn="both")
            job_project = "proj_codcorrect"
            job_slots = 30
            job_dependencies = []
            for child_id in location_data.ix[(location_data['parent_id']==location_id)&(location_data['level']==level), 'location_id'].drop_duplicates():
                if len(location_data.ix[(location_data['location_id']==child_id)&(location_data['most_detailed']==1)]) == 1:
                    job_dependencies.append("agg-cause-{}-{}".format(child_id, output_version_id))
                else:
                    job_dependencies.append("agg-location-{}-{}".format(child_id, output_version_id))
            task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_summary_jobs(task_list, code_directory, log_directory, locations, resume=False):
    for location_id in locations:
        job_name = "summary-{}-{}".format(location_id, output_version_id)
        job_command = ["{c}/python_shell.sh".format(c=code_directory),
                       "{c}/summary.py".format(c=code_directory),
                       "--output_version_id", str(output_version_id),
                       "--location_id", str(location_id)]
        job_log = "{ld}/summary_{v}_{lid}_{sn}.txt".format(v=output_version_id,
                                                             ld=log_directory,
                                                             lid=location_id,
                                                             sn="both")
        job_project = "proj_codcorrect"
        job_slots = 10
        job_dependencies = ["agg-location-1-{}".format(output_version_id)]
        task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_append_summary_jobs(task_list, code_directory, log_directory, locations, resume=False):
    job_name = "append-summary-{}".format(output_version_id)
    job_command = ["{c}/python_shell.sh".format(c=code_directory),
                   "{c}/append_summaries.py".format(c=code_directory),
                   "--output_version_id", str(output_version_id)]
    job_log = "{ld}/append_summaries_{v}.txt".format(v=output_version_id,
                                                   ld=log_directory)
    job_project = "proj_codcorrect"
    job_slots = 46
    job_dependencies = ["summary-{}-{}".format(location_id, output_version_id) for location_id in locations]
    task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list

def generate_append_diagnostic_jobs(task_list, code_directory, log_directory, resume=False):
    job_name = "append_diagnostics-{}".format(output_version_id)
    job_command = ["{c}/python_shell.sh".format(c=code_directory),
                   "{c}/append_diagnostics.py".format(c=code_directory),
                   "--output_version_id", str(output_version_id)]
    job_log = "{ld}/append_diagnostics_{v}.txt".format(v=output_version_id,
                                                       ld=log_directory)
    job_project = "proj_codcorrect"
    job_slots = 15
    job_dependencies = ["agg-location-1-{}".format(output_version_id)]
    task_list.add_task(Task(job_name, job_command, job_log, job_project, slots=job_slots, resume=resume), job_dependencies)
    return task_list


def prep_upload(parent_dir):
    change_permission(parent_dir, recursively=False)
    change_permission(parent_dir + r'/_temp/', recursively=True)
    output_upload_files = read_json(parent_dir + r'/_temp/output_upload.json')
    return output_upload_files


if __name__ == '__main__':

    # Set some core variables
    code_directory = CODE_DIRECTORY
    output_directory = FILE_OUTPUT_DIRECTORY

    # set up folders
    output_version_id, codcorrect_years, resume, append_summaries_status, upload_summary_status, upload_diagnostics_status, best = parse_args()
    parent_dir = set_up_folders(output_directory, output_directory_j, output_version_id)

    if not resume:
        # Retrieve cause resources from database
        cause_set_version_id, cause_metadata_version_id = get_cause_hierarchy_version(1, 2015)
        cause_data = get_cause_hierarchy(cause_set_version_id)
        cause_metadata = get_cause_metadata(cause_metadata_version_id)
        cause_agg_set_version_id, cause_agg_metadata_version_id = get_cause_hierarchy_version(3, 2015)
        cause_aggregation_hierarchy = get_cause_hierarchy(cause_agg_set_version_id)

        # Retrieve location resources from database
        location_set_version_id, location_metadata_version_id = get_location_hierarchy_version(35, 2015)
        location_data = get_location_hierarchy(location_set_version_id)
        location_metadata = get_location_metadata(location_metadata_version_id)

        # Get location & cause names
        location_name_data = run_query("SELECT * FROM shared.location")
        cause_name_data = run_query("SELECT * FROM shared.cause")
        age_name_data = run_query("SELECT * FROM shared.age_group")

        # Set the eligible locations, years, sexes, and ages that will appear in the input data
        eligible_age_group_ids = range(2, 22)
        eligible_sex_ids = [1, 2]
        eligible_cause_ids = cause_data.ix[cause_data['level']>0, 'cause_id'].tolist()
        eligible_year_ids = range(1980, 2016)
        eligible_location_ids = location_data.ix[location_data['is_estimate']==1, 'location_id'].tolist()

        # Pull Space-Time (Geographic) restrictions
        spacetime_restrictions = get_spacetime_restrictions()

        # Create a DataFrame of all eligible cause, age, sex combinations
        eligible_data = pd.DataFrame(eligible_cause_ids, columns=['cause_id'])
        eligible_data = expand_id_set(eligible_data, eligible_age_group_ids, 'age_group_id')
        eligible_data = expand_id_set(eligible_data, eligible_sex_ids, 'sex_id')

        # Add a restriction variable to the eligible DataFrame to factor in age-sex restrictions of causes
        eligible_data['restricted'] = True
        for cause_id in eligible_cause_ids:
            non_restricted_age_group_ids = get_eligible_age_group_ids(
                cause_metadata[cause_id]['yll_age_start'],
                cause_metadata[cause_id]['yll_age_end'])
            non_restricted_sex_ids = get_eligible_sex_ids(
                cause_metadata[cause_id]['male'],
                cause_metadata[cause_id]['female'])
            eligible_data.ix[(eligible_data['cause_id']==cause_id)&(
                                                                    (eligible_data['age_group_id'].isin(non_restricted_age_group_ids))&
                                                                    (eligible_data['sex_id'].isin(non_restricted_sex_ids))
                                                                   ), 'restricted'] = False

        # Get a list of best models currently marked and those used in the shock aggregator
        all_best_models = get_best_model_version(2015)[['cause_id', 'sex_id', 'model_version_id', 'model_version_type_id']]
        shock_aggregator_best_models = get_best_shock_models(2015)[['cause_id', 'sex_id', 'model_version_id', 'model_version_type_id']]
        all_best_models = pd.concat([all_best_models, shock_aggregator_best_models])
        codcorrect_models = all_best_models.ix[all_best_models['model_version_type_id'].isin(range(0,5))].copy(deep=True)
        shock_models = all_best_models.ix[~all_best_models['model_version_type_id'].isin(range(0,5))].copy(deep=True)

        # Check against a list of causes for which we should have models)
        eligible_models = eligible_data.ix[eligible_data['restricted']==False, ['cause_id', 'sex_id']].drop_duplicates().copy(deep=True)
        codcorrect_models = pd.merge(eligible_models, codcorrect_models, on=['cause_id', 'sex_id'], how='left')

        # Add on some metadata for use as inputs to correct.py
        codcorrect_models = pd.merge(cause_data[['cause_id','acause', 'level', 'parent_id']], codcorrect_models, on=['cause_id'])
        shock_models = pd.merge(cause_aggregation_hierarchy[['cause_id','acause', 'level', 'parent_id']], shock_models, on=['cause_id'])

        # Make single list of best models
        best_models = pd.concat([codcorrect_models, shock_models]).reset_index(drop=True)

        # Get a list of models that are missing
        for i in best_models.ix[best_models['model_version_id'].isnull()].index:
            print best_models.ix[i, 'cause_id'], best_models.ix[i, 'sex_id']
        best_models = best_models.ix[best_models['model_version_id'].notnull()]

        # Save helper files
        best_models.to_csv(parent_dir+'/_temp/best_models.csv', index=False)
        eligible_data = pd.merge(eligible_data,
                                 cause_data[['cause_id', 'level', 'parent_id']],
                                 on=['cause_id'], how='left')
        eligible_data.to_csv(parent_dir+'/_temp/eligible_data.csv', index=False)
        spacetime_restrictions.to_csv(parent_dir+'/_temp/spacetime_restrictions.csv', index=False)
        cause_aggregation_hierarchy.to_csv(parent_dir+'/_temp/cause_aggregation_hierarchy.csv', index=False)
        location_data.to_csv(parent_dir+'/_temp/location_hierarchy.csv', index=False)
        get_age_weights().to_csv(parent_dir+'/_temp/age_weights.csv', index=False)

        # Save envelope
        envelope_version_id = prepare_envelope()

        # Save config file
        config = {}
        config['envelope_version_id'] = envelope_version_id
        config['envelope_column'] = 'envelope'
        config['envelope_index_columns'] = ['location_id', 'year_id', 'sex_id', 'age_group_id']
        config['envelope_pop_column'] = 'pop'
        config['index_columns'] = ['location_id', 'year_id', 'sex_id', 'age_group_id', 'cause_id']
        config['data_columns'] = ['draw_{}'.format(x) for x in xrange(1000)]
        config['eligible_age_group_ids'] = eligible_age_group_ids
        config['eligible_sex_ids'] = eligible_sex_ids
        config['eligible_cause_ids'] = eligible_cause_ids
        config['eligible_year_ids'] = codcorrect_years
        config['eligible_location_ids'] = eligible_location_ids
        config['dalynator_export_years_ids'] = codcorrect_years
        config['diagnostic_year_ids'] = [1990, 1995, 2000, 2005, 2010, 2013, 2015]

        write_json(config, parent_dir + r'/_temp/config.json')
    else:
        # Read in location data
        location_data = pd.read_csv(parent_dir+'/_temp/location_hierarchy.csv')

        # Read in config file
        config = read_json(parent_dir + r'/_temp/config.json')

        # Read in variables
        eligible_location_ids = config['eligible_location_ids']
        envelope_version_id = config['envelope_version_id']


        # if eligible_year_ids do not match, then do not resume jobs
        if config['eligible_year_ids'] != codcorrect_years:
            print "CoDCorrect years do not match!"
            print "Can't just resume jobs"
            config['eligible_year_ids'] != codcorrect_years
            write_json(config, parent_dir + r'/_temp/config.json')
            resume = False

    # Generate CoDCorrect jobs
    codcorrect_job_list = TaskList()
    codcorrect_job_list = generate_rescale_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', eligible_location_ids, resume=resume)
    codcorrect_job_list = generate_shock_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', eligible_location_ids, resume=resume)
    codcorrect_job_list = generate_cause_aggregation_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', eligible_location_ids, resume=resume)
    codcorrect_job_list = generate_location_aggregation_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', location_data, resume=resume)
    codcorrect_job_list = generate_summary_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', location_data['location_id'].drop_duplicates(), resume=resume)
    if append_summaries_status:
        codcorrect_job_list = generate_append_summary_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', location_data['location_id'].drop_duplicates(), resume=resume)
    codcorrect_job_list = generate_append_diagnostic_jobs(codcorrect_job_list, code_directory, parent_dir+'/logs', resume=resume)

    # Run jobs
    codcorrect_job_list.update_status(resume=resume)
    while  (codcorrect_job_list.completed < codcorrect_job_list.all_jobs) and (codcorrect_job_list.retry_exceeded == 0):
        if codcorrect_job_list.submitted > 0 or codcorrect_job_list.running > 0:
            time.sleep(60)
        codcorrect_job_list.update_status()
        codcorrect_job_list.run_jobs()
        print "There are:"
        print "    {} all jobs".format(codcorrect_job_list.all_jobs)
        print "    {} submitted jobs".format(codcorrect_job_list.submitted)
        print "    {} running jobs".format(codcorrect_job_list.running)
        print "    {} not started jobs".format(codcorrect_job_list.not_started)
        print "    {} completed jobs".format(codcorrect_job_list.completed)
        print "    {} failed jobs".format(codcorrect_job_list.failed)
        print "    {} jobs whose retry attempts are exceeded".format(codcorrect_job_list.retry_exceeded)
    if codcorrect_job_list.retry_exceeded > 0:
        codcorrect_job_list.display_jobs(status="Retry exceeded")
    else:
        print "Creating upload entry in database"
        create_new_output_version_row(output_version_id,  "New version of CodCorrect", envelope_version_id)
        if upload_diagnostics_status:
            print "Uploading diagnostics"
            change_permission(parent_dir)
            change_permission(parent_dir + r'/_temp/', recursively=True)
            wipe_diagnostics()
            new_diagnostic_version(output_version_id)
            upload_diagnostics(parent_dir)
        if upload_summary_status:
            print "Preparing for upload"
            change_permission(parent_dir)
            change_permission(parent_dir + r'/_temp/', recursively=True)
            output_files = prep_upload(parent_dir)
            for f in output_files:
                upload_summaries(f)
        if best:
            print "Marking upload as best"
            unmark_best(output_version_id)
            mark_best(output_version_id)
        update_status(output_version_id, 1)

    print "Done!"
