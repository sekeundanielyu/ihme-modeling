#!/bin/sh
#$ -S /bin/sh
/usr/local/bin/stata-mp -b do 3b_get_distributions_meps_parallel.do $1
