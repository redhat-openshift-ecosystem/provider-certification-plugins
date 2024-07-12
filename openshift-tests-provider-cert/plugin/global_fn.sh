#!/usr/bin/env bash

# Shared functions used across services

# os_log_info logger function, printing the current bash script
# and line as prefix.
os_log_info() {
    caller_src=$(caller | awk '{print$2}')
    caller_name="$(basename -s .sh "$caller_src"):$(caller | awk '{print$1}')"
    echo "$(date --iso-8601=seconds) | [${SERVICE_NAME}] | $caller_name> " "$@"
}
export -f os_log_info

# sys_sig_handler_error handles the ERR sigspec.
sys_sig_handler_error(){
    os_log_info "[signal handler] ERROR on line $(caller)" >&2
}
trap sys_sig_handler_error ERR

# sys_sig_handler_term handles the TERM(15) sigspec.
sys_sig_handler_term() {
    os_log_info "[signal handler] TERM signal received. Caller: $(caller)"
}
trap sys_sig_handler_term TERM

# create_dependencies_plugin creates any initial dependency to run the plugin.
create_dependencies_plugin() {
    test -d "${SHARED_DIR}" || mkdir -p "${SHARED_DIR}"
    test -d "${RESULTS_SCRIPTS}" || mkdir -p "${RESULTS_SCRIPTS}"

    os_log_info "Creating results pipe to progress updater..."
    test -p "${RESULTS_PIPE}" || mkfifo "${RESULTS_PIPE}"
}

# init_config initializes the configuration based on variables sent
# to the pod. The plugin can assume different executions based on
# the intiial values defined on the variables PLUGIN_NAME, CERT_TEST_SUITE,
# and PLUGIN_BLOCKED_BY.
init_config() {
    os_log_info "[init_config] starting..."

    # Forcing to use newer CLI after plugin renaming
    if [[ -n "${CERT_LEVEL:-}" ]]
    then
        err="[init_config] Detected deprecated env var CERT_LEVEL. It can be caused by wrong CLI version. Please update the openshift-provider-cert binary and try again [CERT_LEVEL=${CERT_LEVEL:-}]"
        create_junit_with_msg "failed" "[opct] ${err}"
        os_log_info "${err}. Exiting..."
        exit 1
    fi

    if [[ -z "${PLUGIN_ID:-}" ]]
    then
        err="[init_config] Empty PLUGIN_ID[${PLUGIN_ID}]. PLUGIN_ID must be defined by Plugin manifest as env var"
        create_junit_with_msg "failed" "[opct] ${err}"
        os_log_info "${err}. Exiting..."
        exit 1
    fi

    os_log_info "Setting config for PLUGIN_ID=[${PLUGIN_ID:-}]..."
    if [[ "${PLUGIN_ID:-}" == "${PLUGIN_ID_OPENSHIFT_UPGRADE}" ]]
    then
        PLUGIN_NAME="${PLUGIN_NAME_OPENSHIFT_UPGRADE}"
        PLUGIN_BLOCKED_BY=()

    elif [[ "${PLUGIN_ID:-}" == "${PLUGIN_ID_KUBE_CONFORMANCE}" ]]
    then
        PLUGIN_NAME="${PLUGIN_NAME_KUBE_CONFORMANCE}"
        CERT_TEST_SUITE="${OPENSHIFT_TESTS_SUITE_KUBE_CONFORMANCE}"
        PLUGIN_BLOCKED_BY=("${PLUGIN_NAME_OPENSHIFT_UPGRADE}")

    elif [[ "${PLUGIN_ID:-}" == "${PLUGIN_ID_OPENSHIFT_CONFORMANCE}" ]]
    then
        PLUGIN_NAME="${PLUGIN_NAME_OPENSHIFT_CONFORMANCE}"
        CERT_TEST_SUITE="${OPENSHIFT_TESTS_SUITE_OPENSHIFT_CONFORMANCE}"
        PLUGIN_BLOCKED_BY+=("${PLUGIN_NAME_KUBE_CONFORMANCE}")

    elif [[ "${PLUGIN_ID:-}" == "${PLUGIN_ID_TESTS_REPLAY}" ]]
    then
        PLUGIN_NAME="${PLUGIN_NAME_TESTS_REPLAY}"
        CERT_TEST_SUITE="${OPENSHIFT_TESTS_SUITE_TESTS_REPLAY}"
        PLUGIN_BLOCKED_BY+=("${PLUGIN_NAME_OPENSHIFT_CONFORMANCE}")
        export CERT_TEST_COUNT_OVERRIDE=0

    elif [[ "${PLUGIN_ID:-}" == "${PLUGIN_ID_OPENSHIFT_ARTIFACTS_COLLECTOR}" ]]
    then
        PLUGIN_NAME="${PLUGIN_NAME_OPENSHIFT_ARTIFACTS_COLLECTOR}"
        PLUGIN_BLOCKED_BY+=("${PLUGIN_NAME_TESTS_REPLAY}")

    else
        err="[init_config] Unknown value for PLUGIN_ID=[${PLUGIN_ID:-}]"
        create_junit_with_msg "failed" "[opct] ${err}"
        os_log_info "${err}. Exiting..."
        exit 1
    fi

    os_log_info "Plugin Config: PLUGIN_NAME=[${PLUGIN_NAME:-}] PLUGIN_BLOCKED_BY=[${PLUGIN_BLOCKED_BY[*]}] CERT_TEST_FILE=[${CERT_TEST_FILE}]"


    os_log_info "Setup config done."
}
export -f init_config

