#!/usr/bin/env bash

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info_local() {
    os_log_info "$(date +%Y%m%d-%H%M%S)> [waiter] $*"
}

os_log_info_local "Starting Level[${CERT_LEVEL:-}]..."
init_config

os_log_info_local "Checking if there's plugins blocking Level${CERT_LEVEL:-} execution..."
if [[ ${#PLUGIN_BLOCKED_BY[@]} -ge 1 ]]; then
    os_log_info_local "Level${CERT_LEVEL:-} plugin is blocked by: [${PLUGIN_BLOCKED_BY[*]}]"
    for pod_label in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_local "Waiting for pod running with label: ${pod_label}"
        kubectl wait \
            --timeout=10m \
            --for=condition=ready pod \
            -l sonobuoy-plugin="${pod_label}"
    done

    os_log_info_local "Resource(s) ready! Waiting for Level[${CERT_LEVEL:-}]'s plugins be completed..."
    for plugin_name in "${PLUGIN_BLOCKED_BY[@]}"; do
        os_log_info_local "Waiting 'completed' condition for pod: ${plugin_name}"
        
        # Wait until sonobuoy job is completed
        timeout_checks=0
        timeout_count=100
        last_count=0
        while true;
        do
            plugin_status=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.status // \"\"" "${STATUS_FILE}")

            os_log_info_local "Plugin[${plugin_name}] with status[${plugin_status}]..."
            os_log_info_local "$(cat "${STATUS_FILE}")"
            if [[ "${plugin_status}" == "complete" ]]; then
                os_log_info_local "Plugin[${plugin_name}] with status[${plugin_status}] is completed!"
                break
            fi

            # Timeout checker
            ## 1. Dont block by long running plugins (only non-updated)
            ## Timeout checks will increase only when previous jobs got stuck,
            ## otherwise it will be reset. It can avoid the plugin run infinitely,
            ## also avoid to set low timeouts for 'unknown' exec time on dependencies.
            count=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.progress.completed // 0" "${STATUS_FILE}")
            if [[ ${count} -gt ${last_count} ]]; then
                timeout_checks=0
                sleep 10
                continue
            fi
            ## 2. Dont get stuck for blocked plugins (which is already waiting for deps)
            blocker_msg=$(jq -r ".plugins[] | select (.plugin == \"${plugin_name}\" ) |.progress.msg // \"\"" "${STATUS_FILE}")
            if [[ "${blocker_msg}" =~ "status=blocked-by" ]]; then
                timeout_checks=0
                sleep 10
                continue
            elif [[ "${blocker_msg}" =~ "status=waiting-for" ]]; then
                timeout_checks=0
                sleep 10
                continue
            fi
            last_count=${count}
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
