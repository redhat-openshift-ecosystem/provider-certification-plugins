#!/usr/bin/env sh

os_log_info() {
    echo "#$(caller |awk '{print$2":"$1}')> " $@
}
export -f os_log_info

sys_trap_error(){
    os_log_info "ERROR on line $(caller)" >&2
}
trap sys_trap_error ERR

export results_dir="${RESULTS_DIR:-/tmp/sonobuoy/results}"
export results_pipe="${results_dir}/status_pipe"

export results_script_dir="${results_dir}/plugin-scripts"
test -d ${results_script_dir} || mkdir -p ${results_script_dir}
