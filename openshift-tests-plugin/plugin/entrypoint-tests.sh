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
declare -gr KUBE_API_URL="https://kubernetes.default.svc:443"
declare -gr SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"
declare -gr SA_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -gr CTRL_DONE_PLUGIN="/tmp/sonobuoy/results/done"
declare -gr CTRL_DONE_TESTS="/tmp/shared/done"
declare -gr CTRL_START_SCRIPT="/tmp/shared/start"
declare -gr CTRL_SUITE_LIST="/tmp/shared/suite.list"
declare -gr CMD_OTESTS="/usr/bin/openshift-tests"

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

# OPCT-432: Workflow entrypoint guard (defense-in-depth).
# Detect whether this plugin is inactive for the current workflow and skip
# cleanly before any cluster interaction. This guards against inactive
# manifests being loaded despite CLI-level filtering.
#
# Matrix:
#   Plugin 05 (upgrade):              run in upgrade, skip in default/disconnected
#   Plugin 10 (kube-conformance):     run in default/disconnected, skip in upgrade
#   Plugin 20 (conformance-validated): run in default/disconnected, skip in upgrade
#   Replay (80), Collector (99):      always active (no guard)
#
# Uses existing env vars: PLUGIN_NAME, RUN_MODE (set by Sonobuoy manifests).
opct_workflow_skip_plugin() {
    local reason="$1"
    echo "OPCT-432: Skipping plugin ${PLUGIN_NAME:-unknown} - ${reason}"

    # Write a JUnit skip result so Sonobuoy reports a clean skip (not failure).
    local junit_dir="/tmp/shared/junit"
    mkdir -p "${junit_dir}"
    cat > "${junit_dir}/junit_e2e_workflow_skip.xml" <<SKIPEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="opct" tests="1" failures="0" time="0.0">
  <testcase name="[opct] workflow guard: ${PLUGIN_NAME:-unknown}" time="0.0">
    <skipped message="${reason}"/>
  </testcase>
</testsuite>
SKIPEOF

    # Signal empty suite list so the plugin container does not block.
    touch "${CTRL_SUITE_LIST}"
    touch "${CTRL_SUITE_LIST}.done"

    # Signal test container completion.
    touch "${CTRL_DONE_TESTS}"

    # Wait for plugin done (Sonobuoy worker) with timeout (max 30 minutes).
    local max_wait=180
    local wait_count=0
    while [[ ${wait_count} -lt ${max_wait} ]]; do
        if [[ -f ${CTRL_DONE_PLUGIN} ]]; then
            echo "OPCT-432: Plugin done detected after skip, exiting."
            exit 0
        fi
        wait_count=$((wait_count + 1))
        if (( wait_count % 6 == 0 )); then
            echo "OPCT-432: Waiting for plugin done after skip [${CTRL_DONE_PLUGIN}] (${wait_count}/${max_wait})..."
        fi
        sleep 10
    done
    echo "OPCT-432: Timeout waiting for plugin done after skip ($((max_wait * 10))s), exiting."
    exit 1
}

# Guard: plugin 05 (upgrade) is inactive in non-upgrade workflows.
if [[ "${PLUGIN_NAME:-}" == "openshift-cluster-upgrade" ]] && [[ "${RUN_MODE:-}" != "upgrade" ]]; then
    opct_workflow_skip_plugin "upgrade plugin inactive in non-upgrade workflow (RUN_MODE=${RUN_MODE:-unset})"
fi

# Guard: plugins 10/20 (conformance) are inactive in upgrade workflows.
if [[ "${RUN_MODE:-}" == "upgrade" ]]; then
    if [[ "${PLUGIN_NAME:-}" == "openshift-kube-conformance" ]] || \
       [[ "${PLUGIN_NAME:-}" == "openshift-conformance-validated" ]]; then
        opct_workflow_skip_plugin "conformance plugin inactive in upgrade workflow (RUN_MODE=upgrade)"
    fi