# show_config dump current configuration to stdout/logs, which will be collected
# on the tarball by aggregator.
show_config() {
    cat <<-EOF
#> Config Dump [start] <#
PLUGIN_NAME=${PLUGIN_NAME}
PLUGIN_BLOCKED_BY=${PLUGIN_BLOCKED_BY[*]}
PLUGIN_ID=${PLUGIN_ID}
CERT_LEVEL=${CERT_LEVEL:-''}
RUN_MODE=${RUN_MODE:-''}
UPGRADE_RELEASES=${UPGRADE_RELEASES-}
CERT_TEST_SUITE=${CERT_TEST_SUITE}
CERT_TEST_COUNT=${CERT_TEST_COUNT}
CERT_TEST_PARALLEL=${CERT_TEST_PARALLEL}
RESULTS_DIR=${RESULTS_DIR}
ENV_NODE_NAME=${ENV_NODE_NAME:-}
ENV_POD_NAME=${ENV_POD_NAME:-}
ENV_POD_NAMESPACE=${ENV_POD_NAMESPACE:-}
DEV_MODE_COUNT=${DEV_MODE_COUNT:-}
#> Config Dump [end] <#
#> Version INFO [start] <#
$(cat VERSION || true)
#> Version INFO [end]   <#
EOF
}

# update_config perform updates on configuration/environment variables
# not covered by init_config.
update_config() {
    os_log_info "[update_config] Getting the total tests to run"
    if [[ -n "${CERT_TEST_FILE:-}" ]]; then
        CERT_TEST_COUNT="$(wc -l "${CERT_TEST_FILE}" |cut -f 1 -d' ' |tr -d '\n')"
    fi
    if [[ "${CERT_TEST_SUITE:-}" != "" ]]
    then
        CERT_TEST_COUNT="$(${UTIL_OTESTS_BIN} run --dry-run "${CERT_TEST_SUITE}" | wc -l)"
    fi
    # Counter override
    if [[ -n "${CERT_TEST_COUNT_OVERRIDE-}" ]]; then
        os_log_info "[update_config] Overriding test count from [${CERT_TEST_COUNT}] to [${CERT_TEST_COUNT_OVERRIDE}]"
        CERT_TEST_COUNT=${CERT_TEST_COUNT_OVERRIDE}
    fi
    if [[ ${DEV_TESTS_COUNT-} -ne 0 ]]; then
        os_log_info "[update_config] Overriding test count from [${CERT_TEST_COUNT}] to [${DEV_TESTS_COUNT}]"
        CERT_TEST_COUNT=${DEV_TESTS_COUNT}
    fi
    os_log_info "[update_config] Total tests found: [${CERT_TEST_COUNT}]"
}

#
# openshift login
#

