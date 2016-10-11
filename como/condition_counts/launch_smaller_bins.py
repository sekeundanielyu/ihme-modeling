from hierarchies import dbtrees
from jobmon import sge
import sys

cvid = sys.argv[1]
lt = dbtrees.loctree(None, 35)
runfile = 'smaller_bins.py'
for l in lt.leaves():
    sge.qsub(
            runfile,
            'sb_%s' % l,
            parameters=[cvid, l],
            jobtype='python',
            project='proj_como',
            conda_env='como')
