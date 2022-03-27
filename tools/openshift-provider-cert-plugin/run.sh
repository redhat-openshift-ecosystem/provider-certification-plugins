#!/bin/sh

#
# openshift-tests-partner-cert runner
#

export KUBECONFIG=/tmp/kubeconfig

suite="${E2E_SUITE:-kubernetes/conformance}"
results_dir="${RESULTS_DIR:-/tmp/sonobuoy/results}"
results_pipe="${results_dir}/status_pipe"

ca_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
sa_token="/var/run/secrets/kubernetes.io/serviceaccount/token"

mkfifo ${results_pipe}

#
# feedback worker
#
saveResults() {

     cat << EOF >${results_dir}/runner.txt
##> openshift-tests version:

##> junit files in ${results_dir}:
$(ls ${results_dir}/junit*.xml)
EOF
    echo "${results_dir}/runner.txt" > ${results_dir}/done
}
trap saveResults EXIT

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
    echo "Running openshift-tests for custom tests [${CUSTOM_TEST_FILE}]..."
    openshift-tests run \
        --junit-dir ${results_dir} \
        -f ./tests/${CUSTOM_TEST_FILE} \
        | tee ${results_pipe}

# reusing script to parser jobs.
# ToDo: keep more simple in basic filters. Example:
# $ openshift-tests run --dry-run all |grep '\[sig-storage\]' |openshift-tests run -f -
elif [[ ! -z ${CUSTOM_TEST_FILTER_SIG:-} ]]; then
    echo "Generating tests for SIG [${CUSTOM_TEST_FILTER_SIG}]..."
    mkdir tmp/
    ./parse-tests.py \
        --filter-suites all \
        --filter-key sig \
        --filter-value "${CUSTOM_TEST_FILTER_SIG}"

    echo "Running"
    openshift-tests run \
        --junit-dir ${results_dir} \
        -f ./tmp/openshift-e2e-suites.txt \
        | tee ${results_pipe}

# Filter by string pattern from 'all' tests
elif [[ ! -z ${CUSTOM_TEST_FILTER_STR:-} ]]; then
    echo "Generating a filter [${CUSTOM_TEST_FILE}]..."
    openshift-tests run --dry-run all \
        | grep "${CUSTOM_TEST_FILTER_STR}" \
        | openshift-tests run -f - \
        | tee ${results_pipe}

# Default execution - running default suite
else
    echo "Running openshift-tests for suite [${suite}]..."
    openshift-tests run \
        --junit-dir ${results_dir} \
        ${suite} \
        | tee ${results_pipe}
fi

echo "Execution finished. Result[$?]";
