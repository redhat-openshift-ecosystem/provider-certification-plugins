#!/usr/bin/env bash

declare -gx PLUGIN_BLOCKED_BY
PLUGIN_BLOCKED_BY=()

declare -grx CERT_TESTS_DIR="./tests/${OPENSHIFT_VERSION:-"v4.10"}"

declare -gx CERT_LEVEL
declare -gx CERT_TEST_FILE
declare -gx CERT_TEST_FILE_COUNT

declare -gAx PROGRESS
declare -grx PROGRESS_URL="http://127.0.0.1:8099/progress"
declare -grx SONOBUOY_BIN="./sonobuoy"
declare -grx STATUS_FILE="/tmp/sonobuoy-status.json"
declare -grx STATUS_UPDATE_INTERVAL_SEC="5"

declare -grx RESULTS_DIR="${RESULTS_DIR:-/tmp/sonobuoy/results}"
declare -grx RESULTS_DONE_NOTIFY="${RESULTS_DIR}/done"
declare -grx RESULTS_PIPE="${RESULTS_DIR}/status_pipe"
declare -grx RESULTS_SCRIPTS="${RESULTS_DIR}/plugin-scripts"

declare -grx KUBECONFIG="${RESULTS_DIR}/kubeconfig"
declare -grx SA_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -grx SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

