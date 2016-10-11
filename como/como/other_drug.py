import numpy as np


def draw_from_beta(mean, se, size=1000):
    sample_size = mean*(1-mean)/se**2
    alpha = mean*sample_size
    beta = (1-mean)*sample_size
    draws = np.random.beta(alpha, beta, size=size)
    return draws


def calc(lid, yid, sid, yld_df):

    """
    Use proportion of other drug users, exclusive of those who also use
    cocaine or amphetamines."""
    other_drug_prop = .0024216
    other_drug_se = .00023581
    other_drug_draws = draw_from_beta(other_drug_prop, other_drug_se)

    # See results of this script:
    amph_coc_prop = .00375522
    amph_coc_se = .00029279
    amph_coc_draws = draw_from_beta(amph_coc_prop, amph_coc_se)

    ratio_draws = other_drug_draws / amph_coc_draws

    other_drug_ylds = yld_df[yld_df.cause_id.isin([563, 564])]
    other_drug_ylds = other_drug_ylds.groupby('age_group_id').sum()
    other_drug_ylds = other_drug_ylds.reset_index()
    dcs = other_drug_ylds.filter(like='draw').columns
    other_drug_ylds.ix[:, dcs] = other_drug_ylds.ix[:, dcs].values*ratio_draws

    other_drug_ylds['cause_id'] = 566
    other_drug_ylds['location_id'] = lid
    other_drug_ylds['year_id'] = yid
    other_drug_ylds['sex_id'] = sid
    return other_drug_ylds
