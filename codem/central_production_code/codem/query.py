'''
This File Contains all the helper functions for performing an SQL query of the
COD database. The goal of this script is to create wrapper functions around
sql syntax so that individuals can retrieve data from the databased without a
deep understanding of the complex database. In addition these functions will be
used within the CODEm rewrite.
'''

import sqlalchemy as sql
import pandas as pd
import queryStrings as QS
import numpy as np
import sys


def getModelParams(model_version_id, update=False):
    '''
    integer -> dictionary

    Given an integer that indicates a valid model version id  the function will
    return a dictionary with keys indicating the model parameters start age,
    end age, sex, start year, cause, and whether to run covariate selection or
    not. "update" indicates whether during the querying process the database
    should be updated to running during the querying process, default is False.
    True should be used when running CODEm.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = "SELECT * FROM cod.model_version WHERE model_version_id = {0}"
    model = conn.execute(call.format(model_version_id)).fetchone()
    model = dict(model.items())
    model["start_year"] = 1980
    call = "SELECT acause FROM shared.cause WHERE cause_id = {0}"
    aC = conn.execute(call.format(model["cause_id"])).fetchone()["acause"]
    model["acause"] = aC
    call = "UPDATE cod.model_version SET status = 0 WHERE model_version_id = {0}"
    if update: conn.execute(call.format(model_version_id))
    conn.close()
    return model


def codQuery(cause_id, sex, start_year, start_age, end_age, location_set_version_id):
    '''
    strings indicating model parameters -> Pandas Data Frame

    Given a list of model parameters will query from the COD database and
    return a pandas data frame. The data frame contains the base variables
    used in the CODEm process.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.codQueryStr.format(c=cause_id, s=sex, sy=start_year, sa=start_age,
                                 ea=end_age, loc_set_id=location_set_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    df['national'] = df['national'].map(lambda x: x == 1).astype(int)
    conn.close()
    return df


def mortQuery(sex, start_year, start_age, end_age, location_set_version_id):
    '''
    strings indicating model parameters -> Pandas Data Frame

    Given a set of model parameters will query from the mortality database and
    return a pandas data frame. The data frame contains the base variables
    used in the CODEm process.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.mortQueryStr.format(sa=start_age, ea=end_age, sy=start_year, s=sex, loc_set_id=location_set_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    return df


def locQuery(locations, location_set_version_id):
    '''
    list -> Pandas Data Frame

    Given a list of country ID numbers will query from the mortality database
    and return a pandas data frame. The data frame contains columns for
    location, super region and region ID.
    '''
    loc = "(" + ",".join([str(l) for l in set(locations)]) + ")"
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.locQueryStr.format(loc=loc, loc_set_id=location_set_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    df["path_to_top_parent"] = \
        df["path_to_top_parent"].map(lambda x: ",".join((x[2:]).split(",")[:3]))
    arr = np.array(list(df.path_to_top_parent.map(lambda x: x.split(","))))
    df2 = pd.DataFrame(arr.astype(int),
                       columns=["super_region", "region", "country_id"])
    df2.loc[df.location_id == 385, "country_id"] = 385  # patch for puerto_rico and usa subnationals
    return pd.concat([df["location_id"], df2], axis=1)


def excludeRegions(df, regionsExclude):
    '''
    (Pandas data frame, list of regions) -> Pandas data frame

    Given a pandas data frame and a list of regions to exclude, which
    can include id codes for super region, region, country or subnational,
    will remove all of the regions of the data frame.
    '''
    exclude = np.array(regionsExclude.split()).astype(int)
    SN_remove = df.location_id.map(lambda x: x not in exclude)
    C_remove = df.country_id.map(lambda x: x not in exclude)
    R_remove = df.region.map(lambda x: x not in exclude)
    SR_remove = df.super_region.map(lambda x: x not in exclude)
    df2 = df[(SN_remove) & (C_remove) & (R_remove) & (SR_remove)]
    df2.reset_index(drop=True, inplace=True)
    return df2


def data_variance(df, response):
    '''
    (data frame, string) -> array

    Given a data frame and a response type generates an estimate of the variance
    for that response based on sample size. A single array is returned where
    each observation has been sampled 100 times from a normal distribution to
    find the estimate.
    '''
    cf = df.cf.values
    N = df.sample_size.values
    env = df.envelope.values
    pop = df["pop"].values
    cf[cf <= 0.00000001] = np.NaN
    cf[cf >= 1.] = np.NaN
    cf_sd = (cf * (1-cf) / N)**.5
    cf_sd[cf_sd > .5] = .5  # cap cf_sd
    f = lambda i: np.random.normal(cf[i], cf_sd[i], 100) * (env[i]/pop[i])
    if response == "lt_cf":
        f = lambda i: np.random.normal(cf[i], cf_sd[i], 100)
    draws = np.array(map(f, range(len(cf))))
    draws[draws <= 0] = np.NaN
    if response == "lt_cf":
        draws = np.log(draws/ (1 - draws))
    elif response == "ln_rate":
        draws = np.log(draws)
    draws_masked = np.ma.masked_array(draws, np.isnan(draws))
    sd_final = np.array(draws_masked.std(axis=1))
    sd_final[sd_final == 0.] = np.NaN
    return sd_final


def data_process(df):
    '''
    Pandas data frame -> Pandas data frame

    Given a pandas data frame that was queried for CODEm returns a
    Pandas data frame that has columns added for mixed effect analysis and
    is re-indexed after removing countries with full sub-national data.
    '''
    df2 = df.copy()
    remove = df2[df2.country_id != df2.location_id].country_id.unique()
    df2 = df2[df2.location_id.map(lambda x: x not in remove)]
    df2 = df2.replace([np.inf, -np.inf], np.nan)
    df2["region_nest"] = df2.super_region.map(str) + ":" + df2.region.map(str)
    df2["age_nest"] = df2.region_nest + ":" + df2.age.map(str)
    df2["country_nest"] = df2.region_nest + ":" + df2.country_id.map(str)
    df2["sub_nat_nest"] = df2.country_nest + ":" + df2.location_id.map(str)
    df2["ln_rate_sd"] = data_variance(df2, "ln_rate")
    df2["lt_cf_sd"] = data_variance(df2, "lt_cf")
    df2.reset_index(inplace=True, drop=True)
    return df2


def queryCodData(cause_id, sex, start_year, start_age, end_age, regionsExclude, location_set_version_id):
    '''
    list -> Pandas data frame

    Given a set of model parameters, will return a pandas data frame
    which contains the identification variables necessary to complete
    the algorithms in CODEm.
    '''
    cod = codQuery(cause_id, sex, start_year, start_age, end_age, location_set_version_id)
    mort = mortQuery(sex, start_year, start_age, end_age, location_set_version_id)
    loc = locQuery(mort.location_id.values, location_set_version_id)
    loc = excludeRegions(loc, regionsExclude)
    mortDF = mort.merge(loc, how='right', on=['location_id'])
    codDF = cod.merge(mortDF, how='right',
                      on=['location_id', 'age', 'sex', 'year'])
    codDF['ln_rate'] = np.log(codDF['cf'] * codDF['envelope'] / codDF['pop'])
    codDF['lt_cf'] = np.log(codDF['cf'].map(lambda x: x/(1.0-x)))
    codDF.loc[codDF["cf"] == 1, "ln_rate"] = np.NAN
    df = data_process(codDF)
    return df


def covMetaData(model_version_id):
    '''
    integer -> Pandas data frame

    Given an integer that represents a valid model ID number, will
    return a pandas data frame which contains the covariate model ID's
    for that model as well as the metadata needed for covariate selection.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.metaQueryStr.format(model_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    return df


def covQuery(covID, location_set_version_id):
    '''
    integer -> Pandas data frame

    Given an integer which represents a valid covariate ID will return a data
    frame which contains a unique value for each country, year, age group.
    This data may be aggregated in some form as well.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.cvQueryStr.format(mvid=covID, loc_set_id=location_set_version_id)
    result = conn.execute(call)
    try:
        df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    except ValueError:
        sys.stderr.write("There appears to be an error with covariate id {0}".format(covID))
        sys.exit()
    df = df.rename(columns={"mean_value":df["name"][0]})
    conn.close()
    return df


def transform(data, trans):
    '''
    (array, string) -> array

    Given an array of numeric data and a string indicating the type of
    transformation desired will return an array with the desired transformation
    applied. If the string supplied is invalid the same array will be returned.
    '''
    if trans == "ln": return np.log(data)
    elif trans == "lt": return np.log(data / (1. - data))
    elif trans == "sq": return data**2
    elif trans == "sqrt": return data**.05
    elif trans == "scale1000": return data * 1000.
    else: return data


def transDF(df, var, trans):
    '''
    (Pandas data frame, string, string) -> Pandas data frame

    Given a pandas data frame, a string that represents a valid numeric
    variable in that column and a string representing a type of transformation,
    will return a Pandas data frame with the variable transform as specified.
    Additionally the name of the variable will be changed to note the
    transformation.
    '''
    df2 = df
    df2[var] = transform(df2[var].values, trans)
    if trans in ["ln", "lt", "sq", "sqrt", "scale1000"]:
        df2 = df2.rename(columns={var: (trans + "_" + var)})
    return df2


def lagIt(df, var, lag):
    '''
    (Pandas data frame, string, string) -> Pandas data frame

    Given a pandas data frame, a string that represents a valid numeric
    variable in that column and an integer representing the number of years to
    lag, will return a Pandas data frame with the specified lag applied.
    Additionally, the name of the variable will be changed to note the
    transformation.
    '''
    if lag is None: return df
    if np.isnan(lag): return df
    df2 = df
    df2["year"] = df2["year"] + lag
    df2 = df2.rename(columns={var: ("lag" + str(lag) + "_" + var)})
    return df2


def createAgeDF():
    '''
    None -> Pandas data frame

    Creates a Pandas data frame with two columns, all the age groups currently
    used in analysis at IHME as noted by the data base as well as a column with
    the code used for the aggregate group.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call ="SELECT age_group_id AS all_ages FROM age_group WHERE age_group_plot = 1"
    result = conn.execute(call)
    ageDF = pd.DataFrame(result.fetchall(), columns=["all_ages"])
    ageDF['age'] = 22
    ageDF = ageDF[(ageDF.all_ages >= 2) & (ageDF.all_ages <= 21)]
    conn.close()
    return ageDF


def ageSexData(df, sex):
    '''
    (Pandas data frame, integer) -> Pandas Data frame

    Given a Pandas data frame and an integer which represents the desired sex
    of the analysis, will return a data frame with a value for each age group
    and only for the desired sex.
    '''
    df2 = df.copy(); ageDF = createAgeDF()
    if len(df2["age"].unique()) == 1:
        df2 = df2.merge(ageDF, on="age")
        df2 = df2.drop("age", 1)
        df2 = df2.rename(columns={"all_ages":"age"})
    if len(df2["sex"].unique()) == 1: df2["sex"] = sex
    df2 = df2[df2["sex"] == sex]
    return df2


def getCVDF(covID, trans, lag, offset, sex, location_set_version_id):
    '''
    (integer, string, integer, integer) -> Pandas data frame

    Given a covariate id number, a string representing a transformation
    type, an integer representing lags of the variable and an integer
    representing which sex to restrict the data to, will return a
    data frame which contains teh values for that covariate transformed
    as specified.
    '''
    df = covQuery(covID, location_set_version_id)
    df[df.columns.values[0]] = df[df.columns.values[0]] + offset
    df = transDF(df, df.columns.values[0], trans)
    df = lagIt(df, df.columns.values[0], lag)
    df = ageSexData(df, sex)
    df = df.drop("name", 1)
    df = df.replace([np.inf, -np.inf], np.nan)
    df = df.astype("float32")
    df = df[df.year >= 1980]
    return df


def getCovData(model_version_id, location_set_version_id):
    '''
    integer -> (Pandas data frame, Pandas data frame)

    Given an integer which represents a valid model version ID, returns
    two Pandas data frames. The first is a data frame which contains the
    covariate data for that model. The second is the meta data of those
    same covarites which will be used for the model selection process.
    '''
    covs = covMetaData(model_version_id)
    sex = getModelParams(model_version_id)["sex_id"]
    df = getCVDF(covs.covariate_model_id[0], covs.transform_type_short[0],
                 covs.lag[0], covs.offset[0], sex, location_set_version_id)
    for i in range(1, len(covs)):
        dfTemp = getCVDF(covs.covariate_model_id[i],
                         covs.transform_type_short[i], covs.lag[i], covs.offset[i], sex, location_set_version_id)
        df = df.merge(dfTemp, how="outer", on=["location_id", "age", "sex", "year"])
    n = df.drop(["location_id", "age", "sex", "year"], axis=1).columns.values
    covs["name"] = n
    return df, covs


def getCodemInputData(model_version_id):
    '''
    integer -> (Pandas data frame, Pandas data frame)

    Given an integer which represents a valid model version ID, returns
    two pandas data frames. The first is the input data needed for
    running CODEm models and the second is a data frame of meta data
    needed for covariate selection.
    '''
    model = getModelParams(model_version_id)
    df = queryCodData(cause_id=model["cause_id"], sex=model["sex_id"],
                      start_year=model["start_year"],
                      start_age=model["age_start"], end_age=model["age_end"],
                      regionsExclude=model["locations_exclude"],
                      location_set_version_id=model["location_set_version_id"])
    cvDF, priors = getCovData(model_version_id, model["location_set_version_id"])
    df = df[(df.year >= model["start_year"]) & (model["age_start"] <= df.age) &
            (df.age <= model["age_end"])]
    df2 = df.merge(cvDF, how="left", on=["location_id", "age", "sex", "year"])
    covs = df2[priors.name.values]
    df = df.drop_duplicates()
    covs = covs.loc[df.index]
    df.reset_index(drop=True, inplace=True)
    covs.reset_index(drop=True, inplace=True)
    columns = df.columns.values[df.dtypes.values == np.dtype('float64')]
    df[columns] = df[columns].astype('float32')
    return df, covs, priors


def get_site_data(path, var, trans, lag):
    '''
    (string, string, string, integer) -> Pandas Data Frame

    Given a valid path within the J drive returns a transformed Pandas data
    frame of the specified transformation type and lag time.
    '''

    df = pd.read_csv("/home/j/" + path)
    df = transDF(df, var, trans)
    df = lagIt(df, var, lag)
    return df


def get_raw_reference(priorsDF, loc):
    '''
    (Pandas data frame, string)

    Given a priors Data frame attempts to retrieve all the site specific or
    reference data based on the chosen value of [loc].
    '''
    l = []
    for i in range(len(priorsDF)):
        if priorsDF[loc][i] != '':
            try:
                l.append(get_site_data(priorsDF[loc][i],
                                       priorsDF.var[i],
                                       priorsDF.transform_type_short[i],
                                       priorsDF.lag[i]))
            except:
                l = l
    return l


def get_raw_reference_data(priorsDF, df, loc):
    '''
    (Pandas data frame, Pandas data frame, string)

    Given a priors data frame, a data frame for each country, age, year of
    interest and a string [loc] indicating a variable in the pandas data frame
    retrieves all the data from the specified column to be attached to the
    country, age, year data frame.
    '''
    l = get_raw_reference(priorsDF, loc)
    sub = priorsDF[priorsDF[loc] != ""]
    for d in l:
        df = df.merge(d, how="left")
    try:
        return df[sub.name.values]
    except:
        return pd.DataFrame()


def write_submodel(model_version_id, submodel_type_id, submodel_dep_id, weight, rank):
    '''
    (int, int, int, float, int) -> int

    Write a submodel to the table and get the id back
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.submodel_query_str.format(model_version_id, submodel_type_id,
                                        submodel_dep_id, weight, rank)
    conn.execute(call)
    call = QS.submodel_get_id.format(model_version_id, rank)
    result = conn.execute(call)
    submodel_id = result.fetchone()["submodel_version_id"]
    conn.close()
    return submodel_id


def write_submodel_covariate(submodel_id, list_of_covariate_ids):
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    for cov in list_of_covariate_ids:
        call = QS.submodel_cov_write_str.format(submodel_id, cov)
        conn.execute(call)
    conn.close()


def write_model_pv(tag, value, model_version_id):
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.pv_write.format(tag, value, model_version_id)
    conn.execute(call)
    conn.close()


def write_model_output(df_true, model_version_id, sex_id):
    df = df_true.copy()
    df["sex"] = sex_id
    columns = ["draw_%d" % i for i in range(1000)]
    df[columns] = df[columns].values / df["envelope"].values[..., np.newaxis]
    df["mean_cf"] = df[columns].mean(axis=1)
    df["lower_cf"] = df[columns].quantile(.025, axis=1)
    df["upper_cf"] = df[columns].quantile(.975, axis=1)
    df = df[["mean_cf", "lower_cf", "upper_cf", "year", "age", "sex", "location_id"]]
    df["model_version_id"] = model_version_id
    df.rename(columns={'year': 'year_id', 'sex': 'sex_id', 'age': 'age_group_id'}, inplace=True)
    DB = "strConnection"
    engine = sql.create_engine(DB); con = engine.connect().connection
    df.to_sql("model", con, flavor="mysql", if_exists="append", index=False, chunksize=15000)
    con.close()


def get_submodel_summary(model_version_id):
    '''
    (int) -> data_frame

    Retrieves the summary submodel rank table for a particular model.
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.submodel_summary_query.format(model_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    return df


def get_codem_run_time(model_version_id):
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = QS.codem_run_time.format(model_version_id=model_version_id)
    result = conn.execute(call)
    minutes = np.array(result.fetchall())
    conn.close()
    return float(minutes[0, 0])


def submodel_covs(submodel_version_id):
    """
    :param submodel_version_id: integer representing a codem submodel version id
    :return: Pandas data frame with information on submodel covariates

    Given a submodel version id returns the covariates that were used in the
    construction of that model.
    """
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = '''
    SELECT covariate_name_short FROM shared.covariate
        WHERE covariate_id IN (SELECT covariate_id from covariate.data_version WHERE data_version_id IN
            (SELECT data_version_id FROM covariate.model_version
                WHERE model_version_id IN
                (SELECT covariate_model_version_id FROM cod.submodel_version_covariate
                    WHERE submodel_version_id={submodel_version_id})))
    '''.format(submodel_version_id=submodel_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    df["submodel_version_id"] = submodel_version_id
    return df


def get_submodels(model_version_id):
    """
    :param model_version_id: integer representing a codem model version id
    :return: Pandas Data frame with submodels and corresponding information
    """
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    call = '''
    SELECT submodel_version_id, rank, weight, submodel_type_id, submodel_dep_id
    FROM cod.submodel_version
    WHERE model_version_id = {model_version_id}
    '''.format(model_version_id=model_version_id)
    result = conn.execute(call)
    df = pd.DataFrame(result.fetchall()); df.columns = result.keys()
    conn.close()
    return df


def all_submodel_covs(model_version_id):
    """
    :param model_version_id: integer representing a codem model version id
    :return: Pandas Data frame with submodels, covariates, and corresponding information
    """
    submodels = get_submodels(model_version_id)
    covs = pd.concat([submodel_covs(x) for x in submodels.submodel_version_id],
                     axis=0).reset_index(drop=True)
    df = covs.merge(submodels, how="left")
    df = df.sort(["rank", "covariate_name_short"])
    call = '''
    SELECT submodel_type_id, submodel_type_name FROM cod.submodel_type;
    '''
    DB = "strConnection"
    engine = sql.create_engine(DB); conn = engine.connect()
    result = conn.execute(call)
    df2 = pd.DataFrame(result.fetchall()); df2.columns = result.keys()
    conn.close()
    df = df.merge(df2, how="left")
    call = '''
    SELECT submodel_dep_id, submodel_dep_name FROM cod.submodel_dep;
    '''
    engine = sql.create_engine(DB); conn = engine.connect()
    result = conn.execute(call)
    df2 = pd.DataFrame(result.fetchall()); df2.columns = result.keys()
    conn.close()
    df = df.merge(df2, how="left")
    df.drop(["submodel_type_id", "submodel_dep_id"],inplace=True, axis=1)
    df = df.sort(["rank", "covariate_name_short"])
    df["approximate_draws"] = np.round(df.weight.values * 1000.)
    return df


def truncate_draws(mat, percent=95):
    """
    :param mat:     array where rows correspond to observations and columns draws
    :param percent: a value between 0 and 100 corresponding to the amount of
                    data to keep
    :return:        array where row data outside row percentile has been
                    replaced with the mean.
    """
    assert 0 < percent < 100, "percent is out of range"
    low_bound = (100. - float(percent)) / 2.
    hi_bound = 100. - low_bound
    matrix = np.copy(mat)
    row_lower_bound = np.percentile(matrix, low_bound, axis=1)
    row_upper_bound = np.percentile(matrix, hi_bound, axis=1)
    replacements = (matrix.T < row_lower_bound).T | (matrix.T > row_upper_bound).T
    replacements[matrix.std(axis=1) < 10**-5, :] = False
    masked_matrix = np.ma.masked_array(matrix, replacements)
    row_mean_masked = np.mean(masked_matrix, axis=1)
    row_replacements = np.where(replacements)[0]
    matrix[replacements] = row_mean_masked[row_replacements]
    return matrix


def acause_from_id(model_version_id):
    """
    Given a valid model version id returns the acause associated with it.
    :param model_version_id: int
        valid model version id
    :return: str
        string representing an acause
    """
    DB = "strConnection"
    call = '''
    SELECT
    acause
    FROM
    shared.cause
    WHERE
    cause_id = (SELECT cause_id
                FROM cod.model_version
                WHERE model_version_id = {})
    '''.format(model_version_id)
    engine = sql.create_engine(DB); conn = engine.connect()
    acause = conn.execute(call).fetchone()["acause"]
    conn.close()
    return acause
