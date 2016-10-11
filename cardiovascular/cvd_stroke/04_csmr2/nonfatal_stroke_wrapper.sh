#!/usr/bin/env bash
cd strPath/nonfatal_stroke_custom
#$ -N stroke_intermediary
#$ -cwd
#$ -P proj_custom_models
#$ -l mem_free=8G
#$ -pe multi_slot 4
#$ -o /share/temp/sgeoutput/stroke/output
#$ -e /share/temp/sgeoutput/stroke/errors

strPath/anaconda/bin/python 00_master.py "$@"
