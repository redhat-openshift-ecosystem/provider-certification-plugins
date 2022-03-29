#!/usr/bin/env sh

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
# set -o errexit

source $(dirname $0)/shared.sh

os_log_info "Starting plugin..." |tee -a ${results_script_dir}/runner.log

# Notify sonobuoy worker with e2e results (junit)
# https://github.com/vmware-tanzu/sonobuoy/blob/main/site/content/docs/main/plugins.md#plugin-result-types
save_results() {
    os_log_info "Saving results."

    # TODO: check how to collect plugin's stdout to artifacts.
    # Sonobuoy does not save any file outside of a valid result schema.
    # The worker will fail if invalid files will be send to 'done' file.
    #cat << EOF >> ${results_script_dir}/runner.log
##> Result files:
#$(ls ${results_script_dir})
#EOF
    #tar cfz ${results_script_dir}.tgz ${results_script_dir}

    pushd ${results_dir};

    # JUnit
    JUNIT_OUTPUT=$(ls junit*.xml || true);

    # Create empty junit result file to avoid failures on report.
    # It happens when tests file is empty. (when? development!)
    # TODO(pre-release): review that strategy
    if [[ -z "${JUNIT_OUTPUT}" ]]; then
        cat << EOF > junit_e2e_$(date +%Y%m%d-%H%M%S).xml
<testsuite name="openshift-tests" tests="0" skipped="0" failures="0" time="1"><property name="TestVersion" value="v4.1.0-4964-g555da83"></property></testsuite>
EOF
        JUNIT_OUTPUT=$(ls junit*.xml);
    fi
    chmod 644 ${JUNIT_OUTPUT};
    echo '/tmp/sonobuoy/results/'${JUNIT_OUTPUT} > ${results_dir}/done

    # tarball
    # https://github.com/vmware-tanzu/sonobuoy-plugins/blob/main/examples/cmd-runner/run.sh#L13
    #tar czf results.tar.gz *
    #printf ${results_dir}/results.tar.gz > ${results_dir}/done

    popd;
    os_log_info "Results saved at ${results_dir}/done=[/tmp/sonobuoy/results/${JUNIT_OUTPUT}]";
}
trap save_results EXIT

# TODO(waiter): add a wait flow to lock execution and avoid cert suites running in parallel.
# https://github.com/mtulio/openshift-provider-certification/issues/2

$(dirname $0)/executor.sh | tee -a ${results_script_dir}/executor.log

# TODO(waiter): add a post processor of JUnit to identify flakes
# https://github.com/mtulio/openshift-provider-certification/issues/14

os_log_info "Plugin runner have finished. Result[$?]";
