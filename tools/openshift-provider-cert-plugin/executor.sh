#!/bin/sh

#
# openshift-tests-partner-cert runner
#

#set -x
set -o pipefail
set -o nounset
# set -o errexit

os_log_info "[executor] Starting..."

export KUBECONFIG=/tmp/kubeconfig

suite="${E2E_SUITE:-kubernetes/conformance}"
ca_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
sa_token="/var/run/secrets/kubernetes.io/serviceaccount/token"

os_log_info "[executor] Checking credentials are present..."
test ! -f "${ca_path}" || os_log_info "[executor] file not found=${ca_path}"
test ! -f "${sa_token}" || os_log_info "[executor] file not found=${sa_token}"

#
# openshift login
#

os_log_info "[executor] Login to OpenShift cluster locally..."
oc login https://172.30.0.1:443 \
    --token=$(cat ${sa_token}) \
    --certificate-authority=${ca_path} || true;

#
# Executor options
#
os_log_info "[executor] Executor started. Choosing execution type based on environment sets."

# To run custom tests, set the environment CUSTOM_TEST_FILE on plugin definition.
# To generate the test file, use the parse-test.py.
if [[ ! -z ${CERT_TEST_FILE:-} ]]; then
    os_log_info "Running openshift-tests for custom tests [${CERT_TEST_FILE}]..."
    if [[ -s ${CERT_TEST_FILE} ]]; then
        openshift-tests run \
            --junit-dir ${results_dir} \
            -f ${CERT_TEST_FILE} \
            | tee ${results_pipe} || true
        os_log_info "openshift-tests finished"
    else
        os_log_info "the file provided has no tests. Sending progress and finish executor...";
        echo "(0/0/0)" > ${results_pipe}
    fi

# reusing script to parser jobs.
# ToDo: keep more simple in basic filters. Example:
# $ openshift-tests run --dry-run all |grep '\[sig-storage\]' |openshift-tests run -f -
elif [[ ! -z ${CUSTOM_TEST_FILTER_SIG:-} ]]; then
    os_log_info "Generating tests for SIG [${CUSTOM_TEST_FILTER_SIG}]..."
    mkdir tmp/
    ./parse-tests.py \
        --filter-suites all \
        --filter-key sig \
        --filter-value "${CUSTOM_TEST_FILTER_SIG}"

    os_log_info "#executor>Running"
    openshift-tests run \
        --junit-dir ${results_dir} \
        -f ./tmp/openshift-e2e-suites.txt \
        | tee ${results_pipe}

# Filter by string pattern from 'all' tests
elif [[ ! -z ${CUSTOM_TEST_FILTER_STR:-} ]]; then
    os_log_info "#executor>Generating a filter [${CUSTOM_TEST_FILTER_STR}]..."
    openshift-tests run --dry-run all \
        | grep "${CUSTOM_TEST_FILTER_STR}" \
        | openshift-tests run -f - \
        | tee ${results_pipe}

# Default execution - running default suite
else
    os_log_info "#executor>Running default execution for openshift-tests suite [${suite}]..."
    openshift-tests run \
        --junit-dir ${results_dir} \
        ${suite} \
        | tee ${results_pipe}
fi

os_log_info "Plugin executor finished. Result[$?]";
