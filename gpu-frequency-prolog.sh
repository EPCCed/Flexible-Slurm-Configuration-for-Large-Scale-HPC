#!/bin/bash
# Run these scripts before the job runs - as the user running the job
# If the script needs root access, make sure you add it to sudo

# EXIT CODES
# 0 - OK
# 1 - General Error
# 5 - Failed to create files in /tmp
# 6 - Failed to remove files in /tmp
# 7 - Failed to create file in HOME
# 8 - Failed to remove files from HOME
# 9 - Failed to obtain SLURM user
# 10 - Failed to obtain SLURM job ID


### DEBUG
#echo "+-+" > /tmp/slurm_env
#hostname >> /tmp/slurm_env
#echo "user: ${SLURM_JOB_USER}" >> /tmp/slurm_env
#env >> /tmp/slurm_env
#echo "-+-" >> /tmp/slurm_env


##
## This script is shared between the compute and login
## and is called on BOTH the compute and login
## so filter out some of the actions for the login nodes
##

## Get the current hostname
s_hostname=$(hostname)

## Set the nodes to filter out
s_login_array=(login1,login2,login3,login4)

## Check our hostname against the login node array
if [[ "${s_login_array[@]}" =~ "${s_hostname}" ]]; then
       	# Nothing to do on a login node so just exit
        exit 0
fi

##
## Add the user's group to huge pages
##

echo "$SLURM_JOB_GID"  > /proc/sys/vm/hugetlb_shm_group
##Set default application clock GPU Frequency and Memory
gpuFreq=1050
gpuFreqMemory=1215


##Get the command line argument, as it is not directly available in the prolog env
prolog_job_params=$(scontrol show job -o $SLURM_JOB_ID)

##Set application clock GPU Frequency if supplied as an argument
if [[ $prolog_job_params =~ " TresFreq=" ]]; then
        DIRAC_TRES_FREQ=$(echo "$prolog_job_params" | /usr/bin/sed 's/.*TresFreq=\([,:=a-z,0-9]*\).*/\1/')
        if [[ $DIRAC_TRES_FREQ =~ "gpu:"[0-9]*",memory="[0-9]* ]]; then
                ##gpuFreqMemory=$(echo "$DIRAC_TRES_FREQ" | /usr/bin/awk -F [:,=] '{print $4}')
                gpuFreq=$(echo "$DIRAC_TRES_FREQ" | /usr/bin/awk -F [:,=] '{print $2}')
                echo "Detected a GPU Frequency argument of $gpuFreq. GPU Frequency must be a multiple of 15 no lower than 210 or higher than 1410."
                echo "Detected a Application clock memory argument of $gpuFreqMemory. Presently the only valid value is 1215."
        elif [[ $DIRAC_TRES_FREQ =~ "gpu:"[0-9]* ]]; then
                gpuFreq=$(echo "$DIRAC_TRES_FREQ" | /usr/bin/awk -F [:,=] '{print $2}')
                echo "Detected a GPU Frequency argument of $gpuFreq. GPU Frequency must be a multiple of 15 no lower than 210 or higher than 1410."
        else
                echo "Did not detect Applications Clocks GPU Frequency value to set, defaulting to $gpuFreq,$gpuFreqMemory"
        fi

fi

##Supply values to nvidia-smi -ac, specifying clocks as a pair (e.g. 1215,1050) that defines GPU's speed in MHz while running applications on a GPU.

/usr/bin/nvidia-smi -ac $gpuFreqMemory,$gpuFreq

##
## Create temp file of the slurm job ID
## used for epilogue cleanup
##
echo $NV_GPU > /tmp/GPU${SLURM_JOB_ID}.txt
if [ ! -f /tmp/GPU${SLURM_JOB_ID}.txt ] ; then
  echo $CUDA_VISIBLE_DEVICES > /tmp/GPU${SLURM_JOB_ID}.txt
fi

##
## Run checks to ensure host is healthy. Checks /tmp and $HOME
##
touch /tmp/$$.tmp
if [ $? -ne 0 ] ; then
        echo "Unable to create file in /tmp/ on $HOSTNAME"   ; exit 5
fi
rm -f /tmp/$$.tmp
if [ $? -ne 0 ] ; then
        echo "Unable to remove file from /tmp/ on $HOSTNAME" ; exit 6
fi

touch $HOME/$$.tmp
if [ $? -ne 0 ] ; then
        echo "Unable to create file in $HOME on $HOSTNAME"   ; exit 7
fi

rm -f $HOME/$$.tmp
if [ $? -ne 0 ] ; then
        echo "Unable to remove file from $HOME on $HOST"     ; exit 8
fi

exit 0
