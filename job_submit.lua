--
-- Slurm job submit for ARCHER2
--
-- Copyright: (C) 2020-2021 EPCC
--
-- Contact: Iakovos Panourgias (i.panourgias@epcc.ed.ac.uk)
--          Steven Robson (s.robson@epcc.ed.ac.uk)
--
-- This program is free software; you can redistribute in and/or modify
-- it under the terms of the GNU General Public License, version 2, as
-- published by the Free Software Foundation.  This program is
-- distributed in the hope that it will be useful, but WITHOUT ANY
-- WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
-- for more details.  On Calibre systems, the complete text of the GNU
-- General Public License can be found in
-- `/usr/share/common-licenses/GPL'.
--
--

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end


function slurm_job_submit ( job_desc, part_list, submit_uid )
    username                 = job_desc.user_name
    time_limit               = job_desc.time_limit       -- equal to "--time="
    name                     = job_desc.name
    shared                   = job_desc.shared
    min_nodes                = job_desc.min_nodes        -- equal to "--nodes"
    num_tasks                = job_desc.num_tasks        -- equal to "--ntasks="
    ntasks_per_node          = job_desc.ntasks_per_node  -- equal to "--ntasks-per-node="
    min_mem_per_node         = job_desc.min_mem_per_node -- equal to "--mem="
    min_mem_per_cpu          = job_desc.min_mem_per_cpu  -- equal to "--mem-per-cpu="
    tres_per_node            = job_desc.tres_per_node    -- equal to "--gres=gpu:X"
    req_nodes                = job_desc.req_nodes        -- equal to "-w nodelist"
    exc_nodes                = job_desc.exc_nodes        -- equal to " -x, --exclude=<node name list>"
    partition                = job_desc.partition
    reservation_name         = job_desc.reservation
    qos                      = job_desc.qos
    work_dir                 = job_desc.work_dir
    user_account             = job_desc.account
    default_account          = job_desc.default_account
    features                 = job_desc.features
    switches                 = job_desc.req_switch

    gpu_node_cpus            = 128  -- Number of cores in a GPU node
    gpus_per_node            = 4    -- Number of GPUs in a GPU node
    num_gpus_num             = 0
    num_gpus_text            = "none"
    user_spec_nodes          = 0
    user_spec_tasks          = 0
    user_spec_tasks_per_node = 0

    standardlength=1440

    slurm.log_info("archer2_job_submit: Job submission evaluation START for %s", username)

    if tres_per_node ~= nil then
        num_gpus_text=string.match(tres_per_node, ":(.*)")
        num_gpus_num=tonumber(num_gpus_text)
        slurm.log_info("archer2_job_submit: GPUs found so GPUs %u", num_gpus_num)
    else
        num_gpus_num = 0
        slurm.log_info("archer2_job_submit: GPUs not found so GPUs %u", num_gpus_num)
    end

    if shared ~= 0 then
        slurm.log_info("archer2_job_submit: Shared Job")
    elseif shared == 0 then
        slurm.log_info("archer2_job_submit: Exclusive Job")
    end

    if min_mem_per_node == nil then
        min_mem_per_node = 0
        slurm.log_info("archer2_job_submit: min_mem_per_node was nil, set to 0")
    end

    if min_mem_per_cpu == nil then
        min_mem_per_cpu = 0
        slurm.log_info("archer2_job_submit: min_mem_per_cpu was nil, set to 0")
    end

    if min_nodes == nil then
        slurm.log_info("archer2_job_submit: min_nodes was nil")
    elseif min_nodes == 4294967294 then
        slurm.log_info("archer2_job_submit: min_nodes was 4294967294")
    elseif min_nodes == 1 then
        slurm.log_info("archer2_job_submit: min_nodes was 1")
    else
        user_spec_nodes = 1
        slurm.log_info("archer2_job_submit: user specified min_nodes was %s", min_nodes)
    end

    if ntasks_per_node == nil then
        ntasks_per_node = 1
        slurm.log_info("archer2_job_submit: ntasks_per_node was nil, set to 1")
    else
        user_spec_tasks_per_node = 1
        slurm.log_info("archer2_job_submit: user specified ntasks_per_node was %s", ntasks_per_node)
    end

    if num_tasks == nil then
        num_tasks = 1
        slurm.log_info("archer2_job_submit: num_tasks was nil, set to 1")
    elseif num_tasks > 42949672 then
        num_tasks = 1
        slurm.log_info("archer2_job_submit: num_tasks was not provided, set to 1")
    else
        user_spec_tasks = 1
        slurm.log_info("archer2_job_submit: user specified num_tasks was %s", num_tasks)
    end

    -- Account checking - Log default and specified budget account
    if default_account ~= nil then
        slurm.log_info("archer2_job_submit: default account is %s", default_account)
    else
        slurm.log_info("archer2_job_submit: no default account")
    end

    if user_account ~= nil then
        slurm.log_info("archer2_job_submit: account provided %s", user_account)
    else
        slurm.log_info("archer2_job_submit: no account provided")
    end

    if features ~= nil then
        slurm.log_info("archer2_job_submit: Features supplied is %s", features)
    else
        slurm.log_info("archer2_job_submit: no features requested")
    end

    if switches  ~= nil then
        slurm.log_info("archer2_job_submit: Switches supplied is %s", switches)
    else
        slurm.log_info("archer2_job_submit: No switches requested")
    end

    -- Partition tests - Ensure that standard/largemem jobs are exclusive and that others request nodes appropriately
    if partition ~= nil then
        slurm.log_info("archer2_job_submit: partition specified %s",partition)
        if string.find(partition, "standard") or string.find(partition, "highmem") then
            --  If request memory, reject
            if min_mem_per_cpu ~= 0 then
                slurm.log_info("archer2_job_submit: memory specified. Reject job")
                slurm.log_user("Job rejected: Please do not specify memory for node-exclusive jobs.")
                return slurm.ERROR
            elseif min_mem_per_node ~= 0 then
                slurm.log_info("archer2_job_submit: memory specified. Reject job")
                slurm.log_user("Job rejected: Please do not specify memory for node-exclusive jobs.")
                return slurm.ERROR
            end
            -- set job to exclusive for standard and highmem partitions
            slurm.log_info("archer2_job_submit: Setting job to exclusive for standard or highmem")
            job_desc.shared = 0
        elseif string.find(partition, "gpu") then
            if num_gpus_num == 0 then
                --  if scheduling in GPU land, must ask for X GPUs
                slurm.log_info("archer2_job_submit: gpu partition detected but no gpus requested. Reject job")
                slurm.log_user("Job rejected: GPU partition specified but no GPU specification found. Please use --gres=gpu:X to specify GPUs.")
                return slurm.ERROR
            elseif user_spec_tasks == 1 and user_spec_tasks_per_node == 1 then
                --  if ask for GPUs and asked for cores, reject.
                slurm.log_info("archer2_job_submit: gpu partition but cores specified. Reject job")
                slurm.log_user("Job rejected: Please do not specify cores/CPUs/tasks for GPU jobs. This is controlled in proportion to GPUs requested.")
                return slurm.ERROR
            else
                --  if ask for GPUs set cores to (numcores/gpus_per_node) * GPUS
                ntasks = ((gpu_node_cpus/gpus_per_node) * num_gpus_num)
                job_desc.num_tasks = num_gpus_num
                job_desc.cpus_per_task = gpu_node_cpus/gpus_per_node
                slurm.log_info("archer2_job_submit: gpu partition job - GPUs:%u calculated cores:%u", num_gpus_num, ntasks)
            end
        elseif string.find(partition, "serial") then
            if user_spec_nodes == 1 then
                -- If using serial nodes, must not ask for nodes
                slurm.log_info("archer2_job_submit: Serial partition requested but nodes specified. Reject job")
                slurm.log_user("Job rejected: Serial nodes are shared nodes. Please do not request whole nodes.")
                return slurm.ERROR
            end
            if shared == 0 then
                -- If using serial nodes, must not ask for exclusive
                slurm.log_info("archer2_job_submit: Serial partition requested but exclusive requested. Reject job")
                slurm.log_user("Job rejected: Serial nodes are shared nodes. Please do not request exclusive access.")
                return slurm.ERROR
            end
        elseif shared ~= 0 and user_spec_nodes == 1 then
            --  Catchall if ask for nodes and not ask --exclusive, then reject.
            slurm.log_info("archer2_job_submit: Nodes specified and not exclusive. Reject job")
            slurm.log_user("Job rejected: Nodes specified but the --exclusive flag is not specifed. Please use the --exclusive flag if you need to request whole nodes, or specify tasks, memory or cpus(cores) if not.")
            return slurm.ERROR
        end
    else
        -- Reject jobs that don't specify a partition
        slurm.log_info("archer2_job_submit: partition not specified")
        slurm.log_user("Job rejected: Please specify a partition name.")
        return slurm.ERROR
    end

    -- If ask for specific nodes or to exclude nodes, then reject
    if req_nodes ~= nil and not string.find(partition, "maintenance") then
        slurm.log_info("archer2_job_submit: Specific nodes requested. Reject job")
        slurm.log_user("Job rejected: Please do not request specific nodes.")
        return slurm.ERROR
    elseif exc_nodes ~= nil and not string.find(partition, "maintenance") then
        slurm.log_info("archer2_job_submit: Specific nodes excluded. Reject job")
        slurm.log_user("Job rejected: Please do not request to exclude specific nodes.")
        return slurm.ERROR
    elseif req_nodes ~= nil and string.find(partition, "maintenance") then
        slurm.log_info("archer2_job_submit: Specific nodes requested in maintenance partition request %s", req_nodes)
    elseif exc_nodes ~= nil and string.find(partition, "maintenance") then
        slurm.log_info("archer2_job_submit: Specific nodes excluded in maintenance partition request %s", exc_nodes)
    end

    -- QoS and time limit tests
    if qos ~= nil then
        slurm.log_info("archer2_job_submit: qos specified %s",qos)
        if string.find(qos, "short") then
            slurm.log_info("archer2_job_submit: short qos requested, setting shortqos reservation")
            job_desc.reservation = "shortqos"
        end
        if reservation_name ~= nil then
            -- A reservation name has been specified
            if string.find(reservation_name, "shortqos") then
                if string.find(qos, "short") then
                    slurm.log_info("archer2_job_submit: short qos requested with shortqos reservation. Continue")
                else
                    -- Not a short/shortqos job, so must use reject this. They must go together.
                    slurm.log_info("archer2_job_submit: non-short qos requested with shortqos reservation. Reject job")
                    slurm.log_user("Job rejected: The shortqos reservation cannot be used without the short QoS. Please use the short QoS.")
                    return slurm.ERROR
                end
            else
                if string.find(qos, "reservation") then
                    -- Correctly using reservations QoS with a reservation.
                    slurm.log_info("archer2_job_submit: reservation qos requested with non-shortqos reservation. Continue")
                else
                    -- Reject job because reservation QoS should be used with a reservation.
                    slurm.log_info("archer2_job_submit: non-reservation qos requested with normal reservation. Reject job")
                    slurm.log_user("Job rejected: Please use the reservation QoS for this reservation.")
                    return slurm.ERROR
                end
            end

        end
        if string.find(qos, "long") then
            if time_limit ~= nil then
                slurm.log_info("archer2_job_submit: time specified %s",time_limit)
                if time_limit <= standardlength or time_limit == nil or time_limit == 4294967294 then
                    -- For long QoS jobs: If job max walltime is less than or equal to standard time limit, should not submit to long
                    slurm.log_info("archer2_job_submit: long qos requested but job is not long. Reject job")
                    slurm.log_user("Job rejected: This job has 24 hours or less of walltime requested. Please consider the standard or taskfarm QoS for this job.")
                    return slurm.ERROR
                end
            else
                -- No time limit, so this is just wrong for a long job, should be >24h
                slurm.log_info("archer2_job_submit: long qos requested but job is not long. Reject job")
                slurm.log_user("Job rejected: This job has 24 hours or less of walltime requested. Please consider the standard or taskfarm QoS for this job.")
                return slurm.ERROR
            end
        end
    else
        slurm.log_info("archer2_job_submit: No qos specified. Reject job")
        slurm.log_user("Job rejected: Please specify a QoS.")
        return slurm.ERROR
    end

    --  If no time specified, then present warning message to user.
    if time_limit == nil or time_limit == 4294967294 then
        if string.find(qos, "short") then
            slurm.log_info("archer2_job_submit: short qos resquested without time limit. Setting to 20mins")
            slurm.log_user("Your job has no time specification (--time=). The maximum time for the short QoS of 20 minutes has been applied.")
            job_desc.time_limit = 20
        else
            slurm.log_info("archer2_job_submit: No time limit specified")
            slurm.log_user("Your job has no time specification (--time=) and the default time is short. You can cancel your job with 'scancel <JOB_ID>' if you wish to resubmit.")
        end
    else
        slurm.log_info("archer2_job_submit: time limit is %s", time_limit)
    end

    if work_dir ~= nil then
        slurm.log_info("archer2_job_submit: work_dir is %s",work_dir)
        if string.starts(work_dir, "/mnt/lustre/a2fs") or string.starts(work_dir, "/work") then
            slurm.log_info("archer2_job_submit: work_dir is %s which is within /work or on NVME, continue",work_dir)
        elseif string.find(partition, "serial") then
            -- Serial node so work dir can be on home or RDFaaS
            slurm.log_info("archer2_job_submit: work_dir is %s which should be OK on serial nodes, continue",work_dir)
        else
            -- Normal compute or GPU node so warn the user
            slurm.log_info("archer2_job_submit: work_dir is %s which is not within /work or on NVME, warn user",work_dir)
            slurm.log_user("Warning: It appears your working directory may not be on the work filesystem. It is %s. The home filesystem and RDFaaS are not available from the compute nodes - please check that this is what you intended. You can cancel your job with 'scancel <JOBID>' if you wish to resubmit.", work_dir)
        end
    end

    -- Job has passed all tests. Log submission details and END, return successful to Slurm so it will continue to try and schedule the job.
    slurm.log_info("archer2_job_submit: user %s, submitted a job %s with %d tasks (shared:%d, ntasks_per_node:%d, min_mem_per_node:%d, min_mem_per_cpu:%d, min_nodes:%d)",
                username, name, num_tasks, shared, ntasks_per_node, min_mem_per_node, min_mem_per_cpu, min_nodes)

    slurm.log_info("archer2_job_submit: Job submission evaluation END for %s", username)
    return slurm.SUCCESS
end

function slurm_job_modify ( job_desc, job_rec, part_list, modify_uid )
    slurm.log_info("archer2_job_submit: slurm_job_modify")

    return slurm.SUCCESS
end

slurm.log_info("initialized")

return slurm.SUCCESS
-- End of job submission lua script.

