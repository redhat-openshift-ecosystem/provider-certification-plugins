#!/usr/bin/env bash

os_log_info() {
    echo "#$(caller |awk '{print$2":"$1}')> " "$@"
}
export -f os_log_info

sys_sig_handler_error(){
    os_log_info "[signal handler] ERROR on line $(caller)" >&2
}
trap sys_sig_handler_error ERR

sys_sig_handler_term() {
    os_log_info "[signal handler] TERM signal received. Caller: $(caller)"
}
trap sys_sig_handler_term TERM

create_dependencies_plugin() {
    test -d "${RESULTS_SCRIPTS}" || mkdir -p "${RESULTS_SCRIPTS}"

    os_log_info_local "Creating results pipe to progress updater..."
    test -p "${RESULTS_PIPE}" || mkfifo "${RESULTS_PIPE}"
}

init_config() {
    os_log_info_local "[init_config]"
    if [[ -z "${CERT_LEVEL:-}" ]]
    then
        os_log_info_local "Empty CERT_LEVEL. It should be defined. Exiting..."
        exit 1

    # openshift-kube-conformance (kube-conformance running w/ openshift-tests)
    elif [[ "${CERT_LEVEL:-}" == "0" ]]
    then
        CERT_TEST_FILE=""
        PLUGIN_BLOCKED_BY=()

    elif [[ "${CERT_LEVEL:-}" == "1" ]]
    then
        CERT_TEST_FILE="${CERT_TESTS_DIR}/level1.txt"
        PLUGIN_BLOCKED_BY+=("openshift-kube-conformance")

    elif [[ "${CERT_LEVEL:-}" == "2" ]]
    then
        os_log_info_local "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]" 
        CERT_TEST_FILE="${CERT_TESTS_DIR}/level2.txt"
        PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level1")

    elif [[ "${CERT_LEVEL:-}" == "3" ]]
    then
        os_log_info_local "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
        CERT_TEST_FILE="${CERT_TESTS_DIR}/level3.txt"
        PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level2")

    else
        os_log_info "[init_config] Unknow value for CERT_LEVEL=[${CERT_LEVEL:-}]"
        exit 1
    fi

    os_log_info_local "Level's specific finished. Setting discoverying total tests to run..."
    export CERT_TEST_FILE_COUNT=0
    if [[ -n "${CERT_TEST_FILE:-}" ]]; then
        CERT_TEST_FILE_COUNT="$(wc -l "${CERT_TEST_FILE}" |cut -f 1 -d' ' |tr -d '\n')"
    fi

    os_log_info_local "Setup config done"
}
export -f init_config

#
# Status scraper collects the results of Sonobuoy plugins
# The scraper will keep the status file STATUS_FILE consumed
# by different components on this container (waiter, progress reporter).
#
start_status_collector() {
    os_log_info_local "Starting sonobuoy status collector..."
    while true;
    do
        ${SONOBUOY_BIN} status --json 2>/dev/null > "${STATUS_FILE}"
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
}
export -f start_status_collector

wait_status_file() {
    while true;
    do
        os_log_info_local "Check if status file exists=[${STATUS_FILE}]"
        test -f "${STATUS_FILE}" && break
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
    os_log_info_local "Status file exists!"
}
export -f wait_status_file
