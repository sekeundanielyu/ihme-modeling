from __future__ import print_function
import pandas as pd
import os
import sys
import shutil
import argparse
from threading import Thread

sys.path.append("/home/j/WORK/10_gbd/00_library/transmogrifier/")
import transmogrifier.gopher as gopher

sys.path.append('/ihme/code/python_shared/')
import cluster_helpers as ch

from getpass import getuser
sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw
import sdg_utils.queries as qry
import sdg_utils.tests as sdg_test


def submit_job_location_draws(indicator_type, location_id):
    """Submit a cluser job to process a location year."""
    log_dir = "/share/temp/sgeoutput/sdg/"
    if not os.path.exists(log_dir):
        os.mkdir(log_dir)
        os.mkdir(os.path.join(log_dir, 'errors'))
        os.mkdir(os.path.join(log_dir, 'output'))
    jobname = "sdg_loc_{it}_{loc}".format(it=indicator_type, loc=location_id)
    worker = "{}/data_prep/prep_draw_files_parallel.py".format(SDG_REPO)
    shell = "{}/sdg_utils/run_on_cluster.sh".format(SDG_REPO)
    args = {
        '--process': "run_location",
        '--indicator_type': indicator_type,
        '--location_id': location_id
    }
    job_id = ch.qsub(worker, shell, 'proj_sdg', custom_args=args,
                     name=jobname, log_dir=log_dir, slots=6, verbose=True)
    return job_id


def submit_job_collect(job_ids, indicator_type):
    """Submit a cluster job to collect processed draws."""
    log_dir = "/share/temp/sgeoutput/sdg/"
    if not os.path.exists(log_dir):
        os.mkdir(log_dir)
        os.mkdir(os.path.join(log_dir, 'errors'))
        os.mkdir(os.path.join(log_dir, 'output'))
    jobname = "sdg_collect_{it}".format(it=indicator_type)
    worker = "{}/data_prep/prep_draw_files_parallel.py".format(SDG_REPO)
    shell = "{}/sdg_utils/run_on_cluster.sh".format(SDG_REPO)
    args = {
        '--process': "collect",
        '--indicator_type': indicator_type,
    }
    holds = job_ids
    job_id = ch.qsub(worker, shell, 'proj_sdg', custom_args=args,
                     name=jobname, log_dir=log_dir, slots=20,
                     holds=holds, verbose=True)
    return job_id


def custom_age_weights(age_group_id_start, age_group_id_end):
    """Get age weights scaled to age group start and end"""
    t = qry.get_age_weights(3)  # default is gbd 2010? Why?

    t = t.query(
        'age_group_id >= {start} & age_group_id <= {end}'.format(
            start=age_group_id_start, end=age_group_id_end)
    )
    # scale weights to 1
    t['age_group_weight_value'] =  \
        t['age_group_weight_value'] / \
        t['age_group_weight_value'].sum()

    return t


def age_standardize(df, indicator_type):
    """Make each draw in the dataframe a rate, then age standardize.
    """

    if indicator_type == 'como':
        group_cols = dw.COMO_GROUP_COLS
    elif indicator_type == 'dalynator':
        group_cols = dw.DALY_GROUP_COLS
    else:
        raise ValueError("bad type: {}".format(indicator_type))

    assert set(df.sex_id.unique()) == {3}, \
        'falsely assuming only both sexes included'
    assert set(df.metric_id.unique()) == {1}, \
        'falsely assuming df is all numbers'
    db_pops = qry.get_pops(both_sexes=True)
    db_pops = db_pops[['location_id', 'year_id',
                       'sex_id', 'age_group_id', 'mean_pop']]

    # do special things for the 30-70 causes
    # merge special age weights on these cause ids using is_30_70 indicator
    df['is_30_70'] = df.cause_id.apply(
        lambda x: 1 if x in dw.DALY_THIRTY_SEVENTY_CAUSE_IDS else 0)

    # get age weights with is_30_70 special weights
    age_weights = custom_age_weights(2, 21)
    age_weights['is_30_70'] = 0
    age_weights_30_70 = custom_age_weights(11, 18)
    age_weights_30_70['is_30_70'] = 1
    age_weights = age_weights.append(age_weights_30_70, ignore_index=True)

    df = df.merge(db_pops, how='left')
    assert df.mean_pop.notnull().values.all(), 'merge with pops failed'
    df = df[df.mean_pop.notnull()]
    df = df.merge(age_weights, on=['age_group_id', 'is_30_70'], how='left')
    assert df.age_group_weight_value.notnull().values.all(), 'age weights merg'

    # concatenate the metadata with the draw cols times the pop
    # this multiplies each draw column by the mean_pop column
    df = pd.concat(
        [
            df[group_cols],
            df[dw.DRAW_COLS].apply(
                lambda x: (x / df['mean_pop']) *
                df['age_group_weight_value']
            )
        ],
        axis=1
    )

    # now a rate, age standardized
    df['metric_id'] = 3
    df['age_group_id'] = 27

    df = df.groupby(group_cols, as_index=False)[dw.DRAW_COLS].sum()
    return df


