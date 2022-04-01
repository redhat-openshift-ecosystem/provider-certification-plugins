#!/usr/bin/env sh

os_log_info() {
    echo "#$(caller |awk '{print$2":"$1}')> " $@
}
export -f os_log_info

sys_sig_error_handler(){
    os_log_info "[signal handler] ERROR on line $(caller)" >&2
}
trap sys_sig_error_handler ERR

sys_sig_term_handler() {
    os_log_info "[signal handler] TERM signal received. Caller: $(caller)"
}
trap sys_sig_term_handler TERM

export results_dir="${RESULTS_DIR:-/tmp/sonobuoy/results}"
export results_pipe="${results_dir}/status_pipe"

export results_script_dir="${results_dir}/plugin-scripts"
test -d ${results_script_dir} || mkdir -p ${results_script_dir}

declare -g PLUGIN_BLOCKED_BY
declare -g CERT_TEST_FILE
export CERT_TEST_FILE=""
export PLUGIN_BLOCKED_BY=()

if [[ -z "${CERT_LEVEL:-}" ]]
then
    os_log_info "Empty CERT_LEVEL. It should be defined. Exiting..."
    exit 1
# Level1 blocks Level2 (...)
elif [[ "${CERT_LEVEL:-}" == "1" ]]
then
    os_log_info "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
    CERT_TEST_FILE="./tests/level1.txt"

elif [[ "${CERT_LEVEL:-}" == "2" ]]
then
    os_log_info "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
    CERT_TEST_FILE="./tests/level2.txt"

elif [[ "${CERT_LEVEL:-}" == "3" ]]
then
    os_log_info "Setting config for CERT_LEVEL=[${CERT_LEVEL:-}]"
    CERT_TEST_FILE="./tests/level3.txt"

else
    os_log_info "Unknow value for CERT_LEVEL=[${CERT_LEVEL:-}]"
    exit 1
fi
