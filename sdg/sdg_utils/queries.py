import sqlalchemy as sa
import pandas as pd
import os

###############################################################################
# DATABASE FUNCTIONS
###############################################################################


def queryToDF(query,
              host='strHost', db='', user='strUser',
              pwd='strPassword', select=True):
    """Execute a query on the given host with given credentials.

    If select==True, returns a dataframe. If false, returns sqlalchemy result.
    """
    # get the engine
    engine = get_engine(host, db, user, pwd)
    conn = engine.connect()

    # make sure sqlalchemy understands the text
    query = sa.text(query)

    # execute the query
    result = conn.execute(query)

    if not select:
        # close the connection and return the result
        conn.close()
        return result

    # convert the result to a DataFrame object
    df = pd.DataFrame(result.fetchall())
    conn.close()
    if len(df) == 0:
        return pd.DataFrame()
    df.columns = result.keys()
    # make sure there are any results
    assert(result.rowcount > 0)

    return df


def get_engine(host='strHost', db='', user='strUser',
               pwd='strPassword'):
    # build the connection string
    if db == '':
        conn_string = "strConnection"
    else:
        conn_string = "strConnection"
    return sa.create_engine(conn_string)


###############################################################################
# QUERIES
###############################################################################

BEST_SINGLE_YEAR_YLLS = """
    SELECT
        output_table_name
    FROM gbd.compare_version_output cvo
    INNER JOIN
        gbd.compare_version cv using (compare_version_id)
    INNER JOIN
        gbd.compare_version_status cvs using (compare_version_status_id)
    WHERE
    -- single year cod
    cvo.template_id=1
    -- YLLS
    AND cvo.measure_id=4
    -- GBD 2015
    AND cv.gbd_round_id=3
    -- Current Best
    AND cvs.compare_version_status_id=1;
"""

BEST_SINGLE_YEAR_INCIDENCE = """
    SELECT
        output_table_name
    FROM gbd.compare_version_output cvo
    INNER JOIN
        gbd.compare_version cv using (compare_version_id)
    INNER JOIN
        gbd.compare_version_status cvs using (compare_version_status_id)
    WHERE
    -- single year epi
    cvo.template_id=6
    -- Incidence
    AND cvo.measure_id=6
    -- GBD 2015
    AND cv.gbd_round_id=3
    -- Current Best
    AND cvs.compare_version_status_id=1;
"""

LOCATIONS = """
    SELECT *
    FROM shared.location_hierarchy_history lhh
    WHERE lhh.location_set_version_id =
        shared.active_location_set_version({lsid}, 3)
"""

CAUSES = """
    SELECT *
    FROM shared.cause_hierarchy_history chh
    WHERE chh.cause_set_version_id =
        shared.active_cause_set_version(3, 3)
"""

RISKS = """
    SELECT *
    FROM shared.rei_hierarchy_history rhh
    WHERE rhh.rei_set_version_id =
        shared.active_rei_set_version(1, 3)
"""

LIVE_BIRTHS = """
    SELECT
        model.location_id,
        model.year_id,
        model.age_group_id,
        model.sex_id,
        model.mean_value AS asfr
    FROM covariate.model
    JOIN covariate.model_version
        ON model.model_version_id=model_version.model_version_id
    JOIN covariate.data_version
        ON model_version.data_version_id=data_version.data_version_id
    JOIN shared.covariate
        ON data_version.covariate_id=covariate.covariate_id
    WHERE
        covariate.last_updated_action!="DELETE"
        AND is_best=1
        AND covariate.covariate_id= 13
        AND model.age_group_id BETWEEN 8 AND 14
        AND model.year_id > 1989
"""

###############################################################################
# POPUlATIONS
###############################################################################

# Store the envelope version here for sequencing, probably a better structure
#  out there
ENV_VERS = queryToDF("""
    SELECT
        ov.output_version_id
        FROM mortality.output_version ov
        WHERE ov.is_best=1
""", host='strHost').output_version_id.values[0]


def get_pops(both_sexes=False):
    """Get the pop file. Rerun if ENV_VERS out of sync with filename."""
    pop_file = '/ihme/scratch/projects/sdg/temp/pops_v{}.csv'.format(ENV_VERS)
    if not os.path.exists(pop_file):
        db_pops = queryToDF(
            """
            SELECT
                o.location_id,
                o.year_id,
                o.sex_id,
                o.age_group_id,
                o.mean_pop
            FROM mortality.output o
            INNER JOIN mortality.output_version ov
                ON o.output_version_id = ov.output_version_id
                AND ov.output_version_id = {ovid}
            """.format(ovid=ENV_VERS),
            host='strHost')
        db_pops.to_csv(pop_file, index=False)
    df = pd.read_csv(pop_file)
    if both_sexes:
        df = df.query('sex_id == 3')
    return df


def get_age_weights(ref_pop=1):
    """Return the who standard reference population weights."""
    weights = queryToDF(
        """
            SELECT age_group_id, age_group_weight_value
            FROM shared.age_group_weight
            WHERE gbd_round_id={ref_pop};
        """.format(ref_pop=ref_pop)
    )
    return weights


def get_sdi_location(location_id):
    """Get the sdi location for the given location_id"""
    query = """
        SELECT location_id, parent_id
        FROM shared.location_hierarchy_history
        WHERE location_set_version_id =
            shared.active_location_set_version(40, 3)
        AND location_id = {location_id}
    """.format(location_id=location_id)
    df = queryToDF(query)
    assert len(df) == 1, \
        'Location was not in sdi hierarchy: {}'.format(location_id)
    sdi_id = df.parent_id.values[0]
    return sdi_id


def get_sdg_reporting_locations():
    """Get level three + England subnationals with territories removed"""

    # get GBD reporting hierarchy
    df = queryToDF(LOCATIONS.format(lsid=1))

    # remove territories
    territories = ['ASM', 'BMU', 'GRL', 'GUM', 'MNP', 'PRI', 'VIR']
    df = df.ix[~df.ihme_loc_id.isin(territories)]

    # get the levels right - national + UK countries
    is_national = df['level']==3
    is_gbr_country = (df['level']==4) & (df['parent_id']==95)
    df = df.ix[is_national | is_gbr_country]

    return df


def get_indicator_table():
    """Fetch the table of indicator metadata"""
    indic_table = pd.read_csv(
        "/home/j/WORK/10_gbd/04_journals/"
        "gbd2015_capstone_lancet_SDG/02_inputs/indicator_ids.csv"
    )
    return indic_table
