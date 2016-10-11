#$ -S /bin/sh
echo $*
/usr/local/bin/R --no-save <$1 $* 
