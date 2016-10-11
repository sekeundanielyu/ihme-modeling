import os
import json

# Path to this file
this_path = os.path.dirname(os.path.abspath(__file__))

# Get configuration options
if os.path.isfile(os.path.join(this_path, "config.local")):
    settings = json.load(open(os.path.join(this_path, "config.local")))
else:
    settings = json.load(open(os.path.join(this_path, "config.default")))
