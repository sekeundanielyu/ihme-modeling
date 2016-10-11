from hierarchies import dbtrees
from jobmon import sge


def launch_squeeze(autism_value=0.29, idiopathic=95.0, autism_resid=0.05):
    locations = dbtrees.loctree(None, 35)

    runfile = "strCodeDir/squeeze_em_all.py"
    for location_id in [l.id for l in locations.leaves()]:
        for year_id in [1990, 1995, 2000, 2005, 2010, 2015]:
            for sex_id in [1, 2]:
                params = [
                        '--location_id', location_id,
                        '--year_id', year_id,
                        '--sex_id', sex_id]
                sge.qsub(
                        runfile,
                        'sqz_%s_%s_%s' % (location_id, year_id, sex_id),
                        parameters=params,
                        slots=30,
                        memory=60,
                        project='proj_como',
                        conda_env="isqueeze")


def launch_failed():
    with open("strCodeDir/miss_squeeze.csv") as f:
        relaunch = f.readlines()
    relaunch = [r.split(".")[0].split("_") for r in relaunch]
    for r in relaunch:
        runfile = "strCodeDir/squeeze_em_all.py"
        params = [
                '--location_id', r[0],
                '--year_id', r[1],
                '--sex_id', r[2]]
        sge.qsub(
                runfile,
                'sqz_%s_%s_%s' % (r[0], r[1], r[2]),
                parameters=params,
                slots=30,
                memory=60,
                project='proj_como',
                conda_env="isqueeze")


if __name__ == '__main__':
    launch_squeeze()
