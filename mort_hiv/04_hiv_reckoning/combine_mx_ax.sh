#!/bin/sh
# Purpose: Combine a large number of text files (either .txt or .csv formats) together
# This assumes that all files are formatted in the exact same way (e.g. output from a loop or parallelized jobs)
# Output: one file with all of the text files appended together

cd "strPath"
 
mkdir result
for j in {0..9}; do
	one_file=("mx_ax_${j}"*."csv")
	sed -n -e '1p' "$one_file" > result/combined_"mx_ax_${j}"."csv"
	 
	for i in "mx_ax_${j}"*."csv"; do
	  sed -e '1d' "${i}" >> result/combined_"mx_ax_${j}"."csv"
	done
done


cd "strPath"
 
mkdir result
for j in {0..9}; do 
	one_file=("mx_ax_${j}"*."csv")
	sed -n -e '1p' "$one_file" > result/combined_"mx_ax_${j}"."csv"
	 
	for i in "mx_ax_${j}"*."csv"; do
	  sed -e '1d' "${i}" >> result/combined_"mx_ax_${j}"."csv"
	done
done
