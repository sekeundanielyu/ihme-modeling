##############################################################################
# STANDARD FILE STRUCTURE
##############################################################################

INPUT_DATA_DIR = '/ihme/scratch/projects/sdg/input_data/'
DRAW_COLS = ['draw_' + str(i) for i in range(0, 1000)]
INDICATOR_ID_COLS = ['indicator_id', 'location_id', 'year_id']
INDICATOR_DATA_DIR = "/ihme/scratch/projects/sdg/indicators/"
SUMMARY_DATA_DIR = "/ihme/scratch/projects/sdg/summary/"
PAPER_OUTPUTS_DIR = "/home/j/WORK/10_gbd/04_journals/" \
          "gbd2015_capstone_lancet_SDG/04_outputs/"

##############################################################################
# MORTALITY RATES - FROM DALYNATOR
##############################################################################

# version numbers are written explicitly so that new sdg versions are
# made intentionally different from previous ones (note exception with como)
DALY_VERS = 117
DALY_TEMP_OUT_DIR = '/ihme/scratch/projects/sdg/temp/dalynator'
DALY_TEMP_OUT_DIR_DELETE = '/ihme/scratch/projects/sdg/temp/dalynator_DEL'

# these are all noted in the google doc, but they are:
# inj_suicide
# inj_trans_road
# inj_poisoning
# inj_homicide
DALY_ALL_AGE_CAUSE_IDS = [
    718,
    689,
    700,
    724,
    729,
    730
]

# 491: cvd, 410: _neo, 587: diabetes, 508: resp
# these are special because they only keep age thirty to seventy
DALY_THIRTY_SEVENTY_CAUSE_IDS = [
    491,
    410,
    587,
    508
]

# note the causes for which 1985+ data should be pulled
PRE_1990_CAUSES = [
    729,
    730
]

# COLUMNS THAT OUTPUT SHOULD BE UNIQUE ON
DALY_GROUP_COLS = ['location_id', 'year_id', 'cause_id',
                   'measure_id', 'metric_id', 'age_group_id', 'sex_id']

##############################################################################
# INCIDENCE RATES
##############################################################################

# this doesnt affect the code because gopher cant actually take a como
# version number as input. So this should actually be written as a function
# pulling the best como version from the database
COMO_VERS = 96
COMO_TEMP_OUT_DIR = '/ihme/scratch/projects/sdg/temp/como/'
COMO_TEMP_OUT_DIR_DELETE = '/ihme/scratch/projects/sdg/temp/como_DEL/'

COMO_INC_CAUSE_IDS = [
     297,
    298,
     299,
    345,
    402
]

COMO_PREV_CAUSE_IDS = [
    346,
    347,
    350,
    351,
    352,
    353,
    354,
    355,
    356,
    357,
    359,
    360,
    364,
    405
]

COMO_GROUP_COLS = ['location_id', 'year_id', 'cause_id',
                   'measure_id', 'metric_id', 'age_group_id', 'sex_id']


##############################################################################
# COVARIATES
##############################################################################

# Claire takin care of business

##############################################################################
# SUMMARY EXPOSURE VARIABlES
##############################################################################

SEV_VERS = 177
SEV_DIR = '/ihme/centralcomp/sev/{v}/'.format(v=SEV_VERS)
SEV_PATH = SEV_DIR + 'draws/{rei_id}.dta'

# pull draws for each of these
SEV_REI_IDS = [
    102,
    83,
    84,
    238,
    87
]

SEV_GROUP_COLS = ['location_id', 'year_id', 'age_group_id',
                  'sex_id', 'measure_id',
                  'metric_id', 'rei_id']
##############################################################################
# Risk prevalence
##############################################################################
# These draws shouldn't change? Should probably ask RF modelers if they've been
# updated since july 5th
RISK_EXPOSURE_REI_IDS = {
    166,  # smoking_direct_prev (cat1)
    167   # abuse_ipv_exp (cat1)
}

RISK_EXPOSURE_REI_IDS_MALN = [
    241,  # nutrition_wasting childhood stunting (cat1 + cat2)
    240  # nutrition_stunting childhood wasting (cat1 + cat2)
]

RISK_EXPOSURE_GROUP_COLS = ['location_id', 'year_id', 'age_group_id',
                            'sex_id', 'rei_id', 'measure_id', 'metric_id']
# so many model version ids .. what to do here not sure
RISK_EXPOSURE_VERS = 4

RISK_EXPOSURE_TEMP_OUT_DIR = '/ihme/scratch/projects/sdg/temp/risk_exposure/'
RISK_EXPOSURE_TEMP_OUT_DIR_DELETE = '/ihme/scratch/projects/' \
    'sdg/temp/risk_exposure_DEL/'

##############################################################################
# Risk attributable burden
##############################################################################

