#!/bin/sh
#$ -S /bin/sh

kick_off=/home/j/WORK/03_cod/02_models/01_code/04_codem_v2/prod/kick_off.py


if [ ! -z $3 ]
then
    /usr/local/epd-current/bin/python $kick_off $1 $2 $3
else
    /usr/local/epd-current/bin/python $kick_off $1 $2
fi


