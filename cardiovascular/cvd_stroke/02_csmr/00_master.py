# Python launcher code for all Nonfatal Stroke Custom Modeling
# Since the modeler involved does not code in Python, this code
# is launched using the nonfatal_stroke_wrapper.sh

import pandas as pd
import stroke_fns
import subprocess
from epi_uploader.upload import upload_sheet
from epi_uploader.xform.uncertainty import (fill_mean_ss_cases,
                                            fill_uncertainty)
from epi_uploader.db_tools import dbapis
import sys

step = sys.argv[1]
step = int(step)

# set up database connections
enginer = dbapis.engine_factory()
enginer.define_engine(
    engine_name='epi_prod', host_key='strKey',
    default_schema='epi')
enginer.define_engine(
    engine_name='cod_prod', host_key='strKey',
    default_schema='shared')
enginer.define_engine(
    engine_name='epi_writer', host_key='strKey',
    default_schema='epi', user_name="strUser",
    password="strPassword")
enginer.define_engine(
    engine_name='epi_reader', host_key='strKey',
    default_schema='epi')
enginer.define_engine(
    engine_name='ghdx_reader', default_schema='ghdx',
    host="strHost",
    user_name="strUser", password="strPassword")

# set i/o parameters
time_now = stroke_fns.get_time()
dismod_dir = 'strPath'
out_dir = stroke_fns.check_dir(
    'strPath/%s' % time_now)

yearvals = range(1990, 2020, 5)

# /////////////////////////STEP 1\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
# set target me_id
total_me = 3954

# get model version of dismod models currently running/most recent
isch_me = 3952
hem_me = 3953

# wait on dismod models running and return model versions
isch_mv, hem_mv = stroke_fns.wait_dismod(isch_me, hem_me)

if step == 1:
    # run 01_survivorship
    for year in yearvals:
        call = ('qsub -cwd -N "surv_%s" -P proj_custom_models '
                '-o strPath '
                '-e strPath '
                '-l mem_free=40G -pe multi_slot 20 cluster_shell.sh '
                '01_survivorship.py "%s" "%s" "%s" "%s" "%s"' % (
                    year, dismod_dir, out_dir, year, isch_mv, hem_mv))
        subprocess.call(call, shell=True)

    # wait for 01_survivorship to completely finish
    stroke_fns.wait('surv', 300)

    # concatenate all of the year-separate outputs from 01
    epi_input = pd.DataFrame()
    for year in yearvals:
        df = pd.read_csv('%s/input_%s_%s_%s.csv' %
                         (out_dir, isch_mv, hem_mv, year))
        epi_input = epi_input.append(df)
    raw_df = epi_input.copy(deep=True)

    # add on necessary columns for epi uploader
    epi_input = stroke_fns.add_uploader_cols(epi_input)
    epi_input['nid'] = 239169
    epi_input['measure_id'] = 6
    epi_input['modelable_entity_id'] = total_me

    # fill in row_nums
    epi_input = stroke_fns.assign_row_nums(epi_input)

    # fill in uncertainty
    epi_input['measure'] = 'incidence'
    try:
        epi_input = fill_uncertainty(epi_input)  # gets se
        epi_input['effective_sample_size'] = .05 / \
            epi_input['standard_error']**2
        epi_input['sample_size'] = epi_input['effective_sample_size']
        epi_input = fill_mean_ss_cases(epi_input)  # gets cases
    except:
        raise ValueError("uncertainty recalculation failed")
    epi_input.drop(['age_group_id', 'year_id', 'measure'], axis=1,
                   inplace=True)

    # upload using the epi uploader
    upload_sheet.uploadit(
        df=epi_input, engine_factory=enginer, request_id=0,
        user_name='strUser',
        orig_path='isch/hem_stroke incidence * survivorship',
        raw_df=raw_df)

# /////////////////////////STEP 2\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
# set target me_ids
acute_isch_csmr_me = 9310
acute_hem_csmr_me = 9311
chronic_csmr_me = 9312

