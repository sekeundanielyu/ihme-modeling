import pandas as pd
from como.simulator import get_distribution


def small_bins(cd, l, y, s):
    print l, y, s
    df = pd.read_hdf("%s/sims_%s_%s_%s.h5" % (cd, l, y, s))

    binned = []
    for aid, subdf in df.groupby('age_group_id'):
        bd = get_distribution(subdf.dw_mean, 100)
        bd['age_group_id'] = aid
        binned.append(bd)

    binned = pd.concat(binned)
    binned.rename(columns={'count': 'draw_mean'}, inplace=True)
    fp = "%s/dw_small_bins_%s_%s_%s.h5" % (cd, l, y, s)
    binned.sort_values(['age_group_id', 'bin_id'], inplace=True)
    binned.to_hdf(
            fp, 'draws', mode='w', format='table',
            data_columns=['age_group_id', 'bin_id'])


if __name__ == "__main__":

    import sys
    cvid = sys.argv[1]
    l = sys.argv[2]
    cd = "/ihme/centralcomp/como/%s/simulants" % cvid
    for y in range(1990, 2016, 5):
        for s in [1, 2]:
            small_bins(cd, l, y, s)
