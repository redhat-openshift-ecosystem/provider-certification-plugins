#!/usr/bin/env bash

#
# openshift-tests-plugin / tests
#
# Entrypoint to execute openshift-tests inside it's official container.
# This script is used as entrypoint for plugins and waits for start command.
#

set -o pipefail
set -o nounset
set -o errexit

# shellcheck disable=SC2034
declare -gr KUBECONFIG=/tmp/shared/kubeconfig;
declare -gr SHARED_DIR="/tmp/shared"
declare -gr KUBE_API_URL="https://kubernetes.default.svc:443"
declare -gr SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
declare -gr SA_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -gr CTRL_DONE_PLUGIN="/tmp/sonobuoy/results/done"
declare -gr CTRL_DONE_TESTS="/tmp/shared/done"
declare -gr CTRL_START_SCRIPT="/tmp/shared/start"
declare -gr CTRL_SUITE_LIST="/tmp/shared/suite.list"

# Detect which test binary to use based on environment variable and availability
if [[ "${USE_K8S_TESTS_EXT:-false}" == "true" ]] && [[ -x "/tmp/shared/k8s-tests-ext" ]]; then
    declare -gr CMD_TESTS="/tmp/shared/k8s-tests-ext"
    declare -gr USE_OTE_INTERFACE="true"
    echo "Using k8s-tests-ext binary with OTE interface"
else
    declare -gr CMD_TESTS="/usr/bin/openshift-tests"
    declare -gr USE_OTE_INTERFACE="false"
    echo "Using openshift-tests binary"
fi

# Legacy variable for backward compatibility
declare -gr CMD_OTESTS="${CMD_TESTS}"

echo "Starting entrypoint tests..."

sig_handler_exit() {
    echo "Done! Exiting..."
}
trap sig_handler_exit EXIT

function handle_error() {
  local error_code=$?
  local error_line=${BASH_LINENO[0]}
  local error_command=$BASH_COMMAND

  echo "Error occurred on line $error_line: $error_command (exit code: $error_code)"

  touch ${CTRL_DONE_TESTS}
}
trap handle_error ERR

/usr/bin/oc login "${KUBE_API_URL}" \
    --token="$(cat "${SA_TOKEN_PATH}")" \
    --certificate-authority="${SA_CA_PATH}";

# Function to gather test list using OTE interface (k8s-tests-ext)
function gather_test_list_ote() {
    local suite_name="${1:-}"
    local output_file="${2}"

    echo "Gathering test list using OTE interface for suite: ${suite_name}"

    # k8s-tests-ext list command outputs JSONL format
    # We need to extract test names and convert to the expected format
    ${CMD_TESTS} list -o jsonl > "${output_file}.jsonl" 2>"${output_file}.log"

    # Convert JSONL to simple test name list (one per line)
    # Each line in JSONL is: {"name":"test-name","labels":{...},"suite":"..."}
    if command -v jq &> /dev/null; then
        jq -r '.name' "${output_file}.jsonl" > "${output_file}"
    else
        # Fallback if jq is not available - use python
        python3 -c "
import json, sys
with open('${output_file}.jsonl') as f:
    for line in f:
        if line.strip():
            data = json.loads(line)
            print(data.get('name', ''))
" > "${output_file}"
    fi

    echo "Extracted $(wc -l < "${output_file}") tests from OTE interface"
}

# Function to gather test list using standard openshift-tests interface
function gather_test_list_standard() {
    local run_command="${1:-run}"
    local suite_name="${2:-}"
    local additional_args="${3:-}"
    local output_file="${4}"

    echo "Gathering test list using openshift-tests for suite: ${suite_name}"

    # shellcheck disable=SC2086
    ${CMD_TESTS} ${run_command} ${suite_name} ${additional_args} --dry-run -o "${output_file}" >"${output_file}.log" 2>&1
}

