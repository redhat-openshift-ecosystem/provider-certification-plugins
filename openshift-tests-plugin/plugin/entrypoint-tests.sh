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
declare -gr KUBE_API_URL="https://172.30.0.1:443"
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

/usr/bin/oc login "${KUBE_API_URL}" \
    --token="$(cat "${SA_TOKEN_PATH}")" \
    --certificate-authority="${SA_CA_PATH}";

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
    echo "Gathering suite list for plugin ${PLUGIN_NAME:-} (stdin is redirected to ${CTRL_SUITE_LIST}.log)"
    # shellcheck disable=SC2086
    ${CMD_OTESTS} ${OT_RUN_COMMAND:-run} ${SUITE_NAME:-${DEFAULT_SUITE_NAME-}} --dry-run -o ${CTRL_SUITE_LIST} >${CTRL_SUITE_LIST}.log
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
