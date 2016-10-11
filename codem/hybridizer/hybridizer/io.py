import sqlalchemy as sql
import pandas as pd
from codcorrect.error_check import check_data_format
import logging


def read_hdf_draws(draws_filepath, location_id, key="draws"):
    """ Read in model draws

    Read in CODEm/custom model draws from a given filepath and filter by location_id.
    """
    data = pd.read_hdf(draws_filepath, key=key, where=["location_id=={location_id}".format(location_id=location_id)])
    return data