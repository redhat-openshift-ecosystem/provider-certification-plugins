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

set_config() {
    if [[ -z "${CERT_LEVEL:-}" ]]
    then
        os_log_info "Empty CERT_LEVEL. It should be defined. Exiting..."
        exit 1

    elif [[ "${CERT_LEVEL:-}" == "1" ]]
    then
        os_log_info_local "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
        export CERT_TEST_FILE="./tests/level1.txt"
        PLUGIN_BLOCKED_BY=()

    elif [[ "${CERT_LEVEL:-}" == "2" ]]
    then
        os_log_info_local "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]" 
        export CERT_TEST_FILE="./tests/level2.txt"
        PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level1")

    elif [[ "${CERT_LEVEL:-}" == "3" ]]
    then
        os_log_info_local "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
        export CERT_TEST_FILE="./tests/level3.txt"
        PLUGIN_BLOCKED_BY+=("openshift-provider-cert-level2")

    else
        os_log_info "Unknow value for CERT_LEVEL=[${CERT_LEVEL:-}]"
        exit 1
    fi
}
