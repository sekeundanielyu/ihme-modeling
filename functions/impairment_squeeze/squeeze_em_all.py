import argparse
import pandas as pd
from multiprocessing import Pool
from transmogrifier import gopher
import os
from functools import partial
import ideal_scale_funcs as ifs


###################################
# Prepare envelopes
###################################
def create_env(location_id, year, sex):
    env_ids = {
            'epi': 2403, 'blind': 9805, 'id_bord': 9423, 'id_mild': 9424,
            'id_mod': 9425, 'id_sev': 9426, 'id_prof': 9427}
    envelope_dict = {}
    for envlab, id in env_ids.iteritems():
        env = gopher.draws(
                {'modelable_entity_ids': [id]},
                'dismod',
                location_ids=location_id,
                year_ids=year,
                sex_ids=sex,
                measure_ids=5)
        envelope_dict[envlab] = env.copy()
    return envelope_dict


###################################
# Get unsqueezed data
###################################
def get_unsqueezed(sequelae_map, drawcols, location_id, year, sex):
    # Get all causes with epilepsy, ID, and blindness
    unsqueezed = []
    for idx, seqrow in sequelae_map.iterrows():
        me_id = int(seqrow[['me_id']])
        a = seqrow['acause']
        g = seqrow['grouping']
        h = seqrow['healthstate']

        try:
            gbd_ids = {'modelable_entity_ids': [me_id]}
            df = gopher.draws(
                    gbd_ids,
                    'dismod',
                    location_ids=location_id,
                    year_ids=year,
                    sex_ids=sex,
                    measure_ids=5)
            df['me_id'] = me_id
            unsqueezed.append(df)
        except:
            print('Failed retrieving %s %s %s' %
                  (a, g, h))
            df = unsqueezed[0].copy()
            df['me_id'] = me_id
            df.ix[:, drawcols] = 0
            unsqueezed.append(df)

    unsqueezed = pd.concat(unsqueezed)
    unsqueezed = unsqueezed[[
        'me_id', 'location_id', 'year_id', 'age_group_id', 'sex_id']+drawcols]
    unsqueezed = unsqueezed.merge(sequelae_map, on='me_id')
    unsqueezed = unsqueezed[unsqueezed.age_group_id < 22]
    unsqueezed = unsqueezed[unsqueezed.age_group_id > 1]

    return unsqueezed


