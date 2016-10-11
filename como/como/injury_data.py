class InjData(object):

    def __init__(self, location_id, year_id, sex_id, env='dev'):
        self.env = env
        self.lid = location_id
        self.yid = year_id
        self.sid = sex_id

    def get_meid_draws(self, meid):
        pass

    def get_all_draws(self, meid_list, nprocs=4):
        pass

    def get_dws(self):
        pass

    def check_draws(self):
        pass

    def apply_restrictions(self):
        pass

    def write_restricted(self):
        pass