# openshift_login perform the login on internal kube-apiserver. The credentials
# should be shared on the exported KUBECONFIG file.
openshift_login() {
    os_log_info "[login] Login to OpenShift cluster [${KUBE_API_INT}]"
    ${UTIL_OC_BIN} login "${KUBE_API_INT}" \
        --token="$(cat "${SA_TOKEN_PATH}")" \
        --certificate-authority="${SA_CA_PATH}" || true;

    os_log_info "[login] Discovering apiServerInternalURI"
    INT_URI="$(${UTIL_OC_BIN} get infrastructures cluster -o json | jq -r .status.apiServerInternalURI)"

    os_log_info "[login] Login to OpenShift cluster with internal URI [${INT_URI}]"
    ${UTIL_OC_BIN} login "${INT_URI}" \
        --token="$(cat "${SA_TOKEN_PATH}")" \
        --certificate-authority="${SA_CA_PATH}" || true;
}

#
# JUnit utils
#

# create_junit_with_msg creates a "fake" JUnit result file with a custom message
# with reason, to help on the user feedback.
create_junit_with_msg() {
    local msg_type
    local msg
    local failures_count
    local junit_file
    local junit_file_type
    local test_payload

    msg_type="$1"; shift
    msg="$1"; shift
    junit_file_type="${1:-e2e}"
    failures_count=0
    skipped_count=0

    if [[ "${msg_type}" == "failed" ]]; then
        failures_count=1
        test_payload="<failure message=\"\">OPCT Plugin runtime: unexpected execution failure. Review the plugin logs.</failure><system-out></system-out>"
    fi
    if [[ "${msg_type}" == "skipped" ]]; then
        skipped_count=1
        test_payload="<skipped message=\"OPCT Plugin Runtime: test skipped. Review the plugin logs for details.\"/>"
    fi
    junit_file="${RESULTS_DIR}/junit_${junit_file_type}_${msg_type}_$(date +%Y%m%d-%H%M%S).xml"

    os_log_info "Creating ${msg_type} JUnit result file [${junit_file}]"
    cat << EOF > "${junit_file}"
<testsuite name="openshift-tests" tests="1" skipped="${skipped_count}" failures="${failures_count}" time="1.0">
 <property name="TestVersion" value="v4.1.0"></property>
 <testcase name="${msg}" time="0"> ${test_payload:-''}
</testcase>
</testsuite>
EOF
    chmod 644 "${junit_file}"
}
export -f create_junit_with_msg

#
# Utilities extractor
#

