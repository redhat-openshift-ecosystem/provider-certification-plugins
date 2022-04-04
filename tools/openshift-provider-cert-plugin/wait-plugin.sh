#!/usr/bin/env bash

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info_waiter() {
    os_log_info "$(date +%Y%m%d-%H%M%S)> [waiter] $*"
}

total_wait_timeout=1h
os_log_info_waiter "Starting Level[${CERT_LEVEL:-}]..."

os_log_info_waiter "PLUGIN_BLOCKED_BY=${PLUGIN_BLOCKED_BY[*]}"
if [[ "${CERT_LEVEL:-}" == "1" ]]
then
    os_log_info_waiter "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
    #PLUGIN_BLOCKED_BY=()

elif [[ "${CERT_LEVEL:-}" == "2" ]]
then
    os_log_info_waiter "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]" 
    PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level1")

elif [[ "${CERT_LEVEL:-}" == "3" ]]
then
    os_log_info_waiter "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
    PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level2")
fi
os_log_info_waiter "PLUGIN_BLOCKED_BY=${PLUGIN_BLOCKED_BY[*]}"

if [[ "${CERT_LEVEL:-}" != "1" ]]; then 
    # Wait the pod to be running
    os_log_info_waiter "Checking if Level[${CERT_LEVEL:-}] is blocked by labels [${PLUGIN_BLOCKED_BY[*]}] are ready..."
    for pod_label in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_waiter "Waiting running pod-label: ${pod_label}"
        kubectl wait \
            --timeout=${total_wait_timeout} \
            --for=condition=ready pod \
            -l sonobuoy-plugin="${pod_label}"
    done

    os_log_info_waiter "Resources ready! Waiting for Level[${CERT_LEVEL:-}]'s plugins is completed..."
    for plugin_name in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_waiter "Waiting 'completed' condition for pod: ${plugin_name}"
        
        # Wait until sonobuoy job is completed
        timeout_checks=0
        timeout_count=100
        while true;
        do
            plugin_status=$(./sonobuoy status --json \
                | jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.status // \"\"")
            os_log_info_waiter "Plugin[${plugin_name}] with status[${plugin_status}]..."
            os_log_info_waiter "$(./sonobuoy status --json)"
            if [[ "${plugin_status}" == "complete" ]]; then
                os_log_info_waiter "Plugin[${plugin_name}] with status[${plugin_status}] is completed!"
                break
            fi
            timeout_checks=$(( timeout_checks + 1 ))
            if [[ ${timeout_checks} -eq ${timeout_count} ]]; then
                os_log_info_waiter "Timeout waiting condition 'complete' for plugin[${plugin_name}]."
                exit 1
            fi
            os_log_info_waiter "Waiting 30s for Plugin[${plugin_name}]...[${timeout_checks}/${timeout_count}]"
            sleep 30
        done
    done
    os_log_info_waiter "All the conditions has been met!"
fi

os_log_info_waiter "Done for Level[${CERT_LEVEL:-}]."