if [[ "${PLUGIN_NAME:-}" == "openshift-tests-replay" ]];
then
    echo "Skipping suite list for plugin ${PLUGIN_NAME:-}"
    touch ${CTRL_SUITE_LIST}

elif [[ "${PLUGIN_NAME:-}" == "openshift-cluster-upgrade" ]] && [[ "${RUN_MODE:-}" == "upgrade" ]]; then
    if [[ "${USE_OTE_INTERFACE}" == "true" ]]; then
        echo "WARNING: k8s-tests-ext not supported for upgrade plugin, falling back to openshift-tests"
        gather_test_list_standard "${OT_RUN_COMMAND:-run}" "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "--to-image ${UPGRADE_RELEASES-}" "${CTRL_SUITE_LIST}"
    else
        echo "Gathering suite list for upgrade plugin ${PLUGIN_NAME:-}"
        gather_test_list_standard "${OT_RUN_COMMAND:-run}" "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "--to-image ${UPGRADE_RELEASES-}" "${CTRL_SUITE_LIST}"
    fi

elif [[ "${PLUGIN_NAME:-}" != "openshift-cluster-upgrade" ]]; then
    if [[ "${USE_OTE_INTERFACE}" == "true" ]]; then
        gather_test_list_ote "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "${CTRL_SUITE_LIST}"
    else
        gather_test_list_standard "${OT_RUN_COMMAND:-run}" "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "" "${CTRL_SUITE_LIST}"
    fi
else
    echo "Skipping suite list for plugin ${PLUGIN_NAME:-}"
    touch ${CTRL_SUITE_LIST}
fi
echo "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" > /tmp/shared/suite.name
touch ${CTRL_SUITE_LIST}.done

echo "#> setting up cloud provider..."
chmod u+x /tmp/shared/platform.sh
/tmp/shared/platform.sh

# Function to execute tests using OTE interface (k8s-tests-ext)
function execute_tests_ote() {
    # shellcheck disable=SC2034
    local test_list="${CTRL_SUITE_LIST}"
    local junit_dir="/tmp/shared/junit"

    echo "Executing tests using OTE interface..."
    mkdir -p "${junit_dir}"

    # Set up environment variables required by k8s-tests-ext
    export TEST_PROVIDER="{\"ProviderName\":\"skeleton\"}"
    export EXTENSION_ARTIFACT_DIR="/tmp/shared/artifacts"
    mkdir -p "${EXTENSION_ARTIFACT_DIR}"

    # Create a simple wrapper script that will be the "start" script
    # This maintains compatibility with the plugin orchestration
    cat > "${CTRL_START_SCRIPT}" <<'EOF_START'
#!/bin/bash
set -euo pipefail

echo "Executing k8s-tests-ext conformance tests..."

junit_dir="/tmp/shared/junit"
test_list="/tmp/shared/suite.list"
cmd_tests="/tmp/shared/k8s-tests-ext"

# Create JUnit XML header
junit_file="${junit_dir}/junit_runner.xml"
test_count=$(wc -l < "${test_list}")
pass_count=0
fail_count=0
skip_count=0

echo '<?xml version="1.0" encoding="UTF-8"?>' > "${junit_file}"
echo '<testsuites>' >> "${junit_file}"
echo "  <testsuite name=\"kubernetes-conformance\" tests=\"${test_count}\">" >> "${junit_file}"

# Read tests from list and execute each one
while IFS= read -r test_name || [ -n "$test_name" ]; do
    if [ -z "$test_name" ]; then
        continue
    fi

    echo "Running test: ${test_name}"

    # Run single test using OTE interface
    result_json=$(mktemp)
    if "${cmd_tests}" run-test -n "${test_name}" -o jsonl > "${result_json}" 2>&1; then
        # Parse result from JSONL
        test_result=$(python3 -c "
import json, sys
try:
    with open('${result_json}') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                print(data.get('result', 'unknown'))
                break
except Exception as e:
    print('unknown', file=sys.stderr)
" 2>/dev/null || echo "unknown")

        case "${test_result}" in
            passed)
                echo "  <testcase name=\"${test_name}\" classname=\"kubernetes.conformance\" status=\"passed\"/>" >> "${junit_file}"
                ((pass_count++))
                ;;
            skipped)
                echo "  <testcase name=\"${test_name}\" classname=\"kubernetes.conformance\" status=\"skipped\"><skipped/></testcase>" >> "${junit_file}"
                ((skip_count++))
                ;;
            *)
                echo "  <testcase name=\"${test_name}\" classname=\"kubernetes.conformance\" status=\"failed\"><failure>Test failed or result unknown</failure></testcase>" >> "${junit_file}"
                ((fail_count++))
                ;;
        esac
    else
        echo "  <testcase name=\"${test_name}\" classname=\"kubernetes.conformance\" status=\"failed\"><failure>Test execution failed</failure></testcase>" >> "${junit_file}"
        ((fail_count++))
    fi

    rm -f "${result_json}"
