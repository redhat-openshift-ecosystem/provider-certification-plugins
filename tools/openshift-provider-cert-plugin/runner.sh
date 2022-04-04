#!/usr/bin/env bash

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
# set -o errexit

# shellcheck disable=SC1091
source "$(dirname "$0")"/global_env.sh
# shellcheck disable=SC1091
source "$(dirname "$0")"/global_fn.sh

os_log_info_local() {
    os_log_info "$(date +%Y%m%d-%H%M%S)> [runner] $*"
}

os_log_info_local "Starting plugin..."

create_dependencies_plugin
set_config

# Notify sonobuoy worker with e2e results (junit)
# https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types
sig_handler_save_results() {

    os_log_info_local "Saving results triggered. Slowing down..."
    sleep 5

    pushd "${RESULTS_DIR}" || exit 1

    # JUnit
    os_log_info_local "Looking for junit result files..."
    junit_output="$(ls junit*.xml || true)";

    # Create empty junit result file to avoid failures on report.
    # It happens when tests file is empty.
    # TODO(pre-release): review that strategy
    if [[ -z "${junit_output}" ]]; then
        local res_file
        res_file="junit_empty_e2e_$(date +%Y%m%d-%H%M%S).xml"
        os_log_info_local "Creating empty Junit result file [${res_file}]"
        cat << EOF > "${res_file}"
<testsuite name="openshift-tests" tests="0" skipped="0" failures="0" time="1"><property name="TestVersion" value="v4.1.0-4964-g555da83"></property></testsuite>
EOF
        junit_output=$(ls junit*.xml);
    fi

    os_log_info_local "Adjusting permissions for results files."
    chmod 644 "${junit_output}";

    os_log_info_local "Sending sonobuoy worker the result file path"
    echo "${RESULTS_DIR}/${junit_output}" > "${RESULTS_DONE_NOTIFY}"

    popd || true;
    os_log_info_local "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/${junit_output}]";
}
trap sig_handler_save_results EXIT

# TODO(serial-execution): add a wait flow to lock execution while
# lower 'level' did not finished (serial execution). Running suites in parallel
# may impact on the results (mainly in monitoring).
# https://github.com/mtulio/openshift-provider-certification/issues/2
os_log_info_local "starting waiter..."
"$(dirname "$0")"/wait-plugin.sh

os_log_info_local "starting executor..."

"$(dirname "$0")"/executor.sh #| tee -a ${results_script_dir}/executor.log

# TODO(report): add a post processor of JUnit to identify flakes
# https://github.com/mtulio/openshift-provider-certification/issues/14

os_log_info_local "Plugin finished. Result[$?]";
