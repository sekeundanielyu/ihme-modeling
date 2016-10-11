import os, sys

run_dir = sys.argv[1]

storage_path = '/strPath/%s' % run_dir

rm_cmd = 'rm -r \"%s/draws\"' % storage_path

print rm_cmd
os.system(rm_cmd)