##################################
# Write to files
##################################
def write_squeezed(sqzd, location_id, year, sex):

    tmap = pd.read_excel(
            "strCodeDir/map_pre_pos_mes.xlsx")
    for me_id, df in sqzd.groupby(['me_id']):

        t_meid = tmap.query('modelable_entity_id_source == %s' % me_id)
        t_meid = t_meid.modelable_entity_id_target.squeeze()
        try:
            t_meid = int(t_meid)
        except:
            pass
        if not isinstance(t_meid, int):
            continue
        print 'Writing squeezed %s to file' % t_meid
        drawsdir = "strOutdir/%s" % t_meid
        fn = "%s/%s_%s_%s.h5" % (drawsdir, location_id, year, sex)
        try:
            os.makedirs(drawsdir)
        except:
            pass
        df['location_id'] = int(float(location_id))
        df['year_id'] = int(float(year))
        df['sex_id'] = int(float(sex))
        df['measure_id'] = 5
        df['age_group_id'] = df.age_group_id.astype(float).astype(int)
        datacols = [
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id']
        df[datacols+drawcols].to_hdf(
                fn,
                'draws',
                mode='w',
                format='table',
                data_columns=datacols)


##################################
# Allocate residuals
##################################
def allocate_residuals(usqzd, sqzd):
    tmap = pd.read_excel(
            "strCodeDir/map_pre_pos_mes.xlsx")

    resids = usqzd.merge(
            sqzd,
            on=['location_id', 'year_id', 'age_group_id', 'sex_id', 'me_id'],
            suffixes=('.usqzd', '.sqzd'))
    resids = resids[resids['resid_target_me.usqzd'].notnull()]

    dcols = ['draw_%s' % d for d in range(1000)]
    dscols = ['draw_%s.sqzd' % d for d in range(1000)]
    ducols = ['draw_%s.usqzd' % d for d in range(1000)]
    toalloc = resids[ducols].values - resids[dscols].values
    toalloc = toalloc.clip(min=0)
    resids = resids.join(pd.DataFrame(
        data=toalloc, index=resids.index, columns=dcols))
    resids = resids[[
        'location_id', 'year_id', 'age_group_id', 'sex_id',
        'resid_target_me.usqzd']+dcols]
    resids.rename(
            columns={'resid_target_me.usqzd': 'resid_target_me'},
            inplace=True)
    resids = resids.groupby(['resid_target_me', 'age_group_id']).sum()
    resids = resids.reset_index()
    resids = resids[['resid_target_me', 'age_group_id']+dcols]

    for me_id, resid_df in resids.groupby('resid_target_me'):
        t_meid = tmap.query('modelable_entity_id_source == %s' % me_id)
        t_meid = t_meid.modelable_entity_id_target.squeeze()
        try:
            t_meid = int(t_meid)
        except:
            pass

        gbd_ids = {'modelable_entity_ids': [me_id]}
        t_df = gopher.draws(
                gbd_ids,
                'dismod',
                location_ids=location_id,
                year_ids=year,
                sex_ids=sex,
                measure_ids=5)
        t_df = t_df.merge(
                resid_df, on='age_group_id', suffixes=('#base', '#resid'))
        newvals = (
            t_df.filter(like="#base").values +
            t_df.filter(like="#resid").values)
        t_df = t_df.join(pd.DataFrame(
            data=newvals, index=t_df.index, columns=dcols))

        print 'Writing residual %s to file' % t_meid
        drawsdir = "strOutDir/%s" % t_meid
        fn = "%s/%s_%s_%s.h5" % (drawsdir, location_id, year, sex)
        try:
            os.makedirs(drawsdir)
        except:
            pass
        t_df['location_id'] = int(float(location_id))
        t_df['year_id'] = int(float(year))
        t_df['sex_id'] = int(float(sex))
        t_df['measure_id'] = 5
        t_df['age_group_id'] = t_df.age_group_id.astype(float).astype(int)
        datacols = [
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id']
        t_df[datacols+dcols].to_hdf(
                fn,
                'draws',
                mode='w',
                format='table',
                data_columns=datacols)

    return resids


###########################################
# Determine the remainder of the envelopes
###########################################
def calc_env_remainders(envelope_dict, sqzd):
    remains = {}
    for key in envelope_dict:
        allocd = sqzd[sqzd['i_%s' % key] == 1]
        allocd = allocd.groupby('age_group_id').sum().reset_index()
        remain = envelope_dict[key].merge(
                allocd,
                on='age_group_id',
                suffixes=('.env', '.alloc'))
        dcols = ['draw_%s' % d for d in range(1000)]
        decols = ['draw_%s.env' % d for d in range(1000)]
        dacols = ['draw_%s.alloc' % d for d in range(1000)]
        toalloc = remain[decols].values - remain[dacols].values
        toalloc = toalloc.clip(min=0)
        remain = remain.join(pd.DataFrame(
            data=toalloc, index=remain.index, columns=dcols))
        remain = remain[['age_group_id']+dcols]
        remains[key] = remain.copy()
    return remains


if __name__ == '__main__':
    ###################################
    # Parse input arguments
    ###################################
    parser = argparse.ArgumentParser()
    parser.add_argument(
            "--location_id",
            help="location_id",
            default=7,
            type=int)
    parser.add_argument(
            "--year_id",
            help="year",
            default=2010,
            type=int)
    parser.add_argument(
            "--sex_id",
            help="sex",
            default=1,
            type=int)
    parser.add_argument(
            "--idiopathic",
            help="idiopathic",
            default=95.0,
            type=float)
    args = parser.parse_args()
    location_id = args.location_id
    year = args.year_id
    sex = args.sex_id
    idiopathic = args.idiopathic

    ###################################
    # Prepare envelopes
    ###################################
    drawcols = ['draw_' + str(i) for i in range(1000)]
    sequelae_map = pd.read_excel(
            "strCodeDir/source_target_maps.xlsx")
    envelope_dict = create_env(location_id, year, sex)

    ###################################
    # Prepare unsqueezed prevalence
    ###################################
    # Load map of sequelae and their targets
    unsqueezed = get_unsqueezed(
            sequelae_map, drawcols, location_id, year, sex)
    unsqueezed.ix[:, drawcols] = unsqueezed.ix[:, drawcols].clip(lower=0)

    ###################################
    # SQUEEZE
    ###################################
    # Parallelize the squeezing
    pool = Pool(20)
    ages = list(pd.unique(unsqueezed['age_group_id']))
    partial_squeeze = partial(
            ifs.squeeze_age_group,
            unsqueezed=unsqueezed,
            env_dict=envelope_dict)
    squeezed = pool.map(partial_squeeze, ages, chunksize=1)
    pool.close()
    pool.join()
    errors = [e for e in squeezed if isinstance(e, tuple)]
    squeezed = pd.concat(squeezed)
    squeezed = squeezed.groupby([
        'location_id', 'year_id', 'age_group_id', 'sex_id', 'me_id']).sum()
    squeezed = squeezed.reset_index()

    ##################################
    # Write to files
    ##################################
    write_squeezed(squeezed, location_id, year, sex)

    ##################################
    # Allocate residuals
    ##################################
    resids = allocate_residuals(unsqueezed, squeezed)

    ###########################################
    # Determine the remainder of the envelopes
    ###########################################
    remains = calc_env_remainders(envelope_dict, squeezed)

    remain_map = {
            'id_bord': 2000,
            'id_mild': 1999,
            'id_mod': 2001,
            'id_sev': 2002,
            'id_prof': 2003}
    for key, meid in remain_map.iteritems():
        print 'Writing remainder %s to file' % meid
        drawsdir = "strOutDir/%s" % meid
        fn = "%s/%s_%s_%s.h5" % (drawsdir, location_id, year, sex)
        try:
            meid = int(meid)
        except:
            pass
        try:
            os.makedirs(drawsdir)
        except:
            pass
        df = remains[key]
        df['location_id'] = int(float(location_id))
        df['year_id'] = int(float(year))
        df['sex_id'] = int(float(sex))
        df['measure_id'] = 5
        df['age_group_id'] = df.age_group_id.astype(float).astype(int)
        datacols = [
                'location_id', 'year_id', 'age_group_id', 'sex_id',
                'measure_id']
        df[datacols+drawcols].to_hdf(
                fn,
                'draws',
                mode='w',
                format='table',
                data_columns=datacols)
