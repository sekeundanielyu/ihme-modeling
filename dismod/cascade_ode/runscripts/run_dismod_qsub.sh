#!/bin/sh
#$ -S /bin/sh
source /etc/profile.d/sge.sh
user_name=$1
model_id=$2
push_results_into_database=1
log_file="/share/temp/sgeoutput/${user_name}/qsub_log.$$"
#
echo $* > $log_file
#
# Need to set current working directory to this particular value
working_dir=/ihme/code

# qsub the pandas version
cat << EOF > /tmp/run_dismod.$$
/usr/local/UGE-dev/bin/lx-amd64/qsub \
-N dm_${model_id}_P \
-P proj_dismod \
-e /share/temp/sgeoutput/epi/cascade_dev/errors \
-o /share/temp/sgeoutput/epi/cascade_dev/output \
${working_dir}/panda_cascade/runscripts/_run_pandas_dismod_qsub.sh \
${model_id}
EOF

Pcmd=`cat /tmp/run_dismod.$$`
# Run the panda cascade
echo "sudo -u ${user_name} sh -c source /etc/profile.d/sge.sh;$Pcmd" >> $log_file
sudo -u ${user_name} sh -c ". /etc/profile.d/sge.sh;$Pcmd"