# start_utils_extractor extracts the openshift-tests utility
# from local registry - the image-registry is required, the CLI
# checks it before calling the plugin.
start_utils_extractor() {
    os_log_info "[extractor] Starting"

    local registry_host
    local registry_host_router
    local registry_args
    registry_host="image-registry.openshift-image-registry.svc:5000"

    os_log_info "[extractor_login] setting image-puller arguments to use service-account's token"
    registry_args="--auth-basic=image-puller:$(cat "${SA_TOKEN_PATH}")"

    # The image-registry fails the authentication in the internal registry when
    # custom route is defined. Workaround it.
    os_log_info "[extractor_login] checking if the defaultRoute is set to the image-registry"
    cfg_default_route=$(${UTIL_OC_BIN} get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.defaultRoute}')
    if [[ $cfg_default_route == true ]]; then

        os_log_info "[extractor_login] getting image registry routes"
        registry_host_router=$(${UTIL_OC_BIN} get routes -n openshift-image-registry -o json \
            | jq -r '.items[] | select(.metadata.name == "default-route").spec.host // ""' || true)

        if [ -z "${registry_host_router:-}" ]; then
            os_log_info "[extractor_login] ERROR: image-registry config is .spec.defaultRoute=true, but the route was not found."
            os_log_info "[extractor_login] Review the result of the following commands:"
            echo "\$ ${UTIL_OC_BIN} get configs.imageregistry.operator.openshift.io/cluster -o jsonpath='{.spec.defaultRoute}'"
            echo "\$ ${UTIL_OC_BIN} get routes -n openshift-image-registry"

            create_junit_with_msg "failed" "[opct][preflight] unable to extract oc utility. Check if image-registry is present."
            touch "${UTIL_OC_FAILED}"
        fi

        os_log_info "[extractor_login] setting up login to registry with args: --registry=${registry_host} --auth-basic=image-puller:[redacted]"
        registry_host=${registry_host_router}
        registry_args+=" --registry=${registry_host}"
    fi

    os_log_info "[extractor_login] initiating registry login at ${registry_host}"
    ${UTIL_OC_BIN} registry login "${registry_args}"

    # Extracting oc (from tests image)
    local util_oc="./oc"
    os_log_info "[extractor][oc] upgrading 'oc' from ${registry_host}/openshift/tests:latest"
    ${UTIL_OC_BIN} image extract \
        "${registry_host}"/openshift/tests:latest \
        --insecure=true \
        --file="/usr/bin/oc"

    os_log_info "[extractor][oc] check if it was downloaded"
    if [[ ! -f ${util_oc} ]]; then
        create_junit_with_msg "failed" "[opct][preflight] unable to extract oc utility. Check if image-registry is present."
        touch "${UTIL_OC_FAILED}"
        exit 1
    fi

    os_log_info "[extractor][oc] set exec permissions for ${UTIL_OC_BIN}"
    chmod u+x ${util_oc}
    if [[ ! -x ${UTIL_OC_BIN} ]]; then
        create_junit_with_msg "failed" "[opct][preflight] unable to make ${UTIL_OC_BIN} executable."
        touch "${UTIL_OC_FAILED}"
        exit 1
    fi

    os_log_info "[extractor][oc] move to ${UTIL_OC_BIN}"
    mv -f ${util_oc} "${UTIL_OC_BIN}"

    os_log_info "[extractor][oc] getting the version"
    ${UTIL_OC_BIN} version

    os_log_info "[extractor][oc] Success! Unlocking extractor"
    touch "${UTIL_OC_READY}"

    # Extracting openshift-tests
    local util_otests="./openshift-tests"
    os_log_info "[extractor][openshift-tests] extracting ${registry_host}/openshift/tests:latest"
    ${UTIL_OC_BIN} image extract \
        "${registry_host}"/openshift/tests:latest \
        --insecure=true \
        --file="/usr/bin/openshift-tests"

    os_log_info "[extractor][openshift-tests] check if it was downloaded"
    if [[ ! -f ${util_otests} ]]; then
        create_junit_with_msg "failed" "[opct][preflight][openshift-tests] unable to extract utility. Check if image-registry is present."
        touch "${UTIL_OTESTS_FAILED}"
        exit 1
    fi
    chmod u+x ${util_otests}

    os_log_info "[extractor][openshift-tests] move to ${UTIL_OTESTS_BIN}"
    mv ${util_otests} "${UTIL_OTESTS_BIN}"

    os_log_info "[extractor][openshift-tests] set exec permissions for ${UTIL_OTESTS_BIN}"
    if [[ ! -x ${UTIL_OTESTS_BIN} ]]; then
        create_junit_with_msg "failed" "[opct][preflight][openshift-tests] unable to make ${UTIL_OTESTS_BIN} executable."
        touch "${UTIL_OTESTS_FAILED}"
        exit 1
    fi

    os_log_info "[extractor][openshift-tests] testing openshift-tests"
    tt_tests=$(${UTIL_OTESTS_BIN} run all --dry-run | wc -l)
    if [[ ${tt_tests} -le 0 ]]; then
        create_junit_with_msg "failed" "[opct][preflight][openshift-tests] failed to get tests from ${UTIL_OTESTS_BIN} utility. Found [${tt_tests}] tests."
        touch "${UTIL_OTESTS_FAILED}"
        exit 1
    fi
    os_log_info "[extractor][openshift-tests] Success! [${tt_tests}] tests available."

    os_log_info "[extractor][openshift-tests] unlocking extractor"
    touch "${UTIL_OTESTS_READY}"
}
export -f start_utils_extractor

