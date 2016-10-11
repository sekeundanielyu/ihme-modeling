import os
import argparse
import subprocess
import pandas as pd
import numpy as np
import db_tools
os.chdir(os.path.dirname(os.path.realpath(__file__)))
from job_utils import draws, getset


##############################################################################
# globals
##############################################################################


draw_seed = 99502
westrom_mean = .114
westrom_lower = .131
westrom_upper = .096

export_cols = [
    "row_num", "parent_id", "data_sheet_file_path", "input_type",
    "modelable_entity_id", "modelable_entity_name", "underlying_nid", "nid",
    "underlying_field_citation_value", "field_citation_value", "page_num",
    "table_num", "source_type", "location_name", "location_id", "ihme_loc_id",
    "smaller_site_unit", "site_memo", "sex", "sex_issue", "year_start",
    "year_end", "year_issue", "age_start", "age_end", "age_issue",
    "age_demographer", "measure", "mean", "lower", "upper", "standard_error",
    "effective_sample_size", "cases", "sample_size", "design_effect",
    "unit_type", "unit_value_as_published", "measure_issue",
    "measure_adjustment", "uncertainty_type", "uncertainty_type_value",
    "representative_name", "urbanicity_type", "recall_type",
    "recall_type_value", "sampling_type", "response_rate", "case_name",
    "case_definition", "case_diagnostics", "note_modeler", "note_SR",
    "extractor", "is_outlier", "2013_data_id", "specificity", "group",
    "group_review"
]


##############################################################################
# math
##############################################################################

def draw_beta(mean, lower, upper, seed):
    np.random.seed(seed)
    sd = (upper - lower) / (2 * 1.96)
    sample_size = mean * (1 - mean) / sd**2
    alpha = mean * sample_size
    beta = (1 - mean) * sample_size
    draws = np.random.beta(alpha, beta, size=(1000, 1))
    draws = pd.DataFrame(
        draws.T,
        index=[0],
        columns=['draw_%s' % i for i in range(1000)])
    return draws


##############################################################################
# apply westrom proportion
##############################################################################

