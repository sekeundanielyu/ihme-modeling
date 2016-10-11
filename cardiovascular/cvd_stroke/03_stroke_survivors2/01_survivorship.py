import stroke_fns
import sys
import pandas as pd

# bring in args
dismod_dir, out_dir, year, model_vers1, model_vers2 = sys.argv[1:6]
year = int(year)
model_vers1 = int(model_vers1)
model_vers2 = int(model_vers2)

# get ready for loop
sexes = [1, 2]
models = [model_vers1, model_vers2]
columns = stroke_fns.filter_cols()
locations = stroke_fns.get_locations()
loops = (len(locations) * 2) * 2

all_df = pd.DataFrame()
count = 0
for mv in models:
    for geo in locations:
        for sex in sexes:
            print 'On loop %s of %s' % (count, loops)
            draws = pd.read_hdf('%s/%s/full/draws/%s_%s_%s.h5' %
                                (dismod_dir, mv, geo, year, sex),
                                'draws')

            # drop age-standardized because we don't want that as input data
            draws = draws[draws.age_group_id != 27]

            # pull out incidence and EMR into seperate dfs
            incidence = draws[draws.measure_id == 6]
            emr = draws[draws.measure_id == 9]

            # keep only age_group_id and draw columns
            incidence = incidence[columns]
            emr = emr[columns]

            # get 28 day survivorship
            emr.set_index('age_group_id', inplace=True)
            fatality = emr / (12 + emr)
            survivorship = 1 - fatality

            # multiply incidence by 28 day survivorship
            incidence.set_index('age_group_id', inplace=True)
            final_incidence = incidence * survivorship

            # add back on identifying columns
            final_incidence['location_id'] = geo
            final_incidence['sex_id'] = sex
            final_incidence['model_version_id'] = mv

            # append to master dataset
            all_df = all_df.append(final_incidence)
            count += 1

all_df.reset_index(inplace=True)
all_df['year_id'] = year

# add together ischemic and hemorrhagic
index_cols = ['location_id', 'age_group_id', 'year_id', 'sex_id']
summed_all_df = all_df.groupby(index_cols).sum().reset_index()

# get mean, upper, lower
summed_all_df.drop('model_version_id', axis=1, inplace=True)
summed_all_df.set_index(index_cols, inplace=True)
final = summed_all_df.transpose().describe(
    percentiles=[.025, .975]).transpose()[['mean', '2.5%', '97.5%']]
final.rename(
    columns={'2.5%': 'lower', '97.5%': 'upper'}, inplace=True)
final.index.rename(['location_id', 'age_group_id', 'year_id', 'sex_id'],
                   inplace=True)
final.reset_index(inplace=True)

# output
final.to_csv('%s/input_%s_%s_%s.csv' %
             (out_dir, model_vers1, model_vers2, year),
             index=False, encoding='utf-8')
