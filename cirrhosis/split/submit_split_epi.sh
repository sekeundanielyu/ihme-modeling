#!/bin/sh
#$ -S /bin/sh
/usr/local/bin/stata-mp -q /home/j/WORK/04_epi/02_models/01_code/06_custom/cirrhosis/code/split_epi.do "$1" 
