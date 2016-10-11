#!/bin/sh
#$ -S /bin/sh
/usr/local/bin/stata-mp -q /home/j/WORK/04_epi/02_models/01_code/06_custom/chagas/code/01a_split.do "$1" "$2"
