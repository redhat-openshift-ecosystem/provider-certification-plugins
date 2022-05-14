#!/usr/bin/env bash

#
# openshift-tests-partner-cert runner
#

set -o pipefail
set -o nounset
# set -o errexit

os_log_info "[executor] Starting..."

os_log_info "[executor] Checking if credentials are present..."
test ! -f "${SA_CA_PATH}" || os_log_info "[executor] secret not found=${SA_CA_PATH}"
test ! -f "${SA_TOKEN_PATH}" || os_log_info "[executor] secret not found=${SA_TOKEN_PATH}"

#
# openshift login
#

os_log_info "[executor] Login to OpenShift cluster locally..."
oc login https://172.30.0.1:443 \
    --token="$(cat "${SA_TOKEN_PATH}")" \
    --certificate-authority="${SA_CA_PATH}" || true;

#
# Executor options
#
os_log_info "[executor] Executor started. Choosing execution type based on environment sets."

# To run custom tests, set the environment CERT_LEVEL on plugin definition.
# To generate the test file, use the script hack/generate-tests-tiers.sh
if [[ -n "${CERT_TEST_FILE:-}" ]]; then
    os_log_info "Running openshift-tests for custom tests [${CERT_TEST_FILE}]..."
    if [[ -s ${CERT_TEST_FILE} ]]; then
        openshift-tests run \
            --junit-dir "${RESULTS_DIR}" \
            -f "${CERT_TEST_FILE}" \
            | tee -a "${RESULTS_PIPE}" || true
        os_log_info "openshift-tests finished[$?]"
    else
        os_log_info "the file provided has no tests. Sending progress and finish executor...";
        echo "(0/0/0)" > "${RESULTS_PIPE}"

        res_file="${RESULTS_DIR}/junit_empty_e2e_$(date +%Y%m%d-%H%M%S).xml"
        os_log_info "Creating empty Junit result file [${res_file}]"
        cat << EOF > "${res_file}"
<testsuite name="openshift-tests" tests="1" skipped="0" failures="0" time="1.0"><property name="TestVersion" value="v4.1.0-4964-g555da83"></property><testcase name="[conformance] empty test list: ${CERT_TEST_FILE} has no tests to run" time="1.0"></testcase></testsuite>
EOF
    fi

# Filter by string pattern from 'all' tests
elif [[ -n "${CUSTOM_TEST_FILTER_STR:-}" ]]; then
    os_log_info "Generating a filter [${CUSTOM_TEST_FILTER_STR}]..."
    openshift-tests run --dry-run all \
        | grep "${CUSTOM_TEST_FILTER_STR}" \
        | openshift-tests run -f - \
        | tee -a "${RESULTS_PIPE}" || true

# Default execution - running default suite.
# Set E2E_SUITE on plugin manifest to change it (unset CERT_LEVEL).
else
    suite="${E2E_SUITE:-kubernetes/conformance}"
    os_log_info "Running default execution for openshift-tests suite [${suite}]..."
    #TODO: Improve the visibility when this execution fails.
    # - Save the stdout to a custom file
    # - Create a custom Junit file w/ failed test, and details about the
    #   failures. Maybe the entire b64 of stdout as failure description field.
    openshift-tests run \
        --junit-dir "${RESULTS_DIR}" \
        "${suite}" \
        | tee -a "${RESULTS_PIPE}" || true
    os_log_info "openshift-tests finished[$?]"
fi

os_log_info "Plugin executor finished. Result[$?]";
