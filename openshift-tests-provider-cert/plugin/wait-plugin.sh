#!/usr/bin/env bash

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info_local() {
    os_log_info "[waiter] $*"
}

os_log_info_local "Starting Level[${PLUGIN_ID:-}]..."
init_config

os_log_info_local "Checking if there are plugins blocking Level${PLUGIN_ID:-} execution..."
if [[ ${#PLUGIN_BLOCKED_BY[@]} -ge 1 ]]; then
    os_log_info_local "Level${PLUGIN_ID:-} plugin is blocked by: [${PLUGIN_BLOCKED_BY[*]}]"
    for pod_label in "${PLUGIN_BLOCKED_BY[@]}"; do

        os_log_info_local "Waiting for pod running with label: ${pod_label}"
         openshift-tests-plugin exec wait-for-plugin \
            --namespace "${ENV_POD_NAMESPACE}" \
            --plugin "${PLUGIN_NAME}" \
            --blocker "${pod_label}"
    done
    os_log_info_local "All blocker conditions have been completed!"
fi

os_log_info_local "Plugin Level[${PLUGIN_ID:-}] waiter done."