fi

/usr/bin/oc login "${KUBE_API_URL}" \
    --token="$(cat "${SA_TOKEN_PATH}")" \
    --certificate-authority="${SA_CA_PATH}";

# OPCT-457: Embed CA data inline in kubeconfig to match
# CI/ci-operator behavior. oc login stores the CA as a file
# reference, but CI produces kubeconfigs with inline
# certificate-authority-data. Embedding ensures consistent
# test environments regardless of runner.
CLUSTER_NAME=$(/usr/bin/oc config view --minify -o jsonpath='{.clusters[0].name}')
if [[ -z "${CLUSTER_NAME}" ]]; then
  echo "ERROR: Failed to retrieve cluster name from kubeconfig" >&2
  exit 1
fi
/usr/bin/oc config set-cluster "${CLUSTER_NAME}" \
    --certificate-authority="${SA_CA_PATH}" \
    --embed-certs=true

# Extracting the suite list for each plugin (--dry-run).
# - openshift-tests-replay: skip
# - openshift-cluster-upgrade: gather suite list for upgrade plugin
# - openshift-kube-conformance: check if we have extracted k8s conformance tests from OTE (later 4.20 releases).
#   If yes, use the extracted tests, otherwise use the default suite.
# - other plugins: gather suite list for plugin
if [[ "${PLUGIN_NAME:-}" == "openshift-tests-replay" ]];
then
    echo "Skipping suite list for plugin ${PLUGIN_NAME:-}"
    touch ${CTRL_SUITE_LIST}

elif [[ "${PLUGIN_NAME:-}" == "openshift-cluster-upgrade" ]] && [[ "${RUN_MODE:-}" == "upgrade" ]]; then
    echo "Gathering suite list for upgrade plugin ${PLUGIN_NAME:-}"
    # shellcheck disable=SC2086
    ${CMD_OTESTS} ${OT_RUN_COMMAND:-run} ${SUITE_NAME:-${DEFAULT_SUITE_NAME-}} \
        --to-image "${UPGRADE_RELEASES-}" \
        --dry-run -o ${CTRL_SUITE_LIST}