def write_output(df, indicator_type, location_id):
    """Write output in way that is conducive to parallelization.

    I want to make final output by cause id with location aggregates, and
    cod-correct data doesn't have location aggregates. In order to do that,
    I'm going to write all the data that goes into each location for a cause
    in a folder, gbd_id / location_id. A location_id contains all the most
    detailed locations contained in that location_id, which could be one
    location id for Andhra Pradesh, Urban, or all of them for Global.

    1. Splits dataframe into each gbd_id, which is final form for each type.
    2. Copies the location data for each location in the location path
    3. Writes the file to gbd_id / location_id named with the original
        location_id
    """
    if indicator_type == 'dalynator':
        out_dir = dw.DALY_TEMP_OUT_DIR
        gbd_id_col = 'cause_id'
    elif indicator_type == 'como':
        out_dir = dw.COMO_TEMP_OUT_DIR
        gbd_id_col = 'cause_id'
    elif indicator_type == 'risk_exposure':
        out_dir = dw.RISK_EXPOSURE_TEMP_OUT_DIR
        gbd_id_col = 'rei_id'
    else:
        raise ValueError("bad type: {}".format(indicator_type))
    # write to each path location so that aggregates can be made later
    for gbd_id in set(df[gbd_id_col]):
        gbd_id_dir = os.path.join(out_dir, str(gbd_id))
        # make sure the directory exists (probably create it)
        try:
            if not os.path.exists(gbd_id_dir):
                os.mkdir(gbd_id_dir)
        except OSError:
            pass
        t = df.ix[df[gbd_id_col] == gbd_id]
        # write location
        out_path = '{d}/{location_id}.h5'.format(
            d=gbd_id_dir,
            location_id=location_id
        )
        t.to_hdf(out_path, key="data", format="f")