# wait on dismod model running and return model version
# note: two inputs into the prev step are also inputs to this step
chronic_mv = stroke_fns.wait_dismod(total_me)

if step == 2:
    # run 02_csmr
    for year in yearvals:
        call = ('qsub -cwd -N "step2_csmr_%s" -P proj_custom_models '
                '-o strPath '
                '-e strPath '
                '-l mem_free=40G -pe multi_slot 20 cluster_shell.sh '
                '02_csmr.py "%s" "%s" "%s" "%s" "%s" "%s"' % (
                    year, dismod_dir, out_dir, year, isch_mv, hem_mv,
                    chronic_mv))
        subprocess.call(call, shell=True)

    # wait for 02_csmr to completely finish
    stroke_fns.wait('step2_csmr', 300)

    # concatenate all of the year-separate outputs from 02
    chronic_list = []
    acute_hem_list = []
    acute_isch_list = []
    for year in yearvals:
        chronic = pd.read_csv('%s/rate_chronic_%s.csv' % (out_dir, year))
        chronic['modelable_entity_id'] = chronic_csmr_me
        chronic['year_id'] = year
        chronic_list.append(chronic)
        acute_isch = pd.read_csv('%s/rate_acute_isch_%s.csv' % (out_dir, year))
        acute_isch['modelable_entity_id'] = acute_isch_csmr_me
        acute_isch['year_id'] = year
        acute_isch_list.append(acute_isch)
        acute_hem = pd.read_csv('%s/rate_acute_hem_%s.csv' % (out_dir, year))
        acute_hem['modelable_entity_id'] = acute_hem_csmr_me
        acute_hem['year_id'] = year
        acute_hem_list.append(acute_hem)
    chronic_input = pd.concat(chronic_list)
    acute_isch_input = pd.concat(acute_isch_list)
    acute_hem_input = pd.concat(acute_hem_list)
    raw_chronic_df = chronic_input.copy(deep=True)
    raw_acute_isch_df = acute_isch_input.copy(deep=True)
    raw_acute_hem_df = acute_hem_input.copy(deep=True)

    # add on necessary columns for epi uploader
    chronic_input = stroke_fns.add_uploader_cols(chronic_input)
    chronic_input['nid'] = 238131
    chronic_input['measure_id'] = 15
    acute_isch_input = stroke_fns.add_uploader_cols(acute_isch_input)
    acute_isch_input['nid'] = 238131
    acute_isch_input['measure_id'] = 15
    acute_hem_input = stroke_fns.add_uploader_cols(acute_hem_input)
    acute_hem_input['nid'] = 238131
    acute_hem_input['measure_id'] = 15

    # fill in row_nums
    chronic_input = stroke_fns.assign_row_nums(chronic_input)
    acute_isch_input = stroke_fns.assign_row_nums(acute_isch_input)
    acute_hem_input = stroke_fns.assign_row_nums(acute_hem_input)

    # fill in uncertainty
    chronic_input['measure'] = 'mtspecific'
    try:
        chronic_input = fill_uncertainty(chronic_input)  # gets se
        chronic_input['effective_sample_size'] = (
            .05 / chronic_input['standard_error']**2)
        chronic_input['sample_size'] = chronic_input['effective_sample_size']
        chronic_input = fill_mean_ss_cases(chronic_input)  # gets cases
    except:
        raise ValueError("uncertainty recalculation failed")

    acute_isch_input['measure'] = 'mtspecific'
    try:
        acute_isch_input = fill_uncertainty(acute_isch_input)  # gets se
        acute_isch_input['effective_sample_size'] = (
            .05 / acute_isch_input['standard_error']**2)
        acute_isch_input['sample_size'] = acute_isch_input[
            'effective_sample_size']
        acute_isch_input = fill_mean_ss_cases(acute_isch_input)  # gets cases
    except:
        raise ValueError("uncertainty recalculation failed")

    acute_hem_input['measure'] = 'mtspecific'
    try:
        acute_hem_input = fill_uncertainty(acute_hem_input)  # gets se
        acute_hem_input['effective_sample_size'] = (
            .05 / acute_hem_input['standard_error']**2)
        acute_hem_input['sample_size'] = acute_hem_input[
            'effective_sample_size']
        acute_hem_input = fill_mean_ss_cases(acute_hem_input)  # gets cases
    except:
        raise ValueError("uncertainty recalculation failed")
    chronic_input.drop(['age_group_id', 'year_id', 'measure'], axis=1,
                       inplace=True)
    acute_isch_input.drop(['age_group_id', 'year_id', 'measure'], axis=1,
                          inplace=True)
    acute_hem_input.drop(['age_group_id', 'year_id', 'measure'], axis=1,
                         inplace=True)

    # upload using the epi uploader
    upload_sheet.uploadit(
        df=chronic_input, engine_factory=enginer, request_id=0,
        user_name='strUser',
        orig_path='CSMR estimation for acute and chronic proportions',
        raw_df=raw_chronic_df)
    upload_sheet.uploadit(
        df=acute_isch_input, engine_factory=enginer, request_id=0,
        user_name='johnsoco',
        orig_path='CSMR estimation for acute and chronic proportions',
        raw_df=raw_acute_isch_df)
    upload_sheet.uploadit(
        df=acute_hem_input, engine_factory=enginer, request_id=0,
        user_name='johnsoco',
        orig_path='CSMR estimation for acute and chronic proportions',
        raw_df=raw_acute_hem_df)

