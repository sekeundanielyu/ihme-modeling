import pandas as pd
import os


def apply_NE_matrix(cv, seqdf, loc, year, sex):
    cf = os.path.join(cv.root_dir, 'info', 'causes.csv')
    cause_ids = pd.read_csv(cf)
    nemat = pd.read_csv(
        "/ihme/injuries/04_COMO_input/01_NE_matrix/"
        "NEmatrix_{l}_{y}_{s}.csv".format(l=loc, y=year, s=sex))
    nemat = nemat.merge(cause_ids, left_on='ecode', right_on='acause')
    nemat = nemat.merge(cv.ismap, left_on='ncode', right_on='n_code')
    nemat = nemat[['cause_id', 'age_group_id', 'sequela_id']+cv.drawcols]
    nemat = nemat.merge(seqdf, on=['sequela_id', 'age_group_id'])
    nemat = nemat.join(pd.DataFrame(
        data=(
            nemat.filter(regex='draw.*x').values *
            nemat.filter(regex='draw.*y').values),
        index=nemat.index,
        columns=cv.drawcols))
    index_cols = ['location_id', 'year_id', 'sex_id', 'cause_id',
                  'age_group_id']
    nemat = nemat.groupby(index_cols).sum().reset_index()
    nemat = nemat[index_cols+cv.drawcols]
    return nemat
