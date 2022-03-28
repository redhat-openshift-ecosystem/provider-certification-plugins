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

    # Sonobuoy Worker result:
    # https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types

    pushd ${results_dir};
    #1 Temp result report
    JUNIT_OUTPUT=$(ls junit*.xml || true);
    test -z "${JUNIT_OUTPUT}" || chmod 644 ${JUNIT_OUTPUT};
    echo '/tmp/sonobuoy/results/'${JUNIT_OUTPUT} > ${results_dir}/done

    #2 prepares the results for handoff to the Sonobuoy worker.
    # https://github.com/vmware-tanzu/sonobuoy-plugins/blob/main/examples/cmd-runner/run.sh#L13
    #tar czf results.tar.gz *
    #printf ${results_dir}/results.tar.gz > ${results_dir}/done

    popd;
    os_log_info "Results saved at ${results_dir}/done=[/tmp/sonobuoy/results/${JUNIT_OUTPUT}]";
}
trap save_results EXIT

$(dirname $0)/run.sh | tee -a ${results_script_dir}/executor.log

os_log_info "Plugin runner have finished. Result[$?]";
