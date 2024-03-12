#!/usr/bin/env bash

#
# openshift-tests-conformance (plugin)
#

set -o pipefail
set -o nounset
# set -o errexit

declare -gxr SERVICE_NAME="plugin"

# shellcheck disable=SC1091
source "$(dirname "$0")"/global_env.sh
# shellcheck disable=SC1091
source "$(dirname "$0")"/global_fn.sh

os_log_info "Starting plugin..."

create_dependencies_plugin

# Notify sonobuoy worker with e2e results (junit)
# https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types
sig_handler_save_results() {

    local junit_prefix
    local junit_output
    junit_prefix="junit"
    os_log_info "Saving results triggered. Slowing down..."
    sleep 5

    pushd "${RESULTS_DIR}" || exit 1

    # custom result by plugin
    ## artifacts-collector: raw
    if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_ARTIFACTS_COLLECTOR}" ]]; then
        echo "${RESULTS_DIR}/raw-results.tar.gz" > "${RESULTS_DONE_NOTIFY}"
        os_log_info "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/raw-results.tar.gz]";
        exit
    elif [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_UPGRADE}" ]]; then
        # 'openshift-tests run-upgrade' generates 3 JUnits (2x junit_e2e_*.xml, 1x junit_upgrade_*.xml)
        # TODO: it's desired to collect all openshift-tests metadata.
        # To collect all metadata a few transformation should be done when discoverying the junits:
        # - 1) identify the junit responsible by the execution (to be used by Sonobuoy)
        # - 2) pack the metadata into tarball to avoid post-processor discoverying/processing files
        # - 3) change the result format to raw
        # - 4) send to aggregator the raw results
        # https://issues.redhat.com/browse/OPCT-33
        junit_prefix="junit_upgrade"
    fi

    # generic result file: JUnit
    os_log_info "Looking for junit result files..."
    mapfile -t JUNIT_FILES < <(ls ${junit_prefix}*.xml 2>/dev/null)
    os_log_info "JUnit files found=[${JUNIT_FILES[*]}]"

    # Create failed junit result file to avoid failures on report.
    # It could happened when executor has crashed.
    if [[ "${#JUNIT_FILES[*]}" -eq 0 ]]; then
        msg="[runner] default error handler: openshift-tests did not created JUnit file(s)"
        os_log_info "ERROR: ${msg}"
        create_junit_with_msg "failed" "[opct] ${msg}"
        junit_output=$(ls ${junit_prefix}*.xml);

    elif [[ "${#JUNIT_FILES[*]}" -gt 1 ]]; then
        os_log_info "More than one JUnit found=[${#JUNIT_FILES[*]}], using only ${JUNIT_FILES[0]}"
        junit_output=${JUNIT_FILES[0]}
    else
        junit_output=${JUNIT_FILES[0]}
    fi

    os_log_info "Adjusting permissions for results files."
    chmod 644 "${junit_output}";

    os_log_info "Sending plugin done to unlock report-progress"
    touch "${PLUGIN_DONE_NOTIFY}"

    os_log_info "Sending sonobuoy worker the result file path"
    openshift-tests-plugin exec progress-msg --message "status=runner=done"
    echo "${RESULTS_DIR}/${junit_output}" > "${RESULTS_DONE_NOTIFY}"

    popd || true;
    os_log_info "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/${junit_output}]";
}
trap sig_handler_save_results EXIT

# TODO add flag to "wait-for worker API ready"
echo ">>> wait_progress_api"
wait_progress_api
openshift-tests-plugin exec progress-msg --message "status=initializing";

os_log_info "logging to the cluster..."
openshift_login

os_log_info "starting preflight checks..."
preflight_check_upgrade

os_log_info "starting sonobuoy status scraper..."
start_status_collector &

os_log_info "starting utilities extractor..."
if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_KUBE_CONFORMANCE}" ]] || [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_CONFORMANCE}" ]]; then
    os_log_info "starting utilities extractor...(skip)"
else
    start_utils_extractor &
fi

os_log_info "initializing plugin config..."
init_config
show_config

os_log_info "check and wait for dependencies..."
#wait_status_file
os_log_info "check and wait for dependencies..."
if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_KUBE_CONFORMANCE}" ]] ||
    [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_CONFORMANCE}" ]] ||
    [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_UPGRADE}" ]]; then
    os_log_info "check and wait for dependencies...(skip)"
else
    wait_utils_extractor
fi

os_log_info "updating runtime configuration..."
update_config

#
# Replace wait-plugin for progress reporter
#
#os_log_info "starting waiter..."
#"$(dirname "$0")"/wait-plugin.sh
PIDS_LOCAL=()
PROGRESS=( ["completed"]=0 ["total"]=${CERT_TEST_COUNT} ["failures"]="" ["msg"]="starting..." )
COUNTER_TOTAL=${CERT_TEST_COUNT}
COUNTER_STARTED=0
COUNTER_FAILED=0
COUNTER_PASSED=0
COUNTER_SKIPPED=0
COUNTER_COMPLETED=0
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
watch_dependency_done

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

echo ">>> report_progress"
openshift-tests-plugin exec progress-msg --message "status=running";
report_progress &
PIDS_LOCAL+=($!)
echo ">>> report_progress DONE"
echo ">>> PIDS 3=${PIDS_LOCAL[*]}"

# Force to update the utilities after cluster upgrades.
# It's mandatory to avoid running clusters with old e2e binaries.
if [[ "${RUN_MODE:-''}" == "${PLUGIN_RUN_MODE_UPGRADE}" ]]; then
    if [[ "${PLUGIN_ID}" != "${PLUGIN_ID_OPENSHIFT_UPGRADE}" ]]; then
        os_log_info "starting utilities extractor updater..."
        start_utils_extractor
    else
        os_log_info "skiping extractor updater: ${PLUGIN_ID:-''}==${PLUGIN_ID_OPENSHIFT_UPGRADE}"
    fi
else
    os_log_info "skiping extractor updater: ${RUN_MODE:-''}!=${PLUGIN_RUN_MODE_UPGRADE}"
fi

os_log_info "starting executor..."
"$(dirname "$0")"/executor.sh #| tee -a ${results_script_dir}/executor.log

os_log_info "Waiting for PIDs [finalizer]: ${PIDS_LOCAL[*]}"
#wait "${PIDS_LOCAL[@]}"
echo ">>> PIDS 4=${PIDS_LOCAL[*]}"

# echo ">>> UNBLOCKED. Sending final message"
# openshift-tests-plugin exec progress-msg --message "status=report-progress-finished"
# echo ">>> PIDS 5=${PIDS_LOCAL[*]}"

# TODO(report): add a post processor of JUnit to identify flakes
# https://github.com/mtulio/openshift-provider-certification/issues/14

openshift-tests-plugin exec progress-msg --message "status=runner=preparing results"
os_log_info "Plugin finished.";
