# pytest will run this just by typing "py.test" from this folder
from dalynator import draws as daly_draws
from gopher import cod_draws, draws
from epi import draws as epi_draws
from como import draws as como_draws


def test_best_daly_draws():
    df = daly_draws(location_id=[130], cause_id=[294],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[22], metric_id=[2], measure_id=[1])
    assert len(df.rei_id.unique()) == len(df), ('more than 1 row per '
                                                'cause/risk returned')
    return df


def test_multiple_locs_daly_draws():
    ''' changed draw directory strcture, so test that the right locs
    are being pulled (went from all files in one dir, to separate folders
    by locations'''
    df = daly_draws(location_id=[130, 131], cause_id=[294],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[22], metric_id=[1], measure_id=[1])
    assert len(df) == 2, ('more than expected locs returned')
    return df


def test_latest_daly_draws():
    df = daly_draws(location_id=[130], cause_id=[294],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[22], metric_id=[2], measure_id=[1],
                    status='latest')
    assert len(df.rei_id.unique()) == len(df), ('more than 1 row per '
                                                'cause/risk returned')
    return df


def test_daly_draws_parallel():
    df = daly_draws(location_id=[130], cause_id=[297],
                    sex_id=[1], year_id=[1990, 1995], verbose=True,
                    age_group_id=[22], metric_id=[2], measure_id=[1],
                    num_workers=2)
    return df


def test_epi_draws():
    me_id = 1182
    df = epi_draws(me_id, sids=[1], lids=[131], yids=[1990], ag_ids=[3],
                   verbose=True)
    assert len(df) == 1, ('too many rows returned')
    return df


def test_cod_draws():
    cause_id = 302
    df = cod_draws(cause_id, sids=[1], lids=[131], yids=[1990], ag_ids=[3],
                   verbose=True)
    assert len(df) == 1, ('too many rows returned')
    return df


def test_exposure_draws():
    df = draws({'rei_ids': [84]}, source='risk', year_ids=[1990],
               location_ids=[102], age_group_ids=[6], sex_ids=[2],
               draw_type='exposure')
    # there should be one row per categorical risk
    assert len(df) == len(df.modelable_entity_id.
                          unique()), ('more than one row per ME returned')
    return df


def test_rr_draws():
    df = draws({'rei_ids': [128]}, source='risk', year_ids=[1990],
               location_ids=[102], age_group_ids=[15], sex_ids=[2],
               draw_type='rr')
    # there should be one row per categorical risk
    assert len(df) == len(df.parameter.unique()), ('more than one row per '
                                                   'category returned')
    return df


def test_risk_id():
    ''' draws can accept risk_id or rei_id '''
    df = draws({'risk_ids': [84]}, source='risk',
               location_ids=[1], draw_type='rr')
    return df


def test_string_format():
    ''' some identifier variables were returning as strings'''
    df1 = draws({'rei_ids': [114]}, source='risk', location_ids=101,
                year_ids=1990, sex_ids=1, draw_type='rr', verbose=True)

    df2 = draws({'modelable_entity_ids': [1449]}, source='epi',
                location_ids=[132], verbose=True)

    for df in [df1, df2]:
        for col in df.columns:
            if col.endswith('id'):
                assert df[col].dtype != 'O'

    return df1, df2


def test_big_hdf():
    ''' some epi draws are stored as one big hdf '''
    df = draws({'rei_ids': [94]}, source='risk', location_ids=101,
               year_ids=1990, sex_ids=1, draw_type='exposure')

    return df


def test_risk_dups():
    ''' some risk exposure draws had duplicate cat4 rows '''
    df = draws({'rei_ids': [94]}, source='risk', location_ids=101,
               year_ids=1990, sex_ids=1, age_group_ids=4, draw_type='exposure')

    assert ~df.duplicated(subset=[
        col for col in df.columns if 'draw' not in col]).any(), (
            'duplicates found')

    return df


def test_missing_files():
    ''' some risk exposure h5 files were missing because save results
    called h5 conversion from csv and that occasionally fails. If get_draws
    gets a file not found error, it should try to fall back on reading
    the original csv'''
    df = draws({'modelable_entity_ids': [8946]}, location_ids=[44553],
               sex_ids=[2], year_ids=[2010], status=56300, verbose=True,
               source='epi')

    return df


def test_como_cause_draws():
    df = como_draws(location_id=[130], cause_id=[297],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[12], status='latest')
    assert len(df) == 4  # chronic prev, inc, prev, yld
    return df


def test_como_rei_draws():
    df = como_draws(location_id=[1], cause_id=[590], rei_id=[205],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[12], status='latest')
    assert not df.empty
    assert len(df.groupby(['rei_id',
                           'measure_id'])) == len(df.measure_id.unique())
    return df


def test_como_sequela_draws():
    df = como_draws(location_id=[1], sequela_id=[1],
                    sex_id=[1], year_id=[1990], verbose=True,
                    age_group_id=[12], status='latest')
    assert not df.empty
    assert len(df.groupby(['sequela_id',
                           'measure_id'])) == len(df.measure_id.unique())
    return df


def test_como_gopher_interface():
    '''instead of calling como.draws, call gopher.draws for como results'''
    df = draws({'sequela_ids': [1]}, source='como', location_id=[1],
               sex_id=[1], year_id=[1990], verbose=True,
               age_group_id=[12], metric_id=[1], status='latest')
    assert not df.empty
    assert len(df.groupby(['sequela_id',
                           'measure_id'])) == len(df.measure_id.unique())
    return df


def test_como_version():
    ''' version should override status'''
    df = draws({'sequela_ids': [1]}, source='como', location_id=[1],
               sex_id=[1], year_id=[1990], verbose=True,
               age_group_id=[12], metric_id=[1], status='best', version=86)
    return df

if __name__ == '__main__':
    df = test_multiple_locs_daly_draws()
