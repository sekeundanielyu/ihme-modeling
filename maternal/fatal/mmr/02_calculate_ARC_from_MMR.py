import pandas as pd
import sys
import glob
import numpy as np
import concurrent.futures as cf

cause_id, out_dir = sys.argv[1:3]
cause_id = int(cause_id)


def add_cols(df):
    df['measure_id'] = 25
    df['cause_id'] = cause_id
    return df

#######################################
# Pull in MMR datasets from last script
#######################################
in_dir = out_dir.rstrip("/multi_year") + "/"
files = glob.glob(in_dir + 'arc_draws_raw_%s_*' % cause_id)


def read_file(f):
    return pd.read_csv(f)

draw_list = []
with cf.ProcessPoolExecutor(max_workers=8) as e:
    for df in e.map(read_file, files):
        draw_list.append(df)
arc_draws = pd.concat(draw_list)

try:
    arc_draws.drop('index', axis=1, inplace=True)
except:
    pass

##################################
# Output ARC in MMR
##################################

# keep all-ages to get one birth number and one row of death draws
# for each year
arc_1054 = arc_draws[arc_draws.age_group_id == 169]
arc_1054.drop(['age_group_id', 'sex_id'], axis=1, inplace=True)
arc_1549 = arc_draws[arc_draws.age_group_id == 24]
arc_1549.drop(['age_group_id', 'sex_id'], axis=1, inplace=True)
arc_1019 = arc_draws[arc_draws.age_group_id == 162]
arc_1019.drop(['age_group_id', 'sex_id'], axis=1, inplace=True)
# divide each death draw by live births to get MMR draws for all-ages
for i in range(1000):
    arc_1054['draw_%s' % i] = ((arc_1054['draw_%s' % i] /
                                arc_1054['births']) * 100000)
    arc_1054.rename(columns={'draw_%s' % i: 'mmr_%s' % i}, inplace=True)
    arc_1549['draw_%s' % i] = ((arc_1549['draw_%s' % i] /
                                arc_1549['births']) * 100000)
    arc_1549.rename(columns={'draw_%s' % i: 'mmr_%s' % i}, inplace=True)
    arc_1019['draw_%s' % i] = ((arc_1019['draw_%s' % i] /
                                arc_1019['births']) * 100000)
    arc_1019.rename(columns={'draw_%s' % i: 'mmr_%s' % i}, inplace=True)
arc_1054.drop('births', axis=1, inplace=True)
arc_1054.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
arc_1549.drop('births', axis=1, inplace=True)
arc_1549.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
arc_1019.drop('births', axis=1, inplace=True)
arc_1019.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)


def create_arc(start_year, end_year, arc_df, age):
    # subset out dataframes for the start and end years
    df = arc_df.copy(deep=True)
    df.set_index('location_id', inplace=True)
    df.replace(0, 1e-9, inplace=True)
    first_year_arc = df[df.year_id == start_year].drop('year_id', axis=1)
    second_year_arc = df[df.year_id == end_year].drop('year_id', axis=1)
    # calculate ARC and put it in a new dataframe
    num = end_year - start_year
    single_year_arc = np.log(second_year_arc / first_year_arc) / num
    # calculate significance
    cols = ['mmr_%s' % i for i in range(0, 1000)]
    p_val = single_year_arc.copy(deep=True)
    p_val['count'] = (p_val[cols] < 0).sum(1)
    p_val['val'] = (1 - (p_val['count'] / 1000))
    p_val['metric_id'] = 6
    mdg_df = single_year_arc.copy(deep=True)
    mdg_df['count'] = (mdg_df[cols] < .0554).sum(1)
    mdg_df['val'] = (1 - (mdg_df['count'] / 1000))
    mdg_df['metric_id'] = 7
    # calculate uppers and lowers
    single_year_arc = single_year_arc.transpose().describe(
        percentiles=[.025, .975]).transpose()[['2.5%', '50%', '97.5%']]
    single_year_arc.rename(columns={'2.5%': 'lower',
                                    '50%': 'val',
                                    '97.5%': 'upper'},
                           inplace=True)
    single_year_arc.index.rename('location_id', inplace=True)

    # add on all necessary identifying columns and append dfs
    single_year_arc['metric_id'] = 3
    single_year_arc = pd.concat([single_year_arc, p_val, mdg_df])
    single_year_arc.reset_index(inplace=True)
    single_year_arc['year_start_id'] = start_year
    single_year_arc['year_end_id'] = end_year
    single_year_arc['age_group_id'] = age
    single_year_arc['sex_id'] = 2
    return single_year_arc

