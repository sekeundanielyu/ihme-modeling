import sys
import os
try:
    import db_process_upload
except:
    sys.path.append(str(os.getcwd()).rstrip('/mmr'))
    import db_process_upload

upload_type, process_v, env, in_dir = sys.argv[1:5]
process_v = int(process_v)

db_process_upload.upload(env, upload_type, process_v, in_dir)