def process_risk_exposure_draws(location_id, test=False):
    """Return yearly age standardized estimates of each rei_id.

    1. Use gopher to pull data for each rei_id for the location_id
    the location id, and all years.
    2. Keep appropriate categories for given rei_id
    3. Draws only come with male/female in rates -
        change to cases and make both sexes aggregate.
    4. Revert back to rates and age standardize using custom weights.

    Arguments:
        location_id: the location_id to process

    Returns:
        pandas dataframe like so:
        [ID_COLS] : [dw.DRAW_COLS]
    """
    dfs = []

    version_df = pd.DataFrame()
    all_ids = set(dw.RISK_EXPOSURE_REI_IDS).union(
        set(dw.RISK_EXPOSURE_REI_IDS_MALN))
    if test:
        years = [2015]
    else:
        years = []
    for rei_id in all_ids:
        print("pulling {r}".format(r=rei_id))
        df = gopher.draws(
            {"rei_ids": [rei_id]},
            source='risk',
            draw_type='exposure',
            location_ids=[location_id],
            year_ids=years,
            age_group_ids=[],
            sex_ids=[1, 2],
            num_workers=5
        )
        # remove any other ages besides gbd ages
        df = df.query('age_group_id >= 2 & age_group_id <= 21')
        # only reporting since 1990
        df = df.query('year_id>=1990')

        if rei_id == 167:
            # change IPV to just women
            df = df.query('sex_id == 2')

        if rei_id in dw.RISK_EXPOSURE_REI_IDS_MALN:
            # these are childhood stunting - cat1 + cat2 equals <-2 std dev
            df = df.query('parameter=="cat1" | parameter=="cat2"')
        else:
            # cat1 represents the prevalence in these cases (can't test this?)
            df = df.query('parameter=="cat1"')

        # set the rei_id because it isnt in the gopher pull
        df['rei_id'] = rei_id

        # keep track of what model versions where used
        version_df = version_df.append(
            df[
                ['rei_id', 'modelable_entity_id', 'model_version_id']
            ].drop_duplicates(),
            ignore_index=True
        )

        # these are prevalence rates
        df['metric_id'] = 3
        df['measure_id'] = 5

        dfs.append(df[dw.RISK_EXPOSURE_GROUP_COLS + dw.DRAW_COLS])

    df = pd.concat(dfs, ignore_index=True)

    # note the versions used by risk exposure vers (manufactured by me)
    version_df.to_csv(
        "/home/j/WORK/10_gbd/04_journals/"
        "gbd2015_capstone_lancet_SDG/02_inputs/"
        "risk_exposure_versions_{v}.csv".format(v=dw.RISK_EXPOSURE_VERS),
        index=False)

    # COLLAPSE SEX
    print("collapsing sex")
    df = df.merge(qry.get_pops(), how='left')
    assert df.mean_pop.notnull().values.all(), 'merge with pops fail'
    # overriding the sex variable for collapsing
    df['sex_id'] = df.rei_id.apply(lambda x: 2 if x == 167 else 3)

    df = pd.concat([df[dw.RISK_EXPOSURE_GROUP_COLS],
                    df[dw.DRAW_COLS].apply(lambda x: x * df['mean_pop'])],
                   axis=1
                   )
    # so unnecessary programmatically but good for documentation -
    #  these are now prev cases
    df['metric_id'] = 1
    # now that its in cases it is possible to collapse sex
    df = df.groupby(dw.RISK_EXPOSURE_GROUP_COLS, as_index=False).sum()

    # RETURN TO RATES
    print("returning to rates")
    df = df.merge(qry.get_pops(), how='left')
    assert df.mean_pop.notnull().values.all(), 'merge with pops fail'
    df = pd.concat([df[dw.RISK_EXPOSURE_GROUP_COLS],
                    df[dw.DRAW_COLS].apply(lambda x: x / df['mean_pop'])],
                   axis=1
                   )
    df['metric_id'] = 3

    # AGE STANDARDIZE
    print("age standardizing")
    df['is_0_5'] = df.rei_id.apply(
        lambda x: 1 if x in dw.RISK_EXPOSURE_REI_IDS_MALN else 0
    )
    wgts = custom_age_weights(2, 21)
    wgts['is_0_5'] = 0
    wgts_2 = custom_age_weights(2, 5)
    wgts_2['is_0_5'] = 1
    wgts = wgts.append(wgts_2, ignore_index=True)
    df = df.merge(wgts, on=['is_0_5', 'age_group_id'], how='left')
    assert df.age_group_weight_value.notnull().values.all(), \
        'merge w wgts failed'
    df = pd.concat([df[dw.RISK_EXPOSURE_GROUP_COLS],
                    df[dw.DRAW_COLS].apply(
        lambda x: x * df['age_group_weight_value'])],
        axis=1
    )
    df['age_group_id'] = 27
    df = df.groupby(
        dw.RISK_EXPOSURE_GROUP_COLS, as_index=False
    )[dw.DRAW_COLS].sum()

    write_output(df, 'risk_exposure', location_id)
    return df


def process_location_daly_draws(location_id, test=False):
    """Pull mortality numbers, limiting to desired ages by cause

    Gets all years >1990 and ages for the location id as mortality numbers
    from transmogrifier's gopher library
    """
    dfs = []
    cause_age_sets = [
        [dw.DALY_ALL_AGE_CAUSE_IDS, range(2, 22)],
        [dw.DALY_THIRTY_SEVENTY_CAUSE_IDS, range(11, 19)]
    ]
    if test:
        years = [2015]
    else:
        years = []
    for causes, ages in cause_age_sets:
        gbd_ids = {'cause_ids': causes}
        df = gopher.draws(gbd_ids, 'dalynator',
                          location_ids=[location_id], year_ids=years,
                          age_group_ids=ages, sex_ids=[3], verbose=True,
                          num_workers=5,
                          version=113)
        # without this here, it can give a too many inputs error
        df = df.query('metric_id == 1 & measure_id == 1')
        dfs.append(df)
    df = pd.concat(dfs, ignore_index=True)

    df = df.ix[(df['year_id'] >= 1990) |
               ((df['cause_id'].isin(dw.PRE_1990_CAUSES)) &
                (df['year_id'] >= 1985)
                )
               ]

    # make sure it looks like we expect
    assert set(df.age_group_id) == set(range(2, 22)), \
        'unexpected age group ids found'
    assert set(df.sex_id) == set([3]), \
        'unexpected sex ids found'
    if not test:
        assert set(df.ix[df['cause_id'].isin(dw.PRE_1990_CAUSES)].year_id) == \
            set(range(1985, 2016, 1)), \
            'unexpected year ids found'
        assert set(df.ix[
            ~df['cause_id'].isin(dw.PRE_1990_CAUSES)
        ].year_id) == \
            set(range(1990, 2016, 1)), \
            'unexpected year ids found'
    assert set(df.location_id) == set([location_id]), \
        'unexpected location ids found'

    # age standardize
    df = age_standardize(df, 'dalynator')

    # write the output
    write_output(df, 'dalynator', location_id)

    return df


