#!/bin/sh
#$ -S /bin/sh
echo $@
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
/usr/local/bin/stata-mp -q do \"$1\" $2

# Clean up after yourself :)
rm -r $STATATMP
