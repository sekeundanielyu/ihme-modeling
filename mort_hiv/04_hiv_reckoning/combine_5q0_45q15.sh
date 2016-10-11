#!/bin/sh
# Purpose: Combine a large number of text files (either .txt or .csv formats) together
# This assumes that all files are formatted in the exact same way (e.g. output from a loop or parallelized jobs)
# Output: one file with all of the text files appended together

 
# Combine 45q15 results for HIV-deleted
cd "strPath"
one_file=("mean_45q15_"*."csv")
sed -n -e '1p' "$one_file" > "strPath/mean_45q15_hivdel.csv"
 
for i in "mean_45q15_"*."csv"; do
  sed -e '1d' "${i}" >> "/strPath/mean_45q15_hivdel.csv"
done


# Combine 5q0 results for HIV-deleted 
one_file=("mean_5q0_"*."csv")
sed -n -e '1p' "$one_file" > "/strPath/mean_5q0_hivdel.csv"
 
for i in "mean_5q0_"*."csv"; do
  sed -e '1d' "${i}" >> "/strPath/mean_5q0_hivdel.csv"
done


# Combine 45q15 results for with-HIV
cd "/strPath"
one_file=("mean_45q15_"*."csv")
sed -n -e '1p' "$one_file" > "/strPath/mean_45q15_whiv.csv"
 
for i in "mean_45q15_"*."csv"; do
  sed -e '1d' "${i}" >> "/strPath/mean_45q15_whiv.csv"
done


# Combine 5q0 results for with-HIV
cd "/strPath"
 
one_file=("mean_5q0_"*."csv")
sed -n -e '1p' "$one_file" > "/strPath/mean_5q0_whiv.csv"
 
for i in "mean_5q0_"*."csv"; do
  sed -e '1d' "${i}" >> "/strPath/mean_5q0_whiv.csv"
done
