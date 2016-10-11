#!/bin/sh
#$ -S /bin/sh
/usr/local/bin/stata-mp -q /home/j/WORK/04_epi/02_models/01_code/06_custom/intest/code/split.do "$1" "$2" "$3"
