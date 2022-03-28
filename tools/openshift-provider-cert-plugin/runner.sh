#!/usr/bin/env sh

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
# set -o errexit

source $(dirname $0)/shared.sh

os_log_info "Starting plugin..." |tee -a ${results_script_dir}/runner.log

save_results() {
    os_log_info "Saving results."
     cat << EOF >> ${results_script_dir}/runner.log
##> Result files:
$(ls ${results_script_dir})
EOF
    tar cfz ${results_script_dir}.tgz ${results_script_dir}
    echo "${results_script_dir}.tgz" |tee ${results_dir}/done
}
trap save_results EXIT

$(dirname $0)/run.sh | tee -a ${results_script_dir}/executor.log

os_log_info "Plugin runner have finished. Result[$?]";