def process_location_como_draws(location_id, measure_id, test=False):
    """Pull indidence rates, merging with population to make cases

    Using COMO because there are plans to make this store each year.

    Gets all years, ages, and sexes for the location id as incidence rates
    from transmogrifier's gopher library, and combines into all ages, both
    sexes cases.
    """
    db_pops = qry.get_pops()
    if measure_id == 6:
        gbd_ids = {'cause_ids': dw.COMO_INC_CAUSE_IDS}
    elif measure_id == 5:
        gbd_ids = {'cause_ids': dw.COMO_PREV_CAUSE_IDS}
    else:
        raise ValueError("bad measure_id: {}".format(measure_id))
    if test:
        years = [2015]
    else:
        years = []
    df = gopher.draws(gbd_ids, 'como', measure_ids=[measure_id],
                      location_ids=[location_id], year_ids=years,
                      age_group_ids=[], sex_ids=[], verbose=True,
                      num_workers=5,
                      version=dw.COMO_VERS)

    # make sure it looks like we expect
    assert set(df.age_group_id) == set(range(2, 22)), \
        'unexpected age group ids found'
    assert set(df.sex_id) == set([1, 2]), \
        'unexpected sex ids found'
    if not test:
        assert set(df.year_id) == set(range(1990, 2016, 5)), \
            'unexpected year ids found'
    assert set(df.location_id) == set([location_id]), \
        'unexpected location ids found'

    # these pull in as rates
    df['metric_id'] = 3

    # merge with pops to transform to cases
    df = df.merge(db_pops, how='left')
    assert df.mean_pop.notnull().values.all(), 'merge with populations failed'

    # concatenate the metadata with the draw cols times the pop
    # this multiplies each draw column by the mean_pop column
    df = pd.concat(
        [
            df[dw.COMO_GROUP_COLS],
            df[dw.DRAW_COLS].apply(lambda x: x * df['mean_pop'])
        ],
        axis=1
    )

    # now its numbers (this line is for readability)
    df['metric_id'] = 1

    # aggregate sexes
    df['sex_id'] = 3

    # collapse sexes together
    df = df.groupby(dw.COMO_GROUP_COLS,
                    as_index=False)[dw.DRAW_COLS].sum()

    # age standardize
    df = age_standardize(df, 'como')

    write_output(df, 'como', location_id)
    return df


def collect_all_processed_draws(indicator_type):
    """Append together all the processed draws and write output per cause id"""
    if indicator_type == 'dalynator':
        gbd_ids = set(dw.DALY_ALL_AGE_CAUSE_IDS).union(
            set(dw.DALY_THIRTY_SEVENTY_CAUSE_IDS))
        group_cols = dw.DALY_GROUP_COLS
        temp_dir = dw.DALY_TEMP_OUT_DIR
        version_id = dw.DALY_VERS
    elif indicator_type in ['como_prev', 'como_inc']:
        if indicator_type == 'como_inc':
            gbd_ids = set(dw.COMO_INC_CAUSE_IDS)
        else:
            gbd_ids = set(dw.COMO_PREV_CAUSE_IDS)
        group_cols = dw.COMO_GROUP_COLS
        temp_dir = dw.COMO_TEMP_OUT_DIR
        version_id = dw.COMO_VERS
    elif indicator_type == 'risk_exposure':
        gbd_ids = set(dw.RISK_EXPOSURE_REI_IDS).union(
            set(dw.RISK_EXPOSURE_REI_IDS_MALN))
        group_cols = dw.RISK_EXPOSURE_GROUP_COLS
        temp_dir = dw.RISK_EXPOSURE_TEMP_OUT_DIR
        version_id = dw.RISK_EXPOSURE_VERS
    else:
        raise ValueError("bad indicator type: {}".format(indicator_type))

    out_dir = '{d}/{it}/{v}'.format(d=dw.INPUT_DATA_DIR,
                                    it=indicator_type, v=version_id)
    if not os.path.exists(out_dir):
        os.makedirs(out_dir)

    err_list = []
    for gbd_id in gbd_ids:
        gbd_id_dir = os.path.join(temp_dir, str(gbd_id))
        processed_draws = os.listdir(gbd_id_dir)
        gbd_id_dfs = []
        for f in processed_draws:
            path = os.path.join(gbd_id_dir, f)
            gbd_id_df = pd.read_hdf(path)
            gbd_id_dfs.append(gbd_id_df)

        gbd_id_df = pd.concat(gbd_id_dfs, ignore_index=True)
        assert not gbd_id_df[group_cols].duplicated().any(), 'duplicates'
        # some locations are strings, make all ints
        gbd_id_df['location_id'] = gbd_id_df.location_id.astype(int)

        try:
            # test that all level three locations are present, but don't break
            #   all the writing if just one is wrong
            sdg_test.all_sdg_locations(gbd_id_df)
            gbd_id_df.to_hdf('{d}/{gbd_id}.h5'.format(
                d=out_dir,
                gbd_id=gbd_id), key="data", format="table",
                data_columns=['location_id', 'year_id']
            )
            print("{g} finished".format(g=gbd_id))
        except ValueError, e:
            err_list.append(e)
            print("Failed: {g}".format(g=gbd_id), file=sys.stderr)
            continue
    for e in err_list:
        # will raise the first error
        raise(e)


