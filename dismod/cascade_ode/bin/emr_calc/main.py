import pandas as pd
import numpy as np
import db_tools
from epi_uploader.xform.uncertainty import (se_from_ui, fill_uncertainty_type,
                                            fill_uncertainty, upper_from_se)
from epi_uploader.xform.misc_xforms import assign_input_type
from epi_uploader.upload import upload_sheet
from db_tools.core.query_tools import make_sql_obj


#############################################################################
# MODULE API
#############################################################################


def dismod_emr(model_version_id, csmr_cause_id, codcorrect_version_id,
               user_name, remission_df=None, envr="prod"):
    """
    Args:
        model_version_id (int): dismod model_version_id
        csmr_cause_id (int): cause_id of csmr to use in calculation. if -1 is
            passed then will attempt to pull csmr from corresponding
            modelable_entity
        codcorrect_version_id (int): id of codcorrect version to pull
        user_name (string): uwnet id of who is running cascade. used to track
            database inserts and updates.
        remission_df (pandas dataframe, option): dataframe of remission values.
            will apply simple aggregation to mean and standard error.
    """
    assert envr in ["prod", "test"], ("envr must be 'prod' or 'test'")

    emr_for_dismod = emr_calc(model_version_id=model_version_id,
                              csmr_cause_id=csmr_cause_id,
                              codcorrect_version_id=codcorrect_version_id,
                              remission_df=remission_df,
                              envr=envr)
    emr_df = emr_for_dismod.emr
    load_handler = upload_emr(emr_df, user_name=user_name, envr=envr)
    load_handler.load()

#############################################################################
# GLOBAL FUNCTIONS
#############################################################################


def aggregate_se(mean, se):
    """compute aggregated value of standard error"""
    se_ratio = np.sum((se/mean)**2)
    aggmean = np.mean(mean)
    aggse = aggmean * np.sqrt(se_ratio)
    return pd.Series({"mean": aggmean, "se": aggse})


def myround(x, base=1):
    return int(base * round(float(x)/base))


def mtxs_from_prev(x, x_se, csmr, csmr_se):
    """calculate excess mortality rate from prevalence"""
    mean = csmr/x
    se = mean * np.sqrt((x_se/x)**2 + (csmr_se/csmr)**2)
    return pd.Series({"mean": mean, "se": se})


def mtxs_from_inci(x, x_se, csmr, csmr_se, re, re_se, emr, emr_se, acmr,
                   acmr_se):
    """calculate excess mortality rate from incidence"""
    mean = csmr*(re+(acmr-csmr)+emr) / x
    se = mean * np.sqrt((x_se/x)**2 + (csmr_se/csmr)**2 + (re_se/re)**2 +
                        (acmr_se/acmr)**2 + (emr_se/emr)**2)
    return pd.Series({"mean": mean, "se": se})

#############################################################################
# CUSTOM EXCEPTIONS
#############################################################################


class NoNonZeroValues(Exception):
    pass


class NoCSMRValues(Exception):
    pass


class UncertRecalcFailure(Exception):
    pass

#############################################################################
# MAIN CLASSES
#############################################################################


