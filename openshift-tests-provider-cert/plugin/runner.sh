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

    os_log_info "Saving results triggered. Slowing down..."
    sleep 5

    pushd "${RESULTS_DIR}" || exit 1

    # raw results
    if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_ARTIFACTS_COLLECTOR}" ]]; then
        echo "${RESULTS_DIR}/raw-results.tar.gz" > "${RESULTS_DONE_NOTIFY}"
        os_log_info "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/raw-results.tar.gz]";
        exit
    fi
    # JUnit
    os_log_info "Looking for junit result files..."
    junit_output="$(ls junit*.xml || true)";

    # Create failed junit result file to avoid failures on report.
    # It could happened when executor has crashed.
    if [[ -z "${junit_output}" ]]; then
        msg="[runner] default error handler: openshift-tests did not created JUnit file"
        os_log_info "ERROR: ${msg}"
        create_junit_with_msg "failed" "[opct] ${msg}"
        junit_output=$(ls junit*.xml);
    fi

    os_log_info "Adjusting permissions for results files."
    chmod 644 "${junit_output}";

    os_log_info "Sending plugin done to unlock report-progress"
    touch "${PLUGIN_DONE_NOTIFY}"

    os_log_info "Sending sonobuoy worker the result file path"
    echo "${RESULTS_DIR}/${junit_output}" > "${RESULTS_DONE_NOTIFY}"

    popd || true;
    os_log_info "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/${junit_output}]";
}
trap sig_handler_save_results EXIT

os_log_info "logging to the cluster..."
openshift_login

os_log_info "starting sonobuoy status scraper..."
start_status_collector &

os_log_info "starting openshift-tests utility extractor..."
start_utils_extractor &

os_log_info "initializing plugin config..."
init_config
show_config

os_log_info "check and wait for dependencies..."
wait_status_file
wait_utils_extractor

os_log_info "updating runtime configuration..."
update_config

os_log_info "starting waiter..."
"$(dirname "$0")"/wait-plugin.sh

os_log_info "starting executor..."
"$(dirname "$0")"/executor.sh #| tee -a ${results_script_dir}/executor.log

# TODO(report): add a post processor of JUnit to identify flakes
# https://github.com/mtulio/openshift-provider-certification/issues/14

os_log_info "Plugin finished. Result[$?]";
