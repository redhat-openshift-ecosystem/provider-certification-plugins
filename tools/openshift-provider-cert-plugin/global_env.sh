
declare -x PLUGIN_BLOCKED_BY
PLUGIN_BLOCKED_BY=()

declare -x CERT_TEST_FILE
CERT_TEST_FILE=""

declare -Ax PROGRESS
declare -rx PROGRESS_URL="http://127.0.0.1:8099/progress"

declare -rx RESULTS_DIR="${RESULTS_DIR:-/tmp/sonobuoy/results}"
declare -rx RESULTS_DONE_NOTIFY="${RESULTS_DIR}/done"
declare -rx RESULTS_PIPE="${RESULTS_DIR}/status_pipe"
declare -rx RESULTS_SCRIPTS="${RESULTS_DIR}/plugin-scripts"

declare -rx KUBECONFIG="${RESULTS_DIR}/kubeconfig"
declare -rx SA_CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -rx SA_TOKEN_PATH="/var/run/secrets/kubernetes.io/serviceaccount/token"