# create single year ARC datasets
all_1054_df = pd.DataFrame()
all_1549_df = pd.DataFrame()
all_1019_df = pd.DataFrame()
for year in range(1990, 2016):
    start_year = year
    end_year = year + 1
    single_year_1054_arc = create_arc(start_year, end_year, arc_1054, 169)
    all_1054_df = all_1054_df.append(single_year_1054_arc)
    single_year_1549_arc = create_arc(start_year, end_year, arc_1549, 24)
    all_1549_df = all_1549_df.append(single_year_1549_arc)
    single_year_1019_arc = create_arc(start_year, end_year, arc_1019, 162)
    all_1019_df = all_1019_df.append(single_year_1019_arc)
all_1054_df = add_cols(all_1054_df)
all_1054_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_1054_df.to_csv('%s/single_year_1054_arc_%s.csv' % (out_dir, cause_id),
                   index=False)
all_1549_df = add_cols(all_1549_df)
all_1549_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_1549_df.to_csv('%s/single_year_1549_arc_%s.csv' % (out_dir, cause_id),
                   index=False)
all_1019_df = add_cols(all_1019_df)
all_1019_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_1019_df.to_csv('%s/single_year_1019_arc_%s.csv' % (out_dir, cause_id),
                   index=False)

# create period ARC datasets
all_periods_1054_list = []
all_periods_1549_list = []
all_periods_1019_list = []
start_years = [1995, 1990, 1990, 2000, 2005, 2013]
end_years = [2015, 2015, 2000, 2015, 2015, 2015]
periods = pd.DataFrame({'start_year': start_years, 'end_year': end_years})
for index, row in periods.iterrows():
    start_year = row['start_year']
    end_year = row['end_year']
    print start_year, end_year
    period_1054_arc = create_arc(start_year, end_year, arc_1054, 169)
    all_periods_1054_list.append(period_1054_arc)
    period_1549_arc = create_arc(start_year, end_year, arc_1549, 24)
    all_periods_1549_list.append(period_1549_arc)
    period_1019_arc = create_arc(start_year, end_year, arc_1019, 162)
    all_periods_1019_list.append(period_1019_arc)
all_periods_1054_df = pd.concat(all_periods_1054_list)
all_periods_1549_df = pd.concat(all_periods_1549_list)
all_periods_1019_df = pd.concat(all_periods_1019_list)
all_periods_1054_df = add_cols(all_periods_1054_df)
all_periods_1054_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_periods_1054_df.to_csv('%s/period_1054_arc_%s.csv' % (out_dir, cause_id),
                           index=False)
all_periods_1549_df = add_cols(all_periods_1549_df)
all_periods_1549_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_periods_1549_df.to_csv('%s/period_1549_arc_%s.csv' % (out_dir, cause_id),
                           index=False)
all_periods_1019_df = add_cols(all_periods_1019_df)
all_periods_1019_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_periods_1019_df.to_csv('%s/period_1019_arc_%s.csv' % (out_dir, cause_id),
                           index=False)

# create peak-2015 ARC datasets
only_2015 = arc_1054[arc_1054.year_id == 2015].reset_index()
arc_1054['mean_mmr'] = arc_1054.filter(like='mmr_').mean(axis=1)
# groupby location_id and keep the row with the year that is max MMR
subset_list = []
for geo in arc_1054.location_id.unique():
    subset = arc_1054[arc_1054.location_id == geo]
    subset = subset[subset.mean_mmr == subset.mean_mmr.max()]
    subset.drop('mean_mmr', axis=1, inplace=True)
    subset_list.append(subset)
arc_1054 = pd.concat(subset_list)

peak_list = []
for start_year in arc_1054.year_id.unique():
    df = arc_1054[arc_1054.year_id == start_year]
    locs = df.location_id.unique()
    add_2015 = only_2015[only_2015.location_id.isin(locs)]
    df = df.append(add_2015)
    end_year = 2015
    df = create_arc(start_year, end_year, df, 169)
    peak_list.append(df)
all_peak_df = pd.concat(peak_list)
all_peak_df = add_cols(all_peak_df)
all_peak_df.replace([np.inf, -np.inf, np.NaN], 0, inplace=True)
all_peak_df.to_csv('%s/peak_1054_arc_%s.csv' % (out_dir, cause_id),
                   index=False, encoding='utf-8')

