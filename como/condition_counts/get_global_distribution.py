import pandas as pd
from multiprocessing import Pool
from hierarchies import dbtrees
from adding_machine.agg_locations import get_pop

# Set the como version
keepcols = ['location_id', 'year_id', 'age_group_id', 'sex_id', 'bin_id',
            'bin_lower', 'draw_mean']
global pop
pop = get_pop()


def process_country_file(cvid, l, y, s):
    print cvid, l, y, s
    dists_directory = "/ihme/centralcomp/como/%s/simulants" % cvid
    indf = pd.read_hdf("%s/dw_small_bins_%s_%s_%s.h5" %
                       (dists_directory, l, y, s))
    df = []
    for aid, adf in indf.groupby('age_group_id'):
        adf.ix[adf.bin_id == 1, 'draw_mean'] = (
                adf.ix[adf.bin_id == 1, 'draw_mean'].values -
                adf.ix[adf.bin_id == 0, 'draw_mean'].values)
        df.append(adf)
    df = pd.concat(df)
    df['location_id'] = l
    df['year_id'] = y
    df['sex_id'] = s
    df = df[keepcols]
    df = df.merge(pop, how='left')
    df['scaled_draw_mean'] = df.groupby('age_group_id')['draw_mean'].apply(
            lambda x:
            x/40000.) * df.pop_scaled
    return df


def wrap_pcf(args):
    return process_country_file(*args)


# Extract discrete bins
def get_bins(cvid, lid, clids):

    args = [
            (cvid, l, y, s)
            for l in clids
            for y in range(1990, 2016, 5)
            for s in [1, 2]]

    pool = Pool(15)
    compiled_dist = pool.map(wrap_pcf, args)
    pool.close()
    pool.join()

    compiled_dist = pd.concat(compiled_dist)
    compiled_dist = compiled_dist.groupby([
        'year_id', 'age_group_id', 'sex_id', 'bin_id', 'bin_lower'])[
        'scaled_draw_mean'].sum().reset_index()
    compiled_dist['location_id'] = lid
    return compiled_dist


if __name__ == "__main__":

    import sys
    cvid = sys.argv[1]

    # Global
    lt = dbtrees.loctree(None, 35)
    rid = 1
    lids = [l.id for l in lt.leaves()]
    cd = get_bins(
            cvid,
            rid,
            lids)
    cd.to_csv(
            "/ihme/centralcomp/como/%s/pyramids/dws_%s.csv" % (cvid, rid),
            index=False)

    sdi_lts = dbtrees.loctree(None, 40, return_many=True)

    # SDI groupings
    for lt in sdi_lts:
        rid = lt.root.id
        lids = [l.id for l in lt.leaves()]
        cd = get_bins(
                cvid,
                rid,
                lids)
        cd.to_csv(
                "/ihme/centralcomp/como/%s/pyramids/dws_%s.csv" % (cvid, rid),
                index=False)