# wait_utils_extractor waits the UTIL_OTESTS_READY control file to be created,
# it will be ready when the openshift-tests is extracted from internal registry,
# controller by start_utils_extractor().
wait_utils_extractor() {
    os_log_info "[extractor_wait][oc] waiting for utils_extractor()"
    while true;
    do
        os_log_info "[extractor_wait][oc] Check files exists=[${UTIL_OC_READY} ${UTIL_OC_FAILED}]"
        test -f "${UTIL_OC_READY}" && break
        test -f "${UTIL_OC_FAILED}" && exit 1
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
    os_log_info "[extractor_wait][oc] finished!"

    os_log_info "[extractor_wait][openshift-tests] waiting for utils_extractor()"
    while true;
    do
        os_log_info "[extractor_wait][openshift-tests] Check files exists=[${UTIL_OTESTS_READY} ${UTIL_OTESTS_FAILED}]"
        test -f "${UTIL_OTESTS_READY}" && break
        test -f "${UTIL_OTESTS_FAILED}" && exit 1
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
    os_log_info "[extractor_wait][openshift-tests] finished!"
}


# start_status_collector collects the results of Sonobuoy plugins.
# The scraper will keep the status file STATUS_FILE consumed
# by different components on this container (waiter, progress reporter).
start_status_collector() {
    os_log_info "[status_collector] Starting"
    while true;
    do
        ${SONOBUOY_BIN} status \
            -n "${ENV_POD_NAMESPACE:-sonobuoy}" --json \
            2>/dev/null > "${STATUS_FILE}"
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
}
export -f start_status_collector

# wait_status_file waits for STATUS_FILE be created by start_status_collector()
# blocking the execution until this file is created.
wait_status_file() {
    os_log_info "[status_file] Starting"
    while true;
    do
        os_log_info "[status_file] Check file exists=[${STATUS_FILE}]"
        test -f "${STATUS_FILE}" && break
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
    os_log_info "[status_file] Status file found!"
}
export -f wait_status_file

#
# Cluster 'Upgrade' feature
#

# Run preflight checks before the upgrade. The execution must fail
# when there is not MachineConfigPool named 'opct' on the cluster.
# Required on the documentation:
# https://github.com/redhat-openshift-ecosystem/provider-certification-tool/blob/main/docs/user.md#prerequisites
# https://issues.redhat.com/browse/OPCT-35
preflight_check_upgrade() {
    os_log_info "[preflight][upgrade] starting checks for 'upgrade'..."

    if [[ "${RUN_MODE:-''}" != "${PLUGIN_RUN_MODE_UPGRADE}" ]]; then
        os_log_info "[preflight][upgrade] ignoring checks as RUN_MODE!=upgrade [${PLUGIN_RUN_MODE_UPGRADE}]"
        touch "${CHECK_MCP_READY}"
        return
    fi

    if [[ "${PLUGIN_ID}" == "${PLUGIN_ID_OPENSHIFT_ARTIFACTS_COLLECTOR}" ]]; then
        os_log_info "[preflight][upgrade] check for PLUGIN_ID=${PLUGIN_ID_OPENSHIFT_ARTIFACTS_COLLECTOR}"
        touch "${CHECK_MCP_READY}"
        return
    fi

    os_log_info "[preflight][upgrade] check MachineConfigPool 'opct' exists"
    ${UTIL_OC_BIN} get machineconfigpool opct
    RC_MCP=$?
    if [[ ${RC_MCP} -ne 0 ]]; then
        err="MachineConfigPool opct not found. Return code=${RC_MCP}"
        create_junit_with_msg "failed" "[opct][mode=${PLUGIN_RUN_MODE_UPGRADE}] ${err}" "upgrade"
        os_log_info "[executor] ${err}. Exiting..."
        touch "${CHECK_MCP_FAILED}"
        exit 1
    fi
    touch "${CHECK_MCP_READY}"
}
export -f preflight_check_upgrade

# Wait for check file for MCP
# https://issues.redhat.com/browse/OPCT-35
preflight_check_upgrade_waiter() {
    os_log_info "[preflight_check][upgrade-waiter] waiting for MachineConfigPool check"
    while true;
    do
        os_log_info "[preflight_check][upgrade-waiter] Check files exists=[${CHECK_MCP_READY} ${CHECK_MCP_FAILED}]"
        test -f "${CHECK_MCP_READY}" && break
        test -f "${CHECK_MCP_FAILED}" && exit 1
        sleep "${STATUS_UPDATE_INTERVAL_SEC}"
    done
    os_log_info "[preflight_check][upgrade-waiter] finished!"
}
export -f preflight_check_upgrade_waiter


