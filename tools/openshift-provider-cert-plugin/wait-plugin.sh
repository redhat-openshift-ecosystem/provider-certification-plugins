#!/usr/bin/env bash

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info_local() {
    os_log_info "$(date +%Y%m%d-%H%M%S)> [waiter] $*"
}

os_log_info_waiter "Starting Level[${CERT_LEVEL:-}]..."
set_config

os_log_info_local "Checking if there's plugins blocking Level${CERT_LEVEL:-} execution..."
if [[ ${#PLUGIN_BLOCKED_BY[@]} -ge 1 ]]; then
    os_log_info_local "Level${CERT_LEVEL:-} plugin is blocked by: [${PLUGIN_BLOCKED_BY[*]}]"
    for pod_label in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_waiter "Waiting running pod-label: ${pod_label}"
        kubectl wait \
            --timeout=10m \
            --for=condition=ready pod \
            -l sonobuoy-plugin="${pod_label}"
    done

    os_log_info_local "Resources ready! Waiting for Level[${CERT_LEVEL:-}]'s plugins is completed..."
    for plugin_name in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_local "Waiting 'completed' condition for pod: ${plugin_name}"
        
        # Wait until sonobuoy job is completed
        timeout_checks=0
        timeout_count=100
        while true;
        do
            plugin_status=$(./sonobuoy status --json \
                | jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.status // \"\"")
            os_log_info_local "Plugin[${plugin_name}] with status[${plugin_status}]..."
            os_log_info_local "$(./sonobuoy status --json)"
            if [[ "${plugin_status}" == "complete" ]]; then
                os_log_info_local "Plugin[${plugin_name}] with status[${plugin_status}] is completed!"
                break
            fi
            timeout_checks=$(( timeout_checks + 1 ))
            if [[ ${timeout_checks} -eq ${timeout_count} ]]; then
                os_log_info_local "Timeout waiting condition 'complete' for plugin[${plugin_name}]."
                exit 1
            fi
            os_log_info_local "Waiting 30s for Plugin[${plugin_name}]...[${timeout_checks}/${timeout_count}]"
            sleep 30
        done
    done
    os_log_info_local "All the conditions has been met!"
fi

os_log_info_local "Done for Level[${CERT_LEVEL:-}]."
