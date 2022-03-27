#!/bin/sh

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
set -o errexit

source $(dirname $0)/shared.sh

export KUBECONFIG=/tmp/kubeconfig

suite="${E2E_SUITE:-kubernetes/conformance}"
ca_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
sa_token="/var/run/secrets/kubernetes.io/serviceaccount/token"

mkfifo ${results_pipe}

echo "#executor> Starting plugin runner..."
#
# feedback worker
#
save_results() {
    echo "#executor> Saving results."
     cat << EOF >>${results_script_dir}/executor.log
#executor> Saving results.
##> openshift-tests version:

##> show files in ${results_dir}:
$(ls ${results_dir}/)
EOF
    #echo "${results_dir}/runner.txt" > ${results_dir}/done
}
trap save_results EXIT

#
# login
#
oc login https://172.30.0.1:443 \
    --token=$(cat ${sa_token}) \
    --certificate-authority=${ca_path};

PUBLIC_API_URL=$(oc get infrastructure cluster -o=jsonpath='{.status.apiServerURL}');
oc login ${PUBLIC_API_URL} \
    --token=$(cat ${sa_token}) \
    --certificate-authority=${ca_path};

#
# runner
#

# To run custom tests, set the environment CUSTOM_TEST_FILE on plugin definition.
# To generate the test file, use the parse-test.py.
if [[ ! -z ${CUSTOM_TEST_FILE:-} ]]; then
    echo "#executor> Running openshift-tests for custom tests [${CUSTOM_TEST_FILE}]..."
    if [[ -s ${CUSTOM_TEST_FILE} ]]; then
        openshift-tests run \
            --junit-dir ${results_dir} \
            -f ${CUSTOM_TEST_FILE} \
            | tee ${results_pipe}
    else
        echo "#executor> the file provided has no tests. Sending progress and finish executor...";
        echo "(0/0/0)" > ${results_pipe}
    fi
# reusing script to parser jobs.
# ToDo: keep more simple in basic filters. Example:
# $ openshift-tests run --dry-run all |grep '\[sig-storage\]' |openshift-tests run -f -
elif [[ ! -z ${CUSTOM_TEST_FILTER_SIG:-} ]]; then
    echo "#executor>Generating tests for SIG [${CUSTOM_TEST_FILTER_SIG}]..."
    mkdir tmp/
    ./parse-tests.py \
        --filter-suites all \
        --filter-key sig \
        --filter-value "${CUSTOM_TEST_FILTER_SIG}"

    echo "#executor>Running"
    openshift-tests run \
        --junit-dir ${results_dir} \
        -f ./tmp/openshift-e2e-suites.txt \
        | tee ${results_pipe}

# Filter by string pattern from 'all' tests
elif [[ ! -z ${CUSTOM_TEST_FILTER_STR:-} ]]; then
    echo "#executor>Generating a filter [${CUSTOM_TEST_FILTER_STR}]..."
    openshift-tests run --dry-run all \
        | grep "${CUSTOM_TEST_FILTER_STR}" \
        | openshift-tests run -f - \
        | tee ${results_pipe}

# Default execution - running default suite
else
    echo "#executor>Running openshift-tests for suite [${suite}]..."
    openshift-tests run \
        --junit-dir ${results_dir} \
        ${suite} \
        | tee ${results_pipe}
fi

sleep 5
echo "#executor>#> Plugin runner finished. Result[$?]";