class emr_calc(object):

    def __init__(self, model_version_id, csmr_cause_id, codcorrect_version_id,
                 remission_df=None, envr="prod"):
        self.envr = envr
        self.model_version_id = model_version_id

        # compute remission aggregates
        self.set_remission(remission_df)

        # add ids
        self.csmr_cause_id = csmr_cause_id
        self.codcorrect_version_id = codcorrect_version_id

        # load in adjusted data
        if self.envr == "prod":
            self.adj_data = pd.read_csv(
                ("/ihme/epi/panda_cascade/prod/{mv}/full/locations/1/outputs/"
                 "both/2000/model_data_adj.csv").format(mv=model_version_id))
        else:
            self.adj_data = pd.read_csv(
                ("/ihme/epi/panda_cascade/dev/{mv}/full/locations/1/outputs/"
                 "both/2000/model_data_adj.csv").format(mv=model_version_id))

    def set_remission(self, remission_df):
        """calculate remission aggregates from remission_df"""
        # if remission is not missing try and generate values
        if remission_df is not None:
            mean_re = np.mean(remission_df["mean"])

            # if mean is non zero we can calculate standard error and upper
            if mean_re != 0:
                remission_df["se"] = remission_df.apply(
                    lambda x:
                        se_from_ui(x["mean"], x["lower"], x["upper"],
                                   method="non-ratio"),
                    axis=1)
                se_re = aggregate_se(remission_df["mean"],
                                     remission_df["se"])["se"].item()
                self.re_upper = upper_from_se(mean_re, se_re,
                                              param_type="rate")

                # if upper < 1 it's a long duration so only use prevalence
                self.mean_re = mean_re
                self.se_re = se_re

            # if mean is 0 then we cannot calculate the aggregate standard
            # error and therefore just assign the 0 case
            else:
                self.mean_re = 0
                self.se_re = 0
                self.re_upper = 0
        # if remission is missing then assign the zero case
        else:
            self.mean_re = 0
            self.se_re = 0
            self.re_upper = 0

    @staticmethod
    def construct_template(df, id_var):
        """construct template to map adjusted data to codcorrect data"""
        plate = df.copy(deep=True)

        # get years to round
        plate["year_id"] = (plate["year_end"] + plate["year_start"])/2
        plate["year_id"] = plate.year_id.apply(myround, args=(5,))
        plate["cross"] = 1

        # get ages to ids
        ages_query = """
        SELECT
            age_group_id, age_group_years_start, age_group_years_end
        FROM
            shared.age_group
        WHERE
            age_group_id BETWEEN 2 AND 21
        """
        ages = db_tools.query(ages_query, database="shared")
        ages["cross"] = 1

        # assign ids to spans
        plate = plate.merge(ages, on="cross")
        plate = plate.ix[
            (
                (plate.age_group_years_start > plate.age_start) &
                (plate.age_group_years_end < plate.age_end)
            ) |
            (
                (plate.age_group_years_start < plate.age_end) &
                (plate.age_group_years_end > plate.age_start)
            ) |
            (
                (plate.age_group_years_start == 0) &
                (plate.age_start == 0)
            )]
        return plate[[id_var, "year_id", "age_group_id", "sex_id",
                      "location_id"]]

    @property
    def adj_data(self):
        """retrieve cleaned version of adjusted data"""
        return self._adj_data

    @adj_data.setter
    def adj_data(self, value):
        """clean adjusted data in preparation for claculation"""

        # keep unique
        value = value[["input_data_key", "mean", "lower", "upper"]]
        value.drop_duplicates(inplace=True)

        # query metadata
        value["input_data_key"] = value["input_data_key"].astype(int)
        id_keys = make_sql_obj(value.input_data_key.tolist())
        demo_query = """
        SELECT
            input_data_key,
            input_data_id,
            modelable_entity_id,
            location_id,
            sex_id,
            year_start,
            year_end,
            age_start,
            age_end,
            measure_id
        FROM
            epi.input_data_audit ida
        WHERE
            input_data_key in ({id_keys})
        """.format(id_keys=id_keys)
        wrows = db_tools.query(demo_query, database="epi", envr=self.envr)
        df_wrows = value.merge(wrows, on=["input_data_key"], how="left")

        # subset
        df_wrows = df_wrows.ix[df_wrows.sex_id != 3]  # get rid of both sex
        df_wrows = df_wrows.ix[df_wrows["mean"] > 0]  # get rid of 0 means
        df_wrows = df_wrows.ix[
            ((df_wrows.age_end - df_wrows.age_start) <= 15) |  # > 20 age group
            (df_wrows.age_start >= 80)]  # or terminal
        df_wrows = df_wrows.ix[
            (df_wrows["mean"].notnull()) &
            (df_wrows["lower"].notnull()) &
            (df_wrows["upper"].notnull())]  # mean upper and lower not null
        df_wrows = df_wrows.ix[df_wrows.measure_id.isin([5, 6])]
        if len(df_wrows) == 0:
            raise NoNonZeroValues("no non-zero values for incidence")

        # query for previously calculated emr row numbers
        me_id = df_wrows.modelable_entity_id.unique().item()
        input_data_ids = make_sql_obj(df_wrows.input_data_id.tolist())
        metadata_query = """
        SELECT
            id.row_num as emr_row_num,
            input_data_metadata_value as input_data_id
        FROM
            epi.input_data id
        JOIN
            epi.input_data_metadata idm
                ON id.input_data_id = idm.input_data_id
        WHERE
            modelable_entity_id = {me_id}
            AND input_data_metadata_type_id = 66
            AND input_data_metadata_value in ({input_data_ids})
            AND id.last_updated_action != "DELETE"
        """.format(me_id=me_id, input_data_ids=input_data_ids)
        old_emr = db_tools.query(metadata_query, database="epi",
                                 envr=self.envr)
        old_emr["input_data_id"] = old_emr.input_data_id.astype(float)
        old_emr["input_data_id"] = old_emr.input_data_id.astype(int)
        df_wmetadata = df_wrows.merge(old_emr, on=["input_data_id"],
                                      how="left")

        # compute standard error
        df_wmetadata["se"] = df_wmetadata.apply(
            lambda x:
                se_from_ui(x["mean"], x["lower"], x["upper"],
                           method="non-ratio"),
            axis=1)
        df = df_wmetadata.rename(columns={"mean": "mean_", "se": "se_"})
        df = df.drop(["upper", "lower"], axis=1)
        df = df[(df["mean_"] > 0) & (df["se_"] != 0)]

        # set result on self
        self._adj_data = df

    @property
    def pred_emr(self):

        # get template for merging
        adj_data_plate = self.construct_template(self.adj_data,
                                                 id_var="input_data_key")

        # load in predicted emr
        if self.envr == "prod":
            pred_emr = pd.read_csv(
                ("/ihme/epi/panda_cascade/prod/{mv}/full/locations/1/outputs/"
                 "both/2000/model_estimate_fit.csv").format(
                    mv=self.model_version_id))
        else:
            pred_emr = pd.read_csv(
                ("/ihme/epi/panda_cascade/dev/{mv}/full/locations/1/outputs/"
                 "both/2000/model_estimate_fit.csv").format(
                    mv=self.model_version_id))
        pred_emr = pred_emr.ix[pred_emr.measure_id == 9]
        pred_emr = pred_emr.rename(columns={"pred_mean": "mean_emr",
                                            "pred_lower": "lower_emr",
                                            "pred_upper": "upper_emr"})
        pred_emr = pred_emr.drop(["measure_id"], axis=1)
        pred_emr = pred_emr.merge(adj_data_plate, how="inner",
                                  on=["age_group_id", "sex_id"])

        # aggregate csmr by input_data_key
        pred_emr["se_emr"] = pred_emr.apply(
            lambda x:
                se_from_ui(x["mean_emr"], x["lower_emr"], x["upper_emr"],
                           method="non-ratio"),
            axis=1)
        pred_emr = pred_emr[["input_data_key", "mean_emr", "se_emr"]]
        grouped = pred_emr.groupby(["input_data_key"])
        emr = grouped.apply(
            lambda x: aggregate_se(x["mean_emr"], x["se_emr"])
        ).reset_index()
        emr = emr.rename(columns={"mean": "mean_emr", "se": "se_emr"})
        emr = emr[(emr["mean_emr"] > 0) & (emr["se_emr"] != 0)]
        return emr

    @property
    def acmr(self):

        # get template for merging
        adj_data_plate = self.construct_template(self.adj_data,
                                                 id_var="input_data_key")

        # possible demographics
        locs = make_sql_obj(adj_data_plate.location_id.tolist())
        ages = make_sql_obj(adj_data_plate.age_group_id.tolist())
        sexes = make_sql_obj(adj_data_plate.sex_id.tolist())
        years = make_sql_obj(adj_data_plate.year_id.tolist())

        # pull data
        query = """
        SELECT
            co.location_id,
            co.year_id,
            co.age_group_id,
            co.sex_id,
            co.mean_death/pop_scaled AS mean_acmr,
            co.upper_death/pop_scaled AS upper_acmr,
            co.lower_death/pop_scaled AS lower_acmr
        FROM
            cod.output co
        JOIN
            cod.output_version cov
                ON cov.output_version_id = co.output_version_id
        JOIN
            mortality.output mo
                ON  mo.location_id = co.location_id
                AND mo.age_group_id = co.age_group_id
                AND mo.sex_id = co.sex_id
                AND mo.year_id = co.year_id
        JOIN
            mortality.output_version mov
                ON mov.output_version_id = mo.output_version_id
        WHERE
            cov.output_version_id = {codcorrect_version_id}
            AND cov.best_end IS NULL
            AND mov.is_best = 1
            AND mov.best_end IS NULL
            AND co.cause_id = 294
            AND co.location_id in ({locs})
            AND co.age_group_id in ({ages})
            AND co.year_id in ({years})
            AND co.sex_id in({sexes})
        """.format(locs=locs, ages=ages, sexes=sexes, years=years,
                   codcorrect_version_id=self.codcorrect_version_id)
        acmr = db_tools.query(query, database="cod")
        acmr = acmr.merge(adj_data_plate, how="inner",
                          on=["year_id", "age_group_id",
                              "sex_id", "location_id"])

        # aggregate csmr by input_data_key
        acmr["se_acmr"] = acmr.apply(
            lambda x:
                se_from_ui(x["mean_acmr"], x["lower_acmr"], x["upper_acmr"],
                           method="non-ratio"),
            axis=1)
        acmr = acmr[["input_data_key", "mean_acmr", "se_acmr"]]
        grouped = acmr.groupby(["input_data_key"])
        acmr = grouped.apply(
            lambda x: aggregate_se(x["mean_acmr"], x["se_acmr"])
        ).reset_index()
        acmr = acmr.rename(columns={"mean": "mean_acmr", "se": "se_acmr"})
        acmr = acmr[(acmr["mean_acmr"] > 0) & (acmr["se_acmr"] != 0)]
        return acmr

    @property
    def csmr(self):
        """pull csmr and aggreagate or duplicate to template"""

        # get template for merging
        adj_data_plate = self.construct_template(self.adj_data,
                                                 id_var="input_data_key")

        if self.csmr_cause_id != -1:
            # possible demographics
            locs = make_sql_obj(adj_data_plate.location_id.tolist())
            ages = make_sql_obj(adj_data_plate.age_group_id.tolist())
            sexes = make_sql_obj(adj_data_plate.sex_id.tolist())
            years = make_sql_obj(adj_data_plate.year_id.tolist())

            # pull data
            query = """
            SELECT
                co.location_id,
                co.year_id,
                co.age_group_id,
                co.sex_id,
                co.mean_death/pop_scaled AS mean_csmr,
                co.upper_death/pop_scaled AS upper_csmr,
                co.lower_death/pop_scaled AS lower_csmr
            FROM
                cod.output co
            JOIN
                cod.output_version cov
                    ON cov.output_version_id = co.output_version_id
            JOIN
                mortality.output mo
                    ON  mo.location_id = co.location_id
                    AND mo.age_group_id = co.age_group_id
                    AND mo.sex_id = co.sex_id
                    AND mo.year_id = co.year_id
            JOIN
                mortality.output_version mov
                    ON mov.output_version_id = mo.output_version_id
            WHERE
                cov.output_version_id = {codcorrect_version_id}
                AND cov.best_end IS NULL
                AND mov.is_best = 1
                AND mov.best_end IS NULL
                AND co.cause_id = {cause_id}
                AND co.location_id in ({locs})
                AND co.age_group_id in ({ages})
                AND co.year_id in ({years})
                AND co.sex_id in({sexes})
            """.format(locs=locs, ages=ages, sexes=sexes, years=years,
                       cause_id=self.csmr_cause_id,
                       codcorrect_version_id=self.codcorrect_version_id)
            df = db_tools.query(query, database="cod")
        elif self.csmr_cause_id == -1:
            # pull custom csmr data
            query = """
            SELECT
                input_data_id, location_id, year_start, year_end, age_start,
                age_end, sex_id, mean as mean_csmr, lower as lower_csmr,
                upper as upper_csmr
            FROM epi.input_data id
            JOIN epi.model_version mv
            USING (modelable_entity_id)
            WHERE
                model_version_id = {mv}
                AND measure_id = 15
                AND id.last_updated_action != "DELETE"
            """.format(mv=self.model_version_id)
            df = db_tools.query(query, database="epi")

            # get template for merging with adjusted data
            csmr_data_plate = self.construct_template(df,
                                                      id_var="input_data_id")
            df = df[["input_data_id", "mean_csmr", "lower_csmr", "upper_csmr"]]
            df = df.merge(csmr_data_plate, how="inner", on="input_data_id")
            df.drop('input_data_id', axis=1, inplace=True)
        else:
            raise NoCSMRValues("no corresponding csmr values discovered")

        df = df.merge(adj_data_plate, how="inner",
                      on=["year_id", "age_group_id", "sex_id", "location_id"])

        # aggregate csmr by input_data_key
        df["se_csmr"] = df.apply(
            lambda x:
                se_from_ui(x["mean_csmr"], x["lower_csmr"], x["upper_csmr"],
                           method="non-ratio"),
            axis=1)
        df = df[["input_data_key", "mean_csmr", "se_csmr"]]
        grouped = df.groupby(["input_data_key"])
        df = grouped.apply(
            lambda x: aggregate_se(x["mean_csmr"], x["se_csmr"])
        ).reset_index()
        df = df.rename(columns={"mean": "mean_csmr", "se": "se_csmr"})
        df = df[(df["mean_csmr"] > 0) & (df["se_csmr"] != 0)]

        if len(df) == 0:
            raise NoCSMRValues("no corresponding csmr values discovered")
        return df

    @property
    def emr(self):
        """calculate the excess mortality associated with the adjusted data"""

        # check if we are computing on prevalence only or both.
        if self.re_upper < 1:
            prev_data = self.adj_data[self.adj_data.measure_id == 5]
            inc_data = []
        else:
            prev_data = self.adj_data[self.adj_data.measure_id == 5]
            inc_data = self.adj_data[self.adj_data.measure_id == 6]

        if len(prev_data) > 0:
            prev_data = prev_data.merge(self.csmr, on="input_data_key",
                                        how="inner")

            # compile components
            prev_data = prev_data.drop(["input_data_key"], axis=1)
            prev_data = prev_data.rename(
                columns={"input_data_id": "emr_calc_input_id"})

            # calculate
            emr_prev = prev_data.apply(
                lambda x:
                    mtxs_from_prev(
                        x=x["mean_"],
                        x_se=x["se_"],
                        csmr=x["mean_csmr"],
                        csmr_se=x["se_csmr"]),
                    axis=1)
            emr_prev = pd.concat([prev_data, emr_prev], axis=1)
            emr_prev = emr_prev.drop(["mean_", "se_", "mean_csmr", "se_csmr",
                                     "measure_id"], axis=1)
            emr_prev = emr_prev.rename(columns={"se": "standard_error",
                                                "emr_row_num": "row_num"})
            if len(prev_data) == 0:
                emr_prev = pd.DataFrame()
        else:
            emr_prev = pd.DataFrame()

        if len(inc_data) > 0:

            inc_data = inc_data.merge(self.csmr, on="input_data_key",
                                      how="inner")
            inc_data = inc_data.merge(self.pred_emr, on="input_data_key",
                                      how="inner")
            inc_data = inc_data.merge(self.acmr, on="input_data_key",
                                      how="inner")

            # compile components
            inc_data = inc_data.drop(["input_data_key"], axis=1)
            inc_data = inc_data.rename(
                columns={"input_data_id": "emr_calc_input_id"})

            # calculate
            emr_inc = inc_data.apply(
                lambda x:
                    mtxs_from_inci(
                        x=x["mean_"],
                        x_se=x["se_"],
                        csmr=x["mean_csmr"],
                        csmr_se=x["se_csmr"],
                        re=self.mean_re,
                        re_se=self.se_re,
                        emr=x["mean_emr"],
                        emr_se=x["se_emr"],
                        acmr=x["mean_acmr"],
                        acmr_se=x["se_acmr"]),
                    axis=1)
            emr_inc = pd.concat([inc_data, emr_inc], axis=1)
            emr_inc = emr_inc.drop(["mean_", "se_", "mean_csmr", "se_csmr",
                                    "measure_id", "mean_emr", "se_emr",
                                    "mean_acmr", "se_acmr"], axis=1)
            emr_inc = emr_inc.rename(columns={"se": "standard_error",
                                              "emr_row_num": "row_num"})
            if len(emr_inc) == 0:
                emr_inc = pd.DataFrame()
        else:
            emr_inc = pd.DataFrame()

        emr = pd.concat([emr_prev, emr_inc], axis=0)
        return emr


