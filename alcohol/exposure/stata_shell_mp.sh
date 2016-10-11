#!/bin/sh
#$ -S /bin/sh
echo $@
echo $1 
echo $2
echo $3 
echo $4
echo $5
# STATATMP is used by Stata to determine tempfolder
export STATATMP="/tmp/stata_"$JOB_ID

# Clear temp directory if it exists
if [ -d $STATATMP ]
then
	rm -r $STATATMP
fi

# Now make temp directory
mkdir $STATATMP

# Launch Stata
/usr/local/bin/stata-mp -q do \"$1\" $2 $3 $4 $5 $6 $7 $8

# Clean up after yourself :)
rm -r $STATATMP

