from copy import copy
import sys
import drill
from drill import Cascade, Cascade_loc
import pandas as pd
import multiprocessing as mp
import os


# Set default file mask to readable-for all users
os.umask(0o0002)

def run_loc(args):
    try:
        loc_id, parent_loc, sex_id, year = args
        cl = Cascade_loc(loc_id, sex_id, year, c, parent_loc=parent_loc)
        cl.run_dismod()
        cl.summarize_posterior()
        cl.draw()
        return loc_id, cl
    except Exception, e:
        print loc_id, e
        return loc_id, None


if __name__ == "__main__":

    mvid = int(sys.argv[1])
    super_id = int(sys.argv[2])
    sex = sys.argv[3]
    y = int(sys.argv[4])

    if sex=='male':
        sex_id = 0.5
    elif sex=='female':
        sex_id = -0.5

    cl_worlds = {}
    c = Cascade(mvid, reimport=False)
    lt = c.loctree
    cl_world = Cascade_loc(1, 0, y, c, reimport=False)
    cl_worlds[y] = cl_world

    num_cpus = mp.cpu_count()
    pool = mp.Pool(min(num_cpus,8))

    cl_world = cl_worlds[y]
    cl_super = Cascade_loc(super_id, sex_id, y, c, parent_loc=cl_world, reimport=False)
    cl_super.run_dismod()
    cl_super.summarize_posterior()
    cl_super.draw()

    # Run sub-locations
    lvl = 1
    completed_locs = { lvl: {super_id: cl_super} }
    desc_at_lvl = True
    while desc_at_lvl:

        desc = lt.get_node_by_id(super_id).level_n_descendants(lvl)

        if len(desc)==0:
            desc_at_lvl = False
            break
        else:
            arglist = []
            for child_loc in desc:
                parent_obj = copy(completed_locs[lvl][child_loc.parent.id])
                arglist.append((
                    child_loc.info['location_id'], parent_obj, sex_id, y))

            res =  pool.map(run_loc, arglist)

            del completed_locs[lvl]

            lvl = lvl+1
            completed_locs[lvl] = {}
            for i in res:
                completed_locs[lvl][i[0]] = i[1]


    pool.close()
    pool.join()

    def depth_first(parent_cl, child_id):
        desc = lt.get_node_by_id(loc(parent_cl.loc)).children
        if len(children)==0:
            return 0
        else:
            pool = mp.Pool(min(len(children),8))
            arglist = []
            for child_loc in desc:
                arglist.append((
                    child_loc.info['location_id'], parent_cl, sex_id, y))
            res =  pool.map(run_loc, arglist)
            pool.close()
            pool.join()