def run_all(indicator_type, test=False):
    """Run each cod correct location-year draw job"""

    # set some locals based on indicator type
    if indicator_type == 'dalynator':
        temp_dir = dw.DALY_TEMP_OUT_DIR
        delete_dir = dw.DALY_TEMP_OUT_DIR_DELETE
    elif indicator_type in ['como_prev', 'como_inc']:
        temp_dir = dw.COMO_TEMP_OUT_DIR
        delete_dir = dw.COMO_TEMP_OUT_DIR_DELETE
    elif indicator_type == 'risk_exposure':
        temp_dir = dw.RISK_EXPOSURE_TEMP_OUT_DIR
        delete_dir = dw.RISK_EXPOSURE_TEMP_OUT_DIR_DELETE
    else:
        raise ValueError("{it} not supported".format(it=indicator_type))
    # set location ids to run
    locations = qry.queryToDF(qry.LOCATIONS.format(lsid=1))
    location_ids = list(
        locations.location_id.unique()
    )

    # change those if it is a test
    if test:
        location_ids = [68, 25]

    # make a new directory to use and delete the other one in a new thread
    print("making a new temp directory and starting a thread to delete old...")
    assert os.path.exists(temp_dir), '{} doesnt exist'.format(temp_dir)
    shutil.move(temp_dir, delete_dir)
    # start a thread that deletes the delete dir
    thread_deleting_old = Thread(target=shutil.rmtree, args=(delete_dir, ))
    thread_deleting_old.start()
    os.mkdir(temp_dir)

    print("processing draws...")
    # initialize list of job ids to hold on
    job_ids = []
    for location_id in location_ids:

        job_ids.append(submit_job_location_draws(
            indicator_type,
            location_id)
        )

    print('collecting all output')
    if not test:
        submit_job_collect(job_ids, indicator_type)

    print('waiting for temp dir deletion to finish...')
    thread_deleting_old.join()
    print('... done deleting and all jobs submitted.')


if __name__ == "__main__":

    parser = argparse.ArgumentParser(
        "Process codcorrect draws for SDG analysis."
    )
    parser.add_argument("--process", required=True,
                        choices=["launch", "run_location", "collect"],
                        help="The process to run. "
                        "'launch' to do everything.")
    parser.add_argument("--indicator_type", required=True,
                        choices=["dalynator", "como_inc",
                                 "como_prev", "risk_exposure"],
                        help="The indicator type to run.")
    parser.add_argument("--location_id", type=int,
                        help="When processing a draw, "
                        "the location_id to process")
    args = parser.parse_args()
    test = False
    if args.process == "launch":
        run_all(args.indicator_type, test=test)
    elif args.process == "run_location":
        location_id = args.location_id
        if args.indicator_type == 'dalynator':
            process_location_daly_draws(location_id, test=test)
        elif args.indicator_type == 'como_inc':
            process_location_como_draws(location_id, 6, test=test)
        elif args.indicator_type == 'como_prev':
            process_location_como_draws(location_id, 5, test=test)
        elif args.indicator_type == 'risk_exposure':
            process_risk_exposure_draws(location_id, test=test)
        else:
            raise ValueError("bad type: {}".format(args.indicator_type))
    elif args.process == "collect":
        collect_all_processed_draws(args.indicator_type)
