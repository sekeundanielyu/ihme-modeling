from simulator import ComoSimulator
from version import ComoVersion


def main(
        como_version_id, location_id=102, year_id=2000, sex_id=2,
        env='dev'):
    cv = ComoVersion(como_version_id)
    cs = ComoSimulator(cv, location_id, year_id, sex_id, env)
    x = cs.simulate_all_sp()
    return x


def main_parallel(cvid, location_id, year_id, sex_id, env='prod'):
    cv = ComoVersion(cvid)
    cs = ComoSimulator(cv, location_id, year_id, sex_id, env)
    cs.write_results()

if __name__ == "__main__":
    res = main_parallel()