RISK_BURDEN_DALY_VERS = 117
RISK_BURDEN_OUTDIR = ("/ihme/scratch/projects/sdg/input_data/"
                      "risk_burden/{}".format(
                          RISK_BURDEN_DALY_VERS))
RISK_BURDEN_REI_IDS = [
    85,  # this eventually needs to be a custom risk cluster, but air will do
    82   # 'wash' (indicator 3.9.2)
]
RISK_BURDEN_DALY_REI_IDS = [
    126
]

##############################################################################
# MATERNAL MORTALITY RATE
##############################################################################

# get draws of MMR from their draw directory
MMR_VERS = 258
MMR_DIR = '/ihme/centralcomp/maternal_mortality/mmr/submission_draws/'
MMR_OUTDIR = '/ihme/scratch/projects/sdg/' \
             'input_data/mmr/{v}/'.format(v=MMR_VERS)
MMR_ID_COLS = ['location_id', 'year_id', 'age_group_id',
               'sex_id', 'measure_id', 'metric_id',
               'cause_id']


##############################################################################
# PROBABILITY OF DEATH
##############################################################################

# how to track what version I'm pulling?
QX_DIR = '/ihme/gbd/WORK/02_mortality/03_models/5_lifetables/' \
         'results/lt_loc/with_shock/qx/'
QX_VERS = '2016_04_20'

##############################################################################
# EPI
##############################################################################

# model_version_id to use for childhood overweight
EPI_CHILD_OVRWGT_VERS = '2016_08_05'
EPI_CHILD_OVRWGT_GROUP_COLS = ['location_id', 'year_id', 'age_group_id',
                               'sex_id', 'measure_id', 'metric_id',
                               'modelable_entity_id']

##############################################################################
# ASFR
##############################################################################
ASFR_DIR = "/ihme/scratch/projects/sdg/input_data/asfr/"

##############################################################################
# SKILLED BIRTH ATTENDANTS (SBA)
##############################################################################
SBA_PATH = "/ihme/scratch/projects/sdg/input_data/" \
           "uhc_expanded/sba/sba_draws.csv"
# try to change this to the date for significant changes
SBA_VERS = "2016_07_27"
SBA_OUT_PATH = "/ihme/scratch/projects/sdg/input_data/" \
               "sba/{v}/sba_draws_clean.h5".format(v=SBA_VERS)

##############################################################################
# COMPLETENESS
##############################################################################

COMPLETENESS_FILE = "/home/j/WORK/10_gbd/04_journals/" \
                    "gbd2015_capstone_lancet_SDG/02_inputs/" \
                    "completeness/comp_sdgs.csv"

COMPLETENESS_FILE_CHN = "/home/j/WORK/10_gbd/04_journals/" \
                        "gbd2015_capstone_lancet_SDG/02_inputs/" \
                        "completeness/chn_comp.csv"

COMPLETENESS_FILE_IND = "/home/j/WORK/10_gbd/04_journals/" \
                        "gbd2015_capstone_lancet_SDG/02_inputs/" \
                        "completeness/" \
                        "ind_srs_pop_deaths_withenv_1995_2013.csv"

COMPLETENESS_GROUP_COLS = ['location_id', 'year_id', 'sex_id',
                           'measure_id', 'metric_id']
COMPLETENESS_DATA_COL = 'trunc_pred'

COMPLETENESS_VERS = 'GBD_2015_final'
COMPLETENESS_OUT_DIR = "/ihme/scratch/projects/sdg/input_data/" \
                       "completeness/{v}".format(v=COMPLETENESS_VERS)


##############################################################################
# POP WEIGHTED MEAN PM 2.5
##############################################################################

MEAN_PM25_VERS = 11

MEAN_PM25_INFILE = "/ihme/gbd/WORK/05_risk/02_models/02_results/" \
                   "air_pm/exp/{v}/final_draws/" \
                   "all.csv".format(v=MEAN_PM25_VERS)


MEAN_PM25_GROUP_COLS = ['location_id', 'year_id', 'metric_id', 'measure_id']

MEAN_PM25_OUTFILE = "/ihme/scratch/projects/sdg/input_data/" \
                    "frostad_pop_weighted_air_pm/" \
                    "{v}/air_pm_draws_clean.h5".format(v=MEAN_PM25_VERS)

##############################################################################
# MET NEED
##############################################################################

MET_NEED_VERS = 204

MET_NEED_INFILE = "/home/j/Project/Coverage/Contraceptives/" \
                  "2015 Contraceptive Prevalence Estimates/" \
                  "gpr_data/input/unmet_need/" \
                  "results/{v}/met_need_collapsed" \
                  "_draws.csv".format(v=MET_NEED_VERS)

MET_NEED_OUTFILE = "/ihme/scratch/projects/sdg/" \
                   "input_data/met_need/" \
                   "{v}/met_need_clean.h5".format(v=MET_NEED_VERS)

MET_NEED_GROUP_COLS = ['location_id', 'year_id',
                       'metric_id', 'measure_id']