# /////////////////////////STEP 3\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
# wait on dismod models running and return model versions
isch_csmr_mv, hem_csmr_mv = stroke_fns.wait_dismod(
    acute_isch_csmr_me, acute_hem_csmr_me)

if step == 3:
    # run 01_survivorship for Step 3
    for year in yearvals:
        call = ('qsub -cwd -N "step3_surv_%s" -P proj_custom_models '
                '-o strPath '
                '-e strPath '
                '-l mem_free=40G -pe multi_slot 20 cluster_shell.sh '
                '01_survivorship.py "%s" "%s" "%s" "%s" "%s"' % (
                    year, dismod_dir, out_dir, year, isch_csmr_mv,
                    hem_csmr_mv))
        subprocess.call(call, shell=True)

    # wait for 01_survivorship to completely finish
    stroke_fns.wait('step3_surv', 300)

    # concatenate all of the year-separate outputs from 03
    epi_input = pd.DataFrame()
    for year in yearvals:
        df = pd.read_csv('%s/input_%s_%s_%s.csv' %
                         (out_dir, isch_csmr_mv, hem_csmr_mv, year))
        epi_input = epi_input.append(df)
    raw_df = epi_input.copy(deep=True)

    # add on necessary columns for epi uploader
    epi_input = stroke_fns.add_uploader_cols(epi_input)
    epi_input['nid'] = 239169
    epi_input['modelable_entity_id'] = chronic_csmr_me
    epi_input['measure_id'] = 6

    # fill in row_nums
    epi_input = stroke_fns.assign_row_nums(epi_input)

    # fill in uncertainty
    epi_input['measure'] = 'incidence'
    try:
        epi_input = fill_uncertainty(epi_input)  # gets se
        epi_input['effective_sample_size'] = .05 / \
            epi_input['standard_error']**2
        epi_input['sample_size'] = epi_input['effective_sample_size']
        epi_input = fill_mean_ss_cases(epi_input)  # gets cases
    except:
        raise ValueError("uncertainty recalculation failed")
    epi_input.drop(['age_group_id', 'year_id', 'measure'], axis=1,
                   inplace=True)

    # upload using the epi uploader
    upload_sheet.uploadit(
        df=epi_input, engine_factory=enginer, request_id=0,
        user_name='strUser',
        orig_path='isch/hem_stroke incidence * survivorship w/prop from CSMR',
        raw_df=raw_df)