#
# Plugin replay
#
# Global vars starts with REPLAY_* and can be overriden by --plugin-env command line.
#

replay_extract_from_config() {
    os_log_info "[openshift-tests-plugin][replay] Attemping to extract custom e2e tests to replay from namespace(${REPLAY_NAMESPACE}) config(${REPLAY_CONFIG}) key(${REPLAY_CONFIG_KEY})"
    ${UTIL_OC_BIN} extract "configmap/${REPLAY_CONFIG}" \
        -n "${REPLAY_NAMESPACE}" \
        --to=/tmp --keys="${REPLAY_CONFIG_KEY}" || true

    test -f "${REPLAY_CONFIG_FILE}" && cat "${REPLAY_CONFIG_FILE}"

}
export -f replay_extract_from_config

replay_run_e2e() {
    os_log_info "[openshift-tests-plugin][replay] Running e2e"
    if [[ -f "${REPLAY_CONFIG_FILE}" ]]; then
        os_log_info "[openshift-tests-plugin][replay] Running e2e from custom config ${REPLAY_CONFIG_FILE}"
        ${UTIL_OTESTS_BIN} run "${REPLAY_SUITE}" \
            -f "${REPLAY_CONFIG_FILE}" \
            --max-parallel-tests "${REPLAY_MAX_PARALLEL_TESTS}" \
            --junit-dir="${REPLAY_JUNIR_DIR}" \
            --monitor "${REPLAY_MONITOR_FOCUS}"
    else
        os_log_info "[openshift-tests-plugin][replay] Running e2e from suite ${REPLAY_SUITE}"
        ${UTIL_OTESTS_BIN} run "${REPLAY_SUITE}" \
            --max-parallel-tests "${REPLAY_MAX_PARALLEL_TESTS}" \
            --junit-dir="${REPLAY_JUNIR_DIR}" \
            --monitor "${REPLAY_MONITOR_FOCUS}"
    fi
}
export -f replay_run_e2e

replay_save_results_e2e() {
    os_log_info "[openshift-tests-plugin][replay] Saving e2e results..."
    pushd "${REPLAY_JUNIR_DIR}" || return
    tar cfz "${REPLAY_RESULTS}/e2e_raw_junits.tar.gz" -- *
    popd || return
}
export -f replay_save_results_e2e

replay_save_results() {
    os_log_info "[openshift-tests-plugin][replay] Saving raw results..."
    pushd "${REPLAY_RESULTS}" || return
    tar cfz "${RESULTS_DIR}/replay-results.tar.gz" -- *
    popd || return
}
export -f replay_save_results

replay_save() {
    os_log_info "[openshift-tests-plugin][replay] Saving results"
    mkdir -vp "${REPLAY_RESULTS}"
    cp -v "${REPLAY_CONFIG_FILE}" "${REPLAY_RESULTS}" || true
    replay_save_results_e2e || true
    replay_save_results
    os_log_info "[openshift-tests-plugin][replay] Notifying Sonobuoy agent"
    echo "${RESULTS_DIR}/replay-results.tar.gz" > /tmp/sonobuoy/results/done
}
export -f replay_save

# Standalone
replay_plugin_run() {
    os_log_info "[openshift-tests-plugin][replay] Starting plugin"
    os_log_info "[openshift-tests-plugin][replay] Dumping config"
    cat << EOF
REPLAY_RESULTS=${REPLAY_RESULTS-}
REPLAY_NAMESPACE=${REPLAY_NAMESPACE-}
REPLAY_CONFIG_MAP=${REPLAY_CONFIG_MAP-}
REPLAY_CONFIG_KEY=${REPLAY_CONFIG_KEY-}
REPLAY_CONFIG_FILE=${REPLAY_CONFIG_FILE-}
REPLAY_SUITE=${REPLAY_SUITE-}
REPLAY_MAX_PARALLEL_TESTS=${REPLAY_MAX_PARALLEL_TESTS-}
REPLAY_JUNIR_DIR=${REPLAY_JUNIR_DIR-}
REPLAY_MONITOR_FOCUS=${REPLAY_MONITOR_FOCUS-}
EOF
    openshift_login
    start_utils_extractor
    replay_extract_from_config
    replay_run_e2e
    replay_save
}
export -f replay_plugin_run
