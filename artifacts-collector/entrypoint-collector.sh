#!/usr/bin/env bash

#
# openshift-tests-plugin / collector
#

set -o pipefail
set -o nounset

declare -gxr SERVICE_NAME="collector"

# shellcheck disable=SC1091
source "$(dirname "$0")"/global_env.sh
# shellcheck disable=SC1091
source "$(dirname "$0")"/global_fn.sh

os_log_info "Starting plugin..."

# Notify sonobuoy worker with e2e results (junit)
# https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types
sig_handler_save_results() {
    os_log_info "Saving results triggered. Slowing down..."
    sleep 5

    pushd "${RESULTS_DIR}" || exit 1

    os_log_info "Sending sonobuoy worker the result file path"
    openshift-tests-plugin exec progress-msg --message "status=runner=done"
    echo "${RESULTS_DIR}/raw-results.tar.gz" > "${RESULTS_DONE_NOTIFY}"
    os_log_info "Results saved at ${RESULTS_DONE_NOTIFY}=[${RESULTS_DIR}/raw-results.tar.gz]";

    popd || true;
}
trap sig_handler_save_results EXIT

openshift-tests-plugin exec progress-msg --message "status=initializing";

os_log_info "logging to the cluster..."
os_log_info "[executor] Checking if credentials are present..."
test -f "${SA_CA_PATH}" || os_log_info "[executor] secret not found=${SA_CA_PATH}"
test -f "${SA_TOKEN_PATH}" || os_log_info "[executor] secret not found=${SA_TOKEN_PATH}"

os_log_info "[login] Login to OpenShift cluster [${KUBE_API_INT}]"
${UTIL_OC_BIN} login "${KUBE_API_INT}" \
    --token="$(cat "${SA_TOKEN_PATH}")" \
    --certificate-authority="${SA_CA_PATH}" || true;

#
# Replace wait-plugin for progress reporter
#
PROGRESS=( ["completed"]=0 ["total"]=${CERT_TEST_COUNT} ["failures"]="" ["msg"]="starting..." )
watch_dependency_done() {
    os_log_info "[watch_dependency] Starting dependency check..."
    for blocker_plugin_name in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info "waiting for plugin [${blocker_plugin_name}]"

        openshift-tests-plugin exec wait-updater \
            --init-total="${PROGRESS["total"]:-0}" \
            --plugin "${PLUGIN_NAME}" \
            --blocker "${blocker_plugin_name}" \
            --done "${PLUGIN_DONE_NOTIFY}"

    done
    os_log_info "[plugin dependencies] Finished!"
    return
}
watch_dependency_done

openshift-tests-plugin exec progress-msg --message "status=running";

os_log_info "starting executor..."
"$(dirname "$0")"/collector.sh

openshift-tests-plugin exec progress-msg --message "status=runner=preparing results"
os_log_info "Plugin finished.";
