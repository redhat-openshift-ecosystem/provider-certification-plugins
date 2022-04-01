#!/usr/bin/env sh

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
# set -o errexit

source $(dirname $0)/shared.sh

os_log_info_runner() {
    os_log_info "$(date +%Y%m%d-%H%M%S)> [runner] $@"
}

os_log_info_runner "Starting plugin..." |tee -a ${results_script_dir}/runner.log

# Notify sonobuoy worker with e2e results (junit)
# https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types
save_results() {

    os_log_info_runner "Saving results triggered. Slowing down..."
    sleep 5

    pushd ${results_dir};

    # JUnit
    os_log_info_runner "Looking for junit result files..."
    JUNIT_OUTPUT="$(ls junit*.xml || true)";

    # Create empty junit result file to avoid failures on report.
    # It happens when tests file is empty.
    # TODO(pre-release): review that strategy
    if [[ -z "${JUNIT_OUTPUT}" ]]; then
        local res_file="junit_empty_e2e_$(date +%Y%m%d-%H%M%S).xml"
        os_log_info_runner "creating empty junit result file [${res_file}]"
        cat << EOF > "${res_file}"
<testsuite name="openshift-tests" tests="0" skipped="0" failures="0" time="1"><property name="TestVersion" value="v4.1.0-4964-g555da83"></property></testsuite>
EOF
        JUNIT_OUTPUT=$(ls junit*.xml);
    fi

    os_log_info_runner "adjusting permissions to results."
    chmod 644 ${JUNIT_OUTPUT};

    os_log_info_runner "telling sonobuoy worker the result file"
    echo '/tmp/sonobuoy/results/'${JUNIT_OUTPUT} > ${results_dir}/done

    popd;
    os_log_info_runner "Results saved at ${results_dir}/done=[/tmp/sonobuoy/results/${JUNIT_OUTPUT}]";
}
trap save_results EXIT

os_log_info_runner "Creating results pipe to progress updater..."
mkfifo ${results_pipe}

# TODO(serial-execution): add a wait flow to lock execution while
# lower 'level' did not finished (serial execution). Running suites in parallel
# may impact on the results (mainly in monitoring).
# https://github.com/mtulio/openshift-provider-certification/issues/2
os_log_info_runner "starting waiter..."
$(dirname $0)/wait-plugin.sh

os_log_info_runner "starting executor..."

$(dirname $0)/executor.sh #| tee -a ${results_script_dir}/executor.log

# TODO(report): add a post processor of JUnit to identify flakes
# https://github.com/mtulio/openshift-provider-certification/issues/14

os_log_info_runner "Plugin finished. Result[$?]";
