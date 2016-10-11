import pandas as pd
import sys
sys.path.append("strPath/transmogrifier")
from transmogrifier import gopher, maths


def interp_loc(modelable_entity_id, measure_id, location_id, outpath):
    start_year = 1980
    epi_start_year = 1990
    end_year = 2015
    rank_year = 2005

    # Retrieve epi draws and interpolate
    epi_draws = []
    for y in range(epi_start_year, end_year+1, 5):
        d = gopher.draws({'modelable_entity_ids': [modelable_entity_id]},
                         year_ids=[y], location_ids=[location_id],
                         measure_ids=[measure_id], verbose=False,
                         source="dismod", age_group_ids=[
                             2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
                             13, 14, 15, 16, 17, 18, 19, 20, 21]
                         )
        assert len(d) > 0, (
            "Uh oh, couldn't find epi draws. Make sure you have "
            "proportion estimates for the supplied meids")
        epi_draws.append(d)
    epi_draws = pd.concat(epi_draws)
    ip_epi_draws = []
    for y in range(epi_start_year, end_year, 5):
        sy = y
        ey = y+5
        ip_draws = maths.interpolate(
                epi_draws.query('year_id==%s' % sy),
                epi_draws.query('year_id==%s' % ey),
                ['age_group_id', 'model_version_id', 'sex_id'],
                'year_id',
                ['draw_%s' % i for i in range(1000)],
                sy,
                ey,
                rank_df=epi_draws.query('year_id==%s' % rank_year))
        if ey != end_year:
            ip_draws = ip_draws[ip_draws.year_id != ey]
        ip_epi_draws.append(ip_draws)
    ip_epi_draws = pd.concat(ip_epi_draws)
    extrap_draws = []
    for y in range(start_year, epi_start_year):
        esy_draws = ip_epi_draws.query('year_id==%s' % epi_start_year)
        esy_draws['year_id'] = y
        extrap_draws.append(esy_draws)
    epi_draws = pd.concat([ip_epi_draws]+extrap_draws)
    epi_draws.to_csv(outpath)


if __name__ == "__main__":

    import os
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument('--location_id', type=int)
    parser.add_argument('--measure_id', type=int)
    parser.add_argument('--modelable_entity_id', type=int)
    parser.add_argument('--outpath')

    args = vars(parser.parse_args())

    interp_loc(args["modelable_entity_id"], args["measure_id"],
               args["location_id"], args["outpath"])
