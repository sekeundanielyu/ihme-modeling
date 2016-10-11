
#!/bin/sh
#$ -S /bin/sh
#$ -M $1@uw.edu
#$ -m beas
umask 002
export LD_LIBRARY_PATH=/usr/lib64
export STATA_DO="do \"$2\""
/usr/local/stata13/stata-mp -q $STATA_DO $3