elif [[ "${PLUGIN_NAME:-}" != "openshift-cluster-upgrade" ]]; then
    # Check if the init container reported an error
    INIT_ERROR_FILE="/tmp/shared/init-error.log"
    if [[ "${PLUGIN_NAME:-}" == "openshift-kube-conformance" ]] && [[ -f "${INIT_ERROR_FILE}" ]]; then
        INIT_ERR=$(<"${INIT_ERROR_FILE}")
        # Normalize to single line for suite list and FIFO consumers
        INIT_ERR_LINE=${INIT_ERR//$'\n'/ }
        echo "ERROR: Init container failed to extract conformance tests:"
        echo "${INIT_ERR}"
        # Escape XML special characters in error message
        INIT_ERR_XML=$(echo "${INIT_ERR}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
        # Write error as suite list entry so plugin reports it
        printf '"[opct] init-error: %s"\n' "${INIT_ERR_LINE}" > "${CTRL_SUITE_LIST}"
        touch ${CTRL_SUITE_LIST}.done
        # Create a JUnit XML so the plugin can process results without crashing
        mkdir -p /tmp/shared/junit
        cat > /tmp/shared/junit/junit_e2e_init-error.xml <<JUNITEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="openshift-kube-conformance" tests="1" failures="1" errors="0" time="0">
  <testcase name="[opct] kube-conformance init container" time="0">
    <failure message="Init container failed to extract conformance tests">${INIT_ERR_XML}</failure>
  </testcase>
</testsuite>
JUNITEOF
        # Wait for FIFO to be created by plugin, then write failed result
        for attempt in $(seq 1 30); do
            if [[ -p /tmp/shared/fifo ]]; then
                echo "FIFO ready (attempt ${attempt}), writing error result..."
                fifo_msg="failed: (0s) $(date -u +%Y-%m-%dT%H:%M:%S) \"[opct] kube-conformance init container error: ${INIT_ERR_LINE}\""
                echo "${fifo_msg}" > /tmp/shared/fifo-msg.txt
                if timeout 5s sh -c "cat /tmp/shared/fifo-msg.txt > /tmp/shared/fifo"; then
                    echo "FIFO write completed."
                else
                    echo "Warning: timed out writing init error to FIFO; continuing with JUnit-only failure reporting."
                fi
                break
            fi
            sleep 1
        done
        touch ${CTRL_DONE_TESTS}
        # Wait for plugin done with timeout (max 30 minutes)
        max_wait=180
        wait_count=0
        while [[ ${wait_count} -lt ${max_wait} ]]; do
            if [[ -f ${CTRL_DONE_PLUGIN} ]]; then
                echo "Plugin done detected, exiting."
                exit 0
            fi
            wait_count=$((wait_count + 1))
            if (( wait_count % 6 == 0 )); then
                echo "Waiting for plugin done [${CTRL_DONE_PLUGIN}] (${wait_count}/${max_wait})..."
            fi
            sleep 10
        done
        echo "Timeout waiting for plugin done after $((max_wait * 10))s, exiting."
        exit 1
    fi

    # For 10-openshift-kube-conformance plugin, check if the init container extracted
    # the conformance test list. If so, use it as the suite list for both progress
    # tracking and test execution (via -f flag).
    K8S_CONFORMANCE_LIST="/tmp/shared/k8s-conformance-tests.list"
    if [[ "${PLUGIN_NAME:-}" == "openshift-kube-conformance" ]] && [[ -f "${K8S_CONFORMANCE_LIST}" ]]; then
        TEST_COUNT=$(wc -l < "${K8S_CONFORMANCE_LIST}")
        if [[ $TEST_COUNT -gt 0 ]]; then
            echo "Using extracted Kubernetes conformance tests (${TEST_COUNT} tests)"
            cp "${K8S_CONFORMANCE_LIST}" "${CTRL_SUITE_LIST}"
            echo "Tests extracted from openshift-tests binary" > ${CTRL_SUITE_LIST}.log
        else
            echo "Warning: Extracted test list is empty, falling back to default suite"
            # shellcheck disable=SC2086
            ${CMD_OTESTS} ${OT_RUN_COMMAND:-run} ${SUITE_NAME:-${DEFAULT_SUITE_NAME-}} --dry-run -o ${CTRL_SUITE_LIST} >${CTRL_SUITE_LIST}.log
        fi
    else
        echo "Gathering suite list for plugin ${PLUGIN_NAME:-} (stdin is redirected to ${CTRL_SUITE_LIST}.log)"
        # shellcheck disable=SC2086
        ${CMD_OTESTS} ${OT_RUN_COMMAND:-run} ${SUITE_NAME:-${DEFAULT_SUITE_NAME-}} --dry-run -o ${CTRL_SUITE_LIST} >${CTRL_SUITE_LIST}.log
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

echo "#> waiting for start command"
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
echo -e "\n\n\t>> Copying e2e artifacts to collector plugin..."
{
    echo -e ">> Discoverying artifacts pod..."
    COLLECTOR_POD=$(oc get pods -n opct -l sonobuoy-plugin=99-openshift-artifacts-collector -o jsonpath='{.items[*].metadata.name}')

    suite_file="artifacts_e2e-tests_${PLUGIN_NAME-}.txt"
    echo -e ">> Copying e2e suite list metadata..."
    oc cp -c plugin "${CTRL_SUITE_LIST}" opct/"${COLLECTOR_POD}":/tmp/sonobuoy/results/"${suite_file}" || true

    echo -e ">> Preparing e2e metatada..."
    # must set the filename prefix artifacts_
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
