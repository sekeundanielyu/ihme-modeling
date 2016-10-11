#!/bin/sh
#$ -S /bin/sh
#$ -m beas
export STATA_DO="do \"$1\""
/usr/local/stata13/stata-mp -q $STATA_DO $2
