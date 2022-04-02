#!/bin/sh

#
# openshift-tests-partner-cert plugin - progress reporter
# Send progress of openshift-tests to sonobuoy worker.
#

set -o pipefail
set -o nounset
set -o errexit

source $(dirname $0)/global_env.sh
source $(dirname $0)/global_fn.sh

os_log_info_local() {
    echo "$(date +%Y%m%d-%H%M%S)> [report] $@"
}

wait_pipe_exists() {
    os_log_info_local "waiting for pipe creation..."
    pip_exists=false
    while true
    do
        test -p ${RESULTS_PIPE} && break
        sleep 1
    done
    os_log_info "[report]  pipe[${RESULTS_PIPE}] created. Starting progress report"
}

watch_plugin_done() {
    os_log_info_local "waiting for plugin done file..."
    while true; do
        if [[ -f "${RESULTS_DONE_NOTIFY}" ]]
        then
            echo "Sonobuoy done detected [waiter]" |tee -a "${RESULTS_PIPE}"
            exit 0
        fi
        sleep 1
    done
    os_log_info_local "plugin done file detected!"
}

watch_dependency_done() {
    os_log_info_local "[plugin dependencies] Starting dependency check..."
    for plugin_name in ${PLUGIN_BLOCKED_BY[@]}; do
        os_log_info_local "waiting for plugin [${plugin_name}]"
        timeout_checks=0
        timeout_count=100
        while true;
        do
            if [[ -f "${RESULTS_DONE_NOTIFY}" ]]
            then
                echo "Sonobuoy done detected [waiter watch]" |tee -a "${RESULTS_PIPE}"
                exit 0
            fi

            ./sonobuoy status --json > /tmp/sonobuoy-status.json 2>/dev/null
            plugin_status=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.status // \"\"" /tmp/sonobuoy-status.json)
            if [[ "${plugin_status}" == "complete" ]]; then
                echo "Plugin[${plugin_name}] with status[${plugin_status}] is completed!"
                break
            fi
            count=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.progress.completed // \"0\"" /tmp/sonobuoy-status.json)
            total=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.progress.total // \"0\"" /tmp/sonobuoy-status.json)
            remaining=$(( total - count ))
            test $remaining -ge 0 && remaining=$(( (total - count) * (-1) ))

            waiting_for_msg="status=waiting-for-plugin=${plugin_name}=(0/${remaining}/0)=[${timeout_checks}/${timeout_count}]"
            body="{
                \"completed\":${remaining},
                \"total\":0,
                \"failures\":[\"0\"],
                \"msg\":\"${waiting_for_msg}\"
            }"
            os_log_info_local "Sending report payload: $(echo ${body} |tr '\n' '')"
            curl -s "${PROGRESS_URL}" -d "${body}"

            timeout_checks=$(( timeout_checks + 1 ))
            if [[ ${timeout_checks} -eq ${timeout_count} ]]; then
                echo "Timeout waiting condition 'complete' for plugin[${plugin_name}]."
                exit 1
            fi
            sleep 10
        done
        os_log_info_local "plugin [${plugin_name}] finished!"
    done
    os_log_info_local "[plugin dependencies] Finished!"
}

report_sonobuoy_progress() {
    local has_update
    PROGRESS+=( ["completed"]=0 ["total"]=0 ["failures"]="" ["msg"]="" )
    has_update=0

    while true
    do
        # Watch sonobuoy done file
        if [[ -f "${RESULTS_DONE_NOTIFY}" ]]
        then
            echo "Sonobuoy done detected [main]"
            break
        fi

        while read line;
        do
            #TODO(bug): JOB_PROGRESS is not detecting the last test count. Example: 'started: (0/10/10)''
            local job_progress
            job_progress=$(echo $line | grep -Po "\([0-9]{1,}\/[0-9]{1,}\/[0-9]{1,}\)" || true);
            if [ ! -z "${job_progress}" ]; then
                has_update=1;
                PROGRESS["completed"]=$(echo ${job_progress:1:-1} | cut -d'/' -f 2)
                PROGRESS["total"]=$(echo ${job_progress:1:-1} | cut -d'/' -f 3)

            elif [[ $line == failed:* ]]; then
                if [ -z "${jobs_faulures}" ]; then
                    PROGRESS["failures"]=\"$(echo $line | cut -d"\"" -f2)\"
                else
                    PROGRESS["failures"]+=,\"$(echo $line | cut -d"\"" -f2)\"
                fi
                has_update=1;
            fi

            if [ $has_update -eq 1 ]; then
                body="{
                    \"completed\":${PROGRESS["completed"]},
                    \"total\":${PROGRESS["total"]},
                    \"failures\":[${PROGRESS["failures"]}],
                    \"msg\":\"status=running\"
                }"
                os_log_info_local "Sending report payload: $(echo ${body} |tr '\n' '')"
                curl -s -d "${body}" "${PROGRESS_URL}"
                has_update=0;
            fi
            job_progress="";

        done <"${RESULTS_PIPE}"
    done
}

set_config
os_log_info_local "PLUGIN_BLOCKED_BY=${PLUGIN_BLOCKED_BY[@]}"

wait_pipe_exists
watch_plugin_done &
watch_dependency_done &
report_sonobuoy_progress

body="{
    \"msg\":\"status=report-progress-finished\"
}"
body="{
    \"completed\":${PROGRESS["completed"]},
    \"total\":${PROGRESS["total"]},
    \"failures\":[${PROGRESS["failures"]}],
    \"msg\":\"status=report-progress-finished\"
}"
os_log_info_local "Sending report payload: $(echo ${body} |tr '\n' '')"
curl -s -d "${body}" "${PROGRESS_URL}"

os_log_info_local "all done"
