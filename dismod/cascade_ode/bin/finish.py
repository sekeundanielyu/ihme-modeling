import sys
import os
import upload
import json
import settings
from jobmon import job

# Set default file mask to readable-for all users
os.umask(0o0002)

if __name__ == "__main__":

    mvid = sys.argv[1]

    # Get configuration options
    jm_path = os.path.dirname(job.__file__)
    sett = settings.load()
    j = job.Job('%s/%s' % (sett['cascade_ode_out_dir'], mvid))
    j.start()

    upload.upload_final(mvid)
    upload.update_model_status(mvid, 1)

    j.finish()
    j.send_request('stop')
