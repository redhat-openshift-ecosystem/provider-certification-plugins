#!/usr/bin/env bash

#
# openshift-tests-conformance (report-progress)
# Send progress from openshift-tests execution to sonobuoy worker.
#

set -o pipefail
set -o nounset
set -o errexit

declare -gx PIDS_LOCAL
declare -gx PROGRESS
declare -gx COUNTER_TOTAL
declare -gx COUNTER_STARTED
declare -gx COUNTER_PASSED
declare -gx COUNTER_SKIPPED
declare -gx COUNTER_FAILED
declare -gx COUNTER_COMPLETED

declare -gxr SERVICE_NAME="report-progress"

# shellcheck disable=SC1091
source "$(dirname "$0")"/global_env.sh
# shellcheck disable=SC1091
source "$(dirname "$0")"/global_fn.sh

# wait_progress_api waits for sonobuoy worker is listening.
wait_progress_api() {
    local addr_ip
    local addr_port
    addr_ip=$(echo "${PROGRESS_URL}" |grep -Po '(\d+.\d+.\d+.\d+)')
    addr_port=$(echo "${PROGRESS_URL}" |grep -Po '\d{4}')

    os_log_info "waiting for sonobuoy-worker service is ready..."
    while true
    do
        test "$(echo '' | curl telnet://"${addr_ip}":"${addr_port}" >/dev/null 2>&1; echo $?)" -eq 0 && break
        sleep 1
    done
    os_log_info "sonobuoy-worker progress api[${PROGRESS_URL}] is ready."
}


# wait_pipe_exists wait until the pipe file is created by plugin.
wait_pipe_exists() {
    os_log_info "waiting for pipe creation..."
    while true
    do
        test -p "${RESULTS_PIPE}" && break
        sleep 1
    done
    os_log_info "[report]  pipe[${RESULTS_PIPE}] created. Starting progress report"
}

# watch_plugin_done watches to block the plugin to be finished prematurely.
watch_plugin_done() {
    os_log_info "waiting for plugin done file..."
    while true; do
        if [[ -f "${PLUGIN_DONE_NOTIFY}" ]]
        then
            echo "Sonobuoy done detected [done wacther]" |tee -a "${RESULTS_PIPE}"
            return
        fi
        sleep 1
    done
    os_log_info "plugin done file detected!"
}

# update_pogress_upgrade report the progress when the plugin instance is upgrade.
# The message will be the progress message from ClusterVersion object.
update_pogress_upgrade() {
    openshift-tests-plugin exec progress-upgrade \
        --done "${PLUGIN_DONE_NOTIFY}"
}

# watch_dependency_done watches aggregator API (status) to
# unblock the execution when dependencies was finished the execution.
watch_dependency_done() {
    os_log_info "[watch_dependency] Starting dependency check..."
    for plugin_name in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info "waiting for plugin [${plugin_name}]"
        
        openshift-tests-plugin exec wait-updater \
            --init-total=${PROGRESS["total"]:-0} \
            --namespace "${ENV_POD_NAMESPACE}" \
            --plugin "${PLUGIN_NAME}" \
            --blocker "${plugin_name}" \
            --done "${PLUGIN_DONE_NOTIFY}"

    done
    os_log_info "[plugin dependencies] Finished!"
    return
}

# report_progress reads the pipe file, parses the progress counters and reports it
# to worker progress endpoint until the piple file is closed and Done file is created
# by plugin container.
report_progress() {
    openshift-tests-plugin exec progress-report \
        --input-total=${PROGRESS["total"]} \
        --input "${RESULTS_PIPE}" \
        --done "${PLUGIN_DONE_NOTIFY}" \
        --show-rank \
        --rank-reverse \
        --show-limit=20
}

#
# Main
#

openshift_login
init_config

os_log_info "starting preflight checks..."
preflight_check_upgrade_waiter

wait_utils_extractor
update_config

PIDS_LOCAL=()
PROGRESS=( ["completed"]=0 ["total"]=${CERT_TEST_COUNT} ["failures"]="" ["msg"]="starting..." )
COUNTER_TOTAL=${CERT_TEST_COUNT}
COUNTER_STARTED=0
COUNTER_FAILED=0
COUNTER_PASSED=0
COUNTER_SKIPPED=0
COUNTER_COMPLETED=0

echo ">>> wait_status_file"
wait_status_file

echo ">>> wait_progress_api"
wait_progress_api

echo ">>> update msg initializing"
openshift-tests-plugin exec progress-msg --message "status=initializing";

echo ">>> wait_pipe_exists"
wait_pipe_exists

#echo ">>> watch_plugin_done &"
#watch_plugin_done &
#PIDS_LOCAL+=($!)
#echo ">>> PIDS 1=${PIDS_LOCAL[*]}"

echo ">>> watch_dependency_done &"
watch_dependency_done
#PIDS_LOCAL+=($!)
echo ">>> PIDS 2=${PIDS_LOCAL[*]}"

# upgrade plugin
if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_UPGRADE}" ]]; then
    echo ">>> update_pogress_upgrade"
    update_pogress_upgrade &
    PIDS_LOCAL+=($!)
fi

echo ">>> report_progress"
openshift-tests-plugin exec progress-msg --message "status=running";
report_progress
echo ">>> report_progress DONE"
echo ">>> PIDS 3=${PIDS_LOCAL[*]}"

os_log_info "Waiting for PIDs [finalizer]: ${PIDS_LOCAL[*]}"
wait "${PIDS_LOCAL[@]}"
echo ">>> PIDS 4=${PIDS_LOCAL[*]}"

echo ">>> UNBLOCKED. Sending final message"
openshift-tests-plugin exec progress-msg --message "status=report-progress-finished"
echo ">>> PIDS 5=${PIDS_LOCAL[*]}"

os_log_info "all done"
