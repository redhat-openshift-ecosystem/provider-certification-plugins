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
