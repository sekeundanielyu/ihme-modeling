import query as Q
import queryStrings as QS
import knockout as ko
import numpy as np
import pandas as pd
import os
import sqlalchemy as sql
import matplotlib
import pylab
import matplotlib.pyplot as plt
import emailer as email
matplotlib.use('Agg')


class Inputs:
    def __init__(self, model_version_id, update):
        self.data_frame, self.covariates, self.priors = \
            Q.getCodemInputData(model_version_id)
        self.cv_names = self.priors.name.values
        self.reference = Q.get_raw_reference_data(self.priors, self.data_frame,
                                                  "reference")
        self.site_spec = Q.get_raw_reference_data(self.priors, self.data_frame,
                                                  "site_specific")
        self.knockouts = None
        self.response_list = None
        self.best_psi = None
        self.ensemble_preds = None
        for k, v in Q.getModelParams(model_version_id, update).items():
            setattr(self, k, v)
        self.psi_values = np.arange(self.psi_weight_min, self.psi_weight_max +
                                    self.psi_weight_int, self.psi_weight_int)
        self.draws = None
        self.country_df = None
        self.region_df = None
        self.super_region_df = None
        self.age_df = None
        self.global_df = None
        self.submodel_covariates = None
        self.draw_id = None
        self.submodel_rmse = None
        self.submodel_trend = None
        self.model_dir = "/ihme/codem/data/{0}/{1}".format(self.acause, self.model_version_id)

    def __repr__(self):
        m, c = (self.model_version_id, self.acause)
        return str("Inputs for model version {0}, cause: {1}").format(m, c)

    def create_knockouts(self, seed=None):
        if seed is None:
            seed = self.model_version_id
        self.knockouts = ko.generate_knockouts(self.data_frame,
                                               self.holdout_number, seed)

    def label_submodels(self, space_ids, mixed_ids):
        self.submodel_covariates["space"] = \
            {space_ids[x]: self.submodel_covariates["space"][x]
             for x in range(len(space_ids))}
        self.submodel_covariates["mixed"] = \
            {mixed_ids[x]: self.submodel_covariates["mixed"][x]
             for x in range(len(mixed_ids))}

    def add_draws_to_df(self, truncate=False, percentile=99):
        self.draws = np.exp(self.draws) * self.data_frame["pop"].values[:, np.newaxis]
        if truncate:
            self.draws = Q.truncate_draws(self.draws, percent=percentile)
        draw_df = pd.DataFrame(self.draws)
        draw_df.columns = \
            ["draw_%d" % i for i in range(0, draw_df.shape[1])]
        self.draws = None
        self.data_frame = pd.concat([self.data_frame, draw_df], axis=1)
        self.data_frame.drop_duplicates(["year", "location_id", "age"], inplace=True)
        self.data_frame.reset_index(drop=True, inplace=True)

    def bare_necessities(self):
        '''
        Keep only the portions of data neccesary for writing.
        '''
        variables = ["super_region", "region", "country_id", "location_id",
                     "age", "year", "cf", "envelope", "pop"]
        self.data_frame = self.data_frame[variables]

    def aggregate_draws(self):
        '''
        (self) -> None

        Aggregate the draws up to the country, region, and super region levels.
        We also need to throw in the age aggregates in globally.
        '''
        self.age_location_df = \
            self.data_frame.groupby(['location_id', 'year'], as_index=False).sum()
        self.age_location_df["age"] = 22
        self.country_df = \
            self.data_frame.groupby(['country_id', 'age', 'year'], as_index=False).sum()
        self.country_df.drop('location_id', axis=1, inplace=True)
        self.country_df.rename(columns={'country_id': 'location_id'}, inplace=True)
        countries = np.setdiff1d(self.country_df.location_id.unique(),
                                 self.data_frame.location_id.unique())
        self.country_df = self.country_df[self.country_df["location_id"].isin(countries)]
        self.country_df.reset_index(drop=True, inplace=True)
        self.age_country_df = \
            self.country_df.groupby(['location_id', 'year'], as_index=False).sum()
        self.age_country_df["age"] = 22
        self.region_df = \
            self.data_frame.groupby(['region', 'age', 'year'], as_index=False).sum()
        self.region_df.drop(['location_id', 'country_id'], axis=1, inplace=True)
        self.region_df.rename(columns={'region': 'location_id'}, inplace=True)
        self.age_region_df = \
            self.region_df.groupby(['location_id', 'year'], as_index=False).sum()
        self.age_region_df["age"] = 22
        self.super_region_df = \
            self.data_frame.groupby(['super_region', 'age', 'year'], as_index=False).sum()
        self.super_region_df.drop(['location_id', 'country_id', 'region'], axis=1, inplace=True)
        self.super_region_df.rename(columns={'super_region': 'location_id'}, inplace=True)
        self.age_super_region_df = \
            self.super_region_df.groupby(['location_id', 'year'], as_index=False).sum()
        self.age_super_region_df["age"] = 22
        self.age_df = \
            self.data_frame.groupby(['age', 'year'], as_index=False).sum()
        self.age_df.drop(['super_region', 'country_id', 'region'], axis=1, inplace=True)
        self.age_df.location_id = 1
        self.global_df = self.data_frame.groupby(["year"], as_index=False).sum()
        self.global_df["location_id"] = 1
        self.global_df["age"] = 22
        self.global_df.drop(["super_region", "region", "country_id"], axis=1, inplace=True)
        self.data_frame["sex"] = self.sex_id
        self.data_frame["cause"] = self.acause

    def write_draws(self):
        '''
        (self) -> None

        Write the most granular results to an HDF file. Make the keys a
        location_id year for ease of access in cod correct use. Includes all of
        the draws from codem as well as some other variables such as age, sex,
        population, envelope.
        '''
        if self.sex_id == 1:
            sex = "male"
        else:
            sex = "female"
        keep_cols = ["draw_%d" % i for i in range(0, 1000)] + \
            ["envelope", "pop", "age", "sex", "year", "location_id"]
        if not os.path.exists("draws"):
            os.makedirs("draws")
        df2 = self.data_frame[keep_cols]
        df2 = df2.rename(columns={"age": "age_group_id", "sex": "sex_id", "year": "year_id"})
        df2["measure_id"] = 1
        df2["cause_id"] = self.cause_id
        df2.location_id = df2.location_id.astype(int)
        df2.age_group_id = df2.age_group_id.astype(int)
        df2.year_id = df2.year_id.astype(int)
        df2.to_hdf('draws/deaths_{sex}.h5'.format(sex=sex), 'data', mode='w', format='table',
                   data_columns=['location_id', 'year_id', 'age_group_id'])
        pd.DataFrame({"keys": ['location_id', 'year_id',
                               'age_group_id']}).to_hdf('draws/deaths_{sex}.h5'.format(sex=sex),
                                                        key="keys", mode='a', format='table')

    def write_submodel_covariates(self):
        '''
        (self) -> None

        For every submodel that is used in codem write all the covariates for
        that submodel into the database for the ability to skip covariate
         selection in future runs of codem.
        '''
        link = {self.priors.name[i]: self.priors.covariate_model_id[i]
                for i in range(len(self.priors))}
        for model in self.submodel_covariates.keys():
            for submodel in self.submodel_covariates[model].keys():
                dic = self.submodel_covariates[model][submodel]
                submodel_covariate_ids = [link[c] for c in dic]
                Q.write_submodel_covariate(submodel, submodel_covariate_ids)

    def write_model_mean(self):
        '''
        (self) -> None

        Write the submodel means of the codem run for all submodels which we
        have more than 50 draws for.
        '''
        valid_models = [m for m in set(self.draw_id) if self.draw_id.count(m) >= 100]
        DB = "strConnection"
        for model in valid_models:
            columns = ["draw_%d" % i for i in np.where(np.array(self.draw_id) == model)[0]]
            for df_true in [self.data_frame, self.country_df, self.region_df,
                       self.super_region_df, self.age_df, self.global_df]:
                df = df_true.copy()
                df["sex"] = self.sex_id
                if df.shape[0] == 0:
                    continue
                df_sub = df.loc[:, ["year", "location_id", "sex", "age", "envelope"] + columns]
                df_sub.loc[:,columns] = df_sub[columns].values / df_sub["envelope"].values[..., np.newaxis]
                df_sub["mean_cf"] = df_sub[columns].mean(axis=1)
                df_sub = df_sub[["year", "location_id", "sex", "age", "mean_cf"]]
                df_sub.rename(columns={'year': 'year_id', 'sex': 'sex_id', 'age': 'age_group_id'}, inplace=True)
                df_sub["model_version_id"] = self.model_version_id
                df_sub["submodel_version_id"] = model
                df_sub["lower_cf"] = 0; df_sub["upper_cf"] = 0
                engine = sql.create_engine(DB); con = engine.connect().connection
                df_sub.to_sql("submodel", con, flavor="mysql", if_exists="append", index=False, chunksize=15000)
                con.close()
        for df_true in [self.data_frame, self.country_df, self.region_df,
                        self.super_region_df, self.age_df, self.global_df,
                        self.age_location_df, self.age_country_df, self.age_region_df,
                        self.age_super_region_df]:
            if df_true.shape[0] == 0:
                    continue
            Q.write_model_output(df_true, self.model_version_id, self.sex_id)

    def write_pv(self):
        tags = ["pv_rmse_in", "pv_rmse_out", "pv_coverage_in", "pv_coverage_out",
                "pv_trend_in", "pv_trend_out", "pv_psi", "status"]
        values = [self.pv_rmse_in, self.pv_rmse_out, self.pv_coverage_in,
                  self.pv_coverage_out, self.pv_trend_in, self.pv_trend_out,
                  self.best_psi, 1]
        for i in range(len(tags)):
            Q.write_model_pv(tags[i], float(values[i]), self.model_version_id)

    def create_global_table(self):
        df = self.global_df.copy()
        columns = ["draw_%d" % (i) for i in range(100)]
        df["mean_deaths"] = df[columns].mean(axis=1)
        df["lower_deaths"] = df[columns].quantile(.025, axis=1)
        df["upper_deaths"] = df[columns].quantile(.975, axis=1)
        plt.figure(figsize=(16, 12))
        plt.plot(df.year.values, df.mean_deaths.values, label="Mean Death Prediction")
        plt.fill_between(df.year.values, df.lower_deaths.values, df.upper_deaths.values,
                         alpha=.3, color='blue', label='95% confidence interval')
        plt.legend(loc=0)
        plt.xlabel("$Year$", fontsize=20)
        plt.ylabel("$Deaths$", fontsize=20)
        plt.title("CODEm Estimates", fontsize=24)
        pylab.savefig("global_estimates.png")

    def submodel_summary_table(self):
        df = Q.get_submodel_summary(self.model_version_id)
        covs = self.submodel_covariates["mixed"]
        covs.update(self.submodel_covariates["space"])
        df["rmse_out"] = df.submodel_version_id.map(lambda x: self.submodel_rmse[x])
        df["trend_out"] = df.submodel_version_id.map(lambda x: self.submodel_trend[x])
        df["covariates"] = df.submodel_version_id.map(lambda x: ', '.join(covs[x]))
        df.sort("rank", inplace=True)
        df.reset_index(drop=True, inplace=True)
        return df

    def create_email_body(self):
        self.create_global_table()
        df = Q.get_submodel_summary(self.model_version_id)
        covs = self.submodel_covariates["mixed"]
        covs.update(self.submodel_covariates["space"])
        df["rmse_out"] = df.submodel_version_id.map(lambda x: self.submodel_rmse[x])
        df["trend_out"] = df.submodel_version_id.map(lambda x: self.submodel_trend[x])
        df["covariates"] = df.submodel_version_id.map(lambda x: ', '.join(covs[x]))
        df.sort("rank", inplace=True)
        df.reset_index(drop=True, inplace=True)
        validation_table = QS.validation_table.format(RMSE_in_ensemble=self.pv_rmse_in,
                                                      RMSE_out_ensemble=self.pv_rmse_out,
                                                      trend_in_ensemble=self.pv_trend_in[0],
                                                      trend_out_ensemble=self.pv_trend_out,
                                                      coverage_in_ensemble=self.pv_coverage_in,
                                                      coverage_out_ensemble=self.pv_coverage_out,
                                                      RMSE_out_sub=df[df["rank"] == 1]["rmse_out"][0],
                                                      trend_out_sub=df[df["rank"] == 1]["trend_out"][0])
        validation_table = validation_table.replace("\n", "")
        frame_work = QS.frame_work.format(user=self.inserted_by,
                                          description=self.description,
                                          sex=["", "males", "females"][self.sex_id],
                                          start_age=self.age_start,
                                          end_age=self.age_end,
                                          run_time=Q.get_codem_run_time(self.model_version_id),
                                          codx_link="http://models.ihme.washington.edu/codx/",
                                          best_psi=self.best_psi,
                                          validation_table=validation_table,
                                          number_of_submodels=df.shape[0],
                                          submodel_table=df.to_html(index=False),
                                          path_to_outputs=self.model_dir)
        frame_work = frame_work.replace("\n", "")
        return frame_work

    def send_email(self):
        '''
        (self) -> None

        Send an email, and create a png of global estimates, but only if the
        user is not codem or nmarquez.
        '''
        email_body = self.create_email_body()
        if self.inserted_by == "codem" or self.inserted_by == "nmarquez" or self.inserted_by == "unknown":
            return None
        s = email.Server("strConnection", 'strUser', 'strPassword')
        # add covariate run csv
        df_cov = Q.all_submodel_covs(self.model_version_id)
        df_cov.to_csv("submodel_covs.csv", index=False)
        s.connect()
        e = email.Emailer(s)
        e.add_attachment('global_estimates.png')
        e.add_attachment("submodel_covs.csv")
        e.add_recipient('%s@uw.edu' % self.inserted_by)
        e.set_subject('CODEm run update for {}'.format(self.acause))
        e.set_body(email_body)
        e.send_email()
        s.disconnect()

    def post_processing(self):
        self.bare_necessities()
        self.add_draws_to_df()
        self.aggregate_draws()
        self.write_draws()
        self.write_submodel_covariates()
        self.write_model_mean()
        self.write_pv()
        self.send_email()
