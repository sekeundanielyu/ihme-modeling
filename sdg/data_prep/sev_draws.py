import pandas as pd
import sys
import os
from getpass import getuser

sys.path.append(SDG_REPO)
import sdg_utils.draw_files as dw


def process_sev_rei_id(rei_id):
    """Read, filter, and save a sev, expressed with rei_id."""

    print 'reading'
    # read from the global sev path
    df = pd.read_stata(dw.SEV_PATH.format(rei_id=rei_id))

    print 'cleaning'
    # only need age-standardized and both sexes
    df = df.query('age_group_id==27 & sex_id==3')
    # rename to standard draw col names
    df = df.rename(columns=lambda x: x.replace('sev_', 'draw_'))
    # rename risk id to db standard rei_id
    df = df.rename(columns={'risk_id': 'rei_id'})
    # sev is the measure
    df['measure_id'] = 29
    # why is this called a rate in the gbd databases?
    df['metric_id'] = 3
    # keep the right columns
    df = df[
        dw.SEV_GROUP_COLS +
        dw.DRAW_COLS
    ]

    print 'saving'
    # write the output to standard sdg file structure
    out_dir = "{d}/sev/{v}/".format(d=dw.INPUT_DATA_DIR, v=dw.SEV_VERS)
    if not os.path.exists(out_dir):
        os.mkdir(out_dir)
    out_path = "{od}/{r}.h5".format(od=out_dir, r=rei_id)
    df.to_hdf(out_path, key="data", format="table",
              data_columns=['location_id', 'year_id'])


if __name__ == "__main__":
    for rei_id in dw.SEV_REI_IDS:
        print 'running', rei_id, '...'
        try:
            process_sev_rei_id(rei_id)
        except IOError:
            print 'No data for {} with this batch of SEVs'.format(rei_id)