class Westrom(draws.SquareImport):

    def __init__(self, source_me_id, **kwargs):
        # super init
        super(Westrom, self).__init__(**kwargs)

        # create beta dist
        self.beta = self.get_beta()

        # get draws that we need
        self.input_df = self.import_square(
            gopher_what={"modelable_entity_ids": [source_me_id]},
            source="dismod")

    def get_beta(self):
        # get distribution
        beta = draw_beta(westrom_mean, westrom_lower, westrom_upper,
                         draw_seed)
        beta["joinkey"] = 1
        beta = beta.set_index(["joinkey"])

        # get desired index shape
        idx_df = self.get_index_df().reset_index()
        idx_df["joinkey"] = 1
        idx_df = idx_df.set_index(["joinkey"])

        # merge together
        beta = pd.concat([idx_df, beta], axis=1).reset_index()
        beta = beta.set_index(self.idx_dmnsns.keys())
        beta.drop("joinkey", axis=1, inplace=True)
        return beta

    def apply_westrom(self):
        return self.beta * self.input_df

    def summarize(self, df):
        df = self.apply_westrom()
        summaries = df.reindex(
            index=df.index,
            columns=['mean', 'lower', 'upper'])
        summaries['mean'] = df[self.draw_cols].mean(axis=1)
        summaries[['lower', 'upper']] = np.percentile(
            df[self.draw_cols],
            [2.5, 97.5],
            axis=1
        ).transpose()
        return summaries.reset_index()

    def export_for_upload(self, df, modelable_entity_id, nid):

        # auto fill
        df["row_num"] = np.nan
        df["parent_id"] = np.nan
        df["data_sheet_file_path"] = np.nan
        df["input_type"] = np.nan
        df["modelable_entity_id"] = modelable_entity_id
        df["underlying_nid"] = np.nan
        df["nid"] = nid
        df["underlying_field_citation_value"] = np.nan
        df["field_citation_value"] = np.nan
        df["page_num"] = np.nan
        df["table_num"] = np.nan
        df["source_type"] = "Mixed or estimation"
        df["ihme_loc_id"] = np.nan
        df["smaller_site_unit"] = np.nan
        df["site_memo"] = np.nan
        df["sex_issue"] = 0
        df["year_start"] = df["year_id"]
        df["year_end"] = df["year_id"]
        df["year_issue"] = 0
        df["age_issue"] = 0
        df["age_demographer"] = np.nan
        df["measure"] = "incidence"
        df["standard_error"] = np.nan
        df["effective_sample_size"] = np.nan
        df["cases"] = np.nan
        df["sample_size"] = np.nan
        df["design_effect"] = np.nan
        df["unit_type"] = "Person"
        df["unit_value_as_published"] = 1
        df["measure_issue"] = 0
        df["measure_adjustment"] = np.nan
        df["uncertainty_type"] = "Confidence interval"
        df["uncertainty_type_value"] = 95
        df["representative_name"] = "Not Set"
        df["urbanicity_type"] = "Unknown"
        df["recall_type"] = "Not Set"
        df["recall_type_value"] = np.nan
        df["sampling_type"] = np.nan
        df["response_rate"] = np.nan
        df["case_name"] = np.nan
        df["case_definition"] = np.nan
        df["case_diagnostics"] = np.nan
        df["note_modeler"] = np.nan
        df["note_SR"] = np.nan
        df["extractor"] = "strUser"
        df["is_outlier"] = 0
        df["2013_data_id"] = np.nan
        df["specificity"] = np.nan
        df["group"] = np.nan
        df["group_review"] = np.nan

        # mapped
        # modelable_entity_name
        q = """
        SELECT
            modelable_entity_name
        FROM
            epi.modelable_entity
        WHERE
            modelable_entity_id = {modelable_entity_id}
        """.format(modelable_entity_id=modelable_entity_id)
        me_name = db_tools.query(
            q, database="epi")["modelable_entity_name"].item()
        df["modelable_entity_name"] = me_name

        # location_name
        loc_df = getset.get_current_location_set()
        loc_df = loc_df.ix[
            loc_df["most_detailed"] == 1,
            ["location_id", "location_name"]
        ]
        df = df.merge(loc_df, on="location_id", how="left")

        # sex
        q = "SELECT sex_id, sex FROM shared.sex"
        sex_df = db_tools.query(q, database="shared")
        df = df.merge(sex_df, on="sex_id", how="left")

        # age
        age_df = getset.get_age_group_set(1)
        age_df = age_df.rename(columns={"age_group_years_start": "age_start",
                                        "age_group_years_end": "age_end"})
        df = df.merge(age_df, on="age_group_id", how="left")

        # export
        q = """
        SELECT
            concat(
                "/home/j/WORK/04_epi/01_database/02_data/",
                acause,
                "/",
                modelable_entity_id,
                "/04_big_data"
            ) AS fpath
        FROM
            epi.modelable_entity
        join
            epi.modelable_entity_cause USING (modelable_entity_id)
        join
            shared.cause USING (cause_id)
        join
            epi.modelable_entity_type using (modelable_entity_type_id)
        where
            modelable_entity_cause.last_updated_action != 'DELETE'
            and modelable_entity_id = {modelable_entity_id}
        """.format(modelable_entity_id=modelable_entity_id)
        outdir = db_tools.query(q, database="epi")["fpath"].item()
        if not os.path.exists(outdir):
            os.makedirs(outdir)
        fname = os.path.join(outdir, "westrom_calc.xlsx")

        # export it
        df = df[export_cols]
        df.to_excel(fname, encoding="utf8", sheet_name="extraction")
        return fname

    def upload(self, fpath):
        subprocess.check_output(
            ["env_submit_master.sh",
             "/ihme/code/central_comp/anaconda/bin/",
             "epidb_loaders",
             "python",
             "/ihme/centralcomp/epidb_loaders/bin/request_input_data_load.py",
             "--filepath", fpath,
             "--delete_group", "modelable_entity_id,nid"]
        )


def calculate_westrom(source_me_id, target_me_id):

    # initialize westrom class
    dim = Westrom.default_idx_dmnsns
    dim["measure_id"] = [6]
    dim["sex_id"] = [2]
    west = Westrom(source_me_id=source_me_id, idx_dmnsns=dim)

    # calculate westrom
    west_df = west.apply_westrom()
    west_df = west.summarize(west_df)

    # export and upload
    fpath = west.export_for_upload(west_df, target_me_id, 237616)
    west.upload(fpath)

##############################################################################
# when called as a script
##############################################################################

if __name__ == "__main__":

    # parse command line args
    parser = argparse.ArgumentParser()
    parser.add_argument("--source_me_id", required=True,
                        help="me_id, apply westom to this incidence",
                        type=int)
    parser.add_argument("--target_me_id", required=True,
                        help="me_id, save westom incidence to this",
                        type=int)
    args = vars(parser.parse_args())

    # run function
    calculate_westrom(
        source_me_id=args["source_me_id"],
        target_me_id=args["target_me_id"])