done < "${test_list}"

# Close JUnit XML
echo "  </testsuite>" >> "${junit_file}"
echo "</testsuites>" >> "${junit_file}"

echo "Test execution complete: ${pass_count} passed, ${fail_count} failed, ${skip_count} skipped out of ${test_count} total"
EOF_START

    chmod +x "${CTRL_START_SCRIPT}"
    echo "Created OTE start script at ${CTRL_START_SCRIPT}"

    # Execute the start script
    ${CTRL_START_SCRIPT}
}

echo "#> waiting for start command"
if [[ "${USE_OTE_INTERFACE}" == "true" ]]; then
    echo "Using OTE interface - generating and executing k8s-tests-ext start script"
    execute_tests_ote
else
    # Standard flow: wait for plugin Go code to generate start script
    # TODO implement a timeout
    msg="waiting for start command [${CTRL_START_SCRIPT}]. Read the container 'plugin' logs for more information."
    while true;
    do
        if [[ -f ${CTRL_START_SCRIPT} ]];
        then
            chmod u+x $CTRL_START_SCRIPT && cat $CTRL_START_SCRIPT && $CTRL_START_SCRIPT;
            break;
        fi
        echo "$(date) ${msg}";
        sleep 10;
    done
fi
echo -e "\n\n\t>> Copying e2e artifacts to collector plugin..."
{
    echo -e ">> Discoverying artifacts pod..."
    COLLECTOR_POD=$(oc get pods -n opct -l sonobuoy-plugin=99-openshift-artifacts-collector -o jsonpath='{.items[*].metadata.name}')

    suite_file="artifacts_e2e-tests_${PLUGIN_NAME-}.txt"
    echo -e ">> Copying e2e suite list metadata..."
    oc cp -c plugin "${CTRL_SUITE_LIST}" opct/"${COLLECTOR_POD}":/tmp/sonobuoy/results/"${suite_file}" || true

    echo -e ">> Preparing e2e metatada..."
    # must prefix with artifacts_
    e2e_artifact_name="artifacts_e2e-metadata-${PLUGIN_NAME:-}.tar.gz"
    e2e_artifact="/tmp/${e2e_artifact_name}"
    tar cfzv "${e2e_artifact}"  /tmp/shared/junit/* || true

    echo -e ">> Copying e2e metadata ${e2e_artifact_name}..."
    oc cp -c plugin "${e2e_artifact}" opct/"${COLLECTOR_POD}":/tmp/sonobuoy/results/"${e2e_artifact_name}" || true

} || true
touch ${CTRL_DONE_TESTS}

# wait for plugin done
# TODO implement a timeout
msg="waiting for plugin done [${CTRL_DONE_PLUGIN}]. For more information, read the container 'plugin' logs."
while true;
do
    if [[ -f ${CTRL_DONE_PLUGIN} ]];
    then
        echo "Plugin done detected, exiting.";
        exit 0;
    fi
    echo "$(date) ${msg}";
    sleep 10;
done