class upload_emr(object):

    def __init__(self, df, user_name, envr):

        # set environment
        self.envr = envr

        # original input dataframe
        self.user_name = user_name
        self.raw_df = df
        self.proc_df = df.copy(deep=True)

        # setup database connections
        self.enginer = db_tools.EngineFactory()
        self.enginer.define_engine(
            engine_name='epi_writer', host_key='epi_' + self.envr,
            default_schema='epi', user_name=strUser",
            password="strPass")
        self.enginer.define_engine(
            engine_name='epi_reader', host_key='epi_' + self.envr,
            default_schema='epi')
        self.enginer.define_engine(
            engine_name='ghdx_reader', default_schema='ghdx',
            host="strConn",
            user_name="strUser", password="strPass")

    @property
    def proc_df(self):
        return self._proc_df

    @proc_df.setter
    def proc_df(self, value):
        """property setter. add all missing columns that are required by db
        and calculate uncertainty intervals"""

        # make copy
        df = value.copy(deep=True)

        # fill all columns
        df["measure_id"] = 9
        df["nid"] = 237616
        df["underlying_nid"] = np.NAN
        df["source_type_id"] = 36
        df["sampling_type_id"] = np.NAN
        df["representative_id"] = -1
        df["urbanicity_type_id"] = 0
        df["recall_type_id"] = -1
        df["recall_type_value"] = np.NAN
        df["unit_type_id"] = 1
        df["unit_value_as_published"] = 1
        df["outlier_type_id"] = 0
        df["upper"] = np.NAN
        df["lower"] = np.NAN
        df["sample_size"] = np.NAN
        df["effective_sample_size"] = np.NAN
        df["cases"] = np.NAN
        df["design_effect"] = np.NAN
        df["uncertainty_type"] = np.NAN
        df["uncertainty_type_value"] = np.NAN
        df["inserted_by"] = self.user_name
        df["last_updated_by"] = self.user_name
        df["parent_id"] = np.NAN
        df["input_type_id"] = np.NAN
        df["uncertainty_type_id"] = 1
        df["note_modeler"] = np.NAN
        df["note_SR"] = np.NAN

        # fill row_num
        df = self.assign_row_nums(df, envr=self.envr)

        # fill uncertainty
        df["measure"] = "mtexcess"
        try:
            df = fill_uncertainty_type(df)
            df = fill_uncertainty(df)
        except:
            raise UncertRecalcFailure("uncertainty recalculation failed")
        df = df.drop(["measure", "uncertainty_type"], axis=1)

        # fill input_type
        self._proc_df = assign_input_type(df)

    # assign all data from previous runs that we aren't recalculating to be
    # outliers
    @property
    def depricated_df(self):
        """pull down all data that is not in the current dismod run. set the
        outlier status to 1."""
        # get ids that we have
        me_id = make_sql_obj(self.proc_df.modelable_entity_id.unique().item())
        calc_input_ids = self.proc_df.emr_calc_input_id.tolist()

        # query for stuff we don't have. set outlier to 1 on these data
        old_data_query = """
        SELECT
            id.input_data_id,
            row_num,
            modelable_entity_id,
            location_id,
            sex_id,
            year_start,
            year_end,
            age_start,
            age_end,
            nid,
            underlying_nid,
            source_type_id,
            sampling_type_id,
            measure_id,
            representative_id,
            urbanicity_type_id,
            recall_type_id,
            recall_type_value,
            unit_type_id,
            unit_value_as_published,
            uncertainty_type_id,
            uncertainty_type_value,
            input_type_id,
            mean,
            upper,
            lower,
            standard_error,
            effective_sample_size,
            sample_size,
            cases,
            design_effect,
            4 as outlier_type_id,
            NULL AS note_SR,
            NULL AS note_modeler,
            input_data_metadata_value as emr_calc_input_id
        FROM
            epi.input_data id
        JOIN
            epi.input_data_metadata idm
                ON id.input_data_id = idm.input_data_id
                AND input_data_metadata_type_id = 66
        WHERE
            modelable_entity_id = {me_id}
            AND input_data_metadata_type_id = 66
            AND id.last_updated_action != "DELETE"
        """.format(me_id=me_id)
        old_emr = db_tools.query(old_data_query, database="epi",
                                 envr=self.envr)
        old_emr["emr_calc_input_id"] = old_emr.emr_calc_input_id.astype(float)
        old_emr["emr_calc_input_id"] = old_emr.emr_calc_input_id.astype(int)
        old_emr = old_emr[
            ~old_emr.emr_calc_input_id.isin(calc_input_ids)]
        old_emr = old_emr.drop(["input_data_id"], axis=1)
        return old_emr

    @staticmethod
    def assign_row_nums(df, envr="prod"):
        """Fills in missing row_nums in input dataframe

        Args:
            df (object): pandas dataframe object of input data
            engine (object): ihme_databases class instance with default
                engine set
            me_id (int): modelable_entity_id for the dataset in memory

        Returns:
            Returns a copy of the dataframe with the row_nums filled in,
            increment strarting from the max of the database for the given
            modelable_entity.
        """
        me_id = df.modelable_entity_id.unique().item()
        query = """
        select
            ifnull(max(row_num),0)+1
        from
            epi.input_data
        where
            modelable_entity_id = {me_id}
            """.format(me_id=me_id)
        newMaxRowNum = db_tools.query(query, database="epi", envr=envr
                                      ).iloc[0, 0]

        # fill in new row_nums that are currently null
        nullCond = df.row_num.isnull()
        lengthMissingRowNums = len(df[nullCond])
        if lengthMissingRowNums == 0:
            return df
        else:
            df.ix[nullCond, 'row_num'] = range(
                newMaxRowNum, lengthMissingRowNums + newMaxRowNum
            )

            # check if row nums assigned properly
            assert not any(df.row_num.duplicated()), '''
                Duplicate row numbers assigned'''
            assert max(df.row_num) == (
                lengthMissingRowNums + newMaxRowNum - 1
            ), 'Row numbers not assigned correctly'
            return df

    def load(self):
        """ loads excess mortality data and outliers old data.
        basic upload from the uploader"""
        load_df = pd.concat([self.proc_df, self.depricated_df])
        upload_sheet.uploadit(
            df=load_df, engine_factory=self.enginer, request_id=0,
            user_name=self.user_name, orig_path="dismod emr calculation",
            raw_df=self.raw_df)
