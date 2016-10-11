import os
with open("%s/__version__.txt" % os.path.dirname(__file__)) as f:
    git_info = f.readline()
