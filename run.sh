#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

echo "Starting OpenShift Provider Certification Tool..."

# Check if there's sonobuoy environment: should fail
NS_SONOBUOY="$(oc get projects |grep ^sonobuoy || true)"
if [[ -n "${NS_SONOBUOY}" ]]; then
    echo "sonobuoy project is present on cluster. Run the destroy flow: ./destroy.sh"
    exit 1
fi

# Check if there's 'e2e-' namespaces (it should be deleted when starting new tests)
# TODO: Is there any other reuqirement to simulate a clean installation to start
#  running the suite of tests instead of providing a new cluster installation?
for project in $(oc get projects |awk '{print$1}' |grep ^e2e |sort -u || true); do
    echo "Stale namespace was found: [${project}], deleting..."
    oc delete project "${project}" || true
done

echo "Running OpenShift Provider Certification Tool..."
sleep 5

# Do not use timeout=0:
# https://github.com/mtulio/openshift-provider-certification/issues/17
PLUGIN_TIMEOUT=43200
sonobuoy run \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --timeout ${PLUGIN_TIMEOUT} \
    --plugin tools/plugins/openshift-provider-cert-level-1.yaml \
    --plugin tools/plugins/openshift-provider-cert-level-2.yaml \
    --plugin tools/plugins/openshift-provider-cert-level-3.yaml

sleep 5 # waiting to leave from 'Pending' state
echo "$(date)> The certification tool is running, statuses will be reported every minute..."
sonobuoy status

cnt=0
while true; do
    if [[ "$(sonobuoy status --json |jq -r .status)" != "running" ]]; then
        break
    fi
    cnt=$(( cnt + 1 ))
    if [[ $(( cnt % 3 )) -eq 0 ]]; then
        echo -e "\n\n$(date)> Sonobuoy is still running..."
        sonobuoy status
    fi
    sleep 10
done

echo -e "\n$(date)> Test suite has finished."
sonobuoy status

echo -e "\nWaiting the results to be processed..."
cnt=0
while true; do
    if [[ "$(sonobuoy status --json |jq -r .status)" != "post-processing" ]]; then
        break
    fi
    cnt=$(( cnt + 1 ))
    if [[ $cnt -eq 20 ]]; then
        echo -e "\n\n$(date)> Timeout waiting the result post-processor..."
        echo -e "\n\n$(date)> Run again with option 'check'"
        exit 1
    fi
    sleep 30
done

echo -e "\nCollecting results..."
sleep 10

result_file=$(sonobuoy retrieve)
RC=$?
# TODO[1](release): need to collect artifacts if
#  'sonobuoy retrieve' returned 'EOF' (download error).
# https://github.com/mtulio/openshift-provider-certification/issues/4
# TODO[2](asap): The filename could be set for 'retrieve' option,
# so it can be an work arround while [1] is not fixed.
if [[ ${RC} -ne 0 ]]; then
    echo "One or more errors found to retrieve results"
    exit ${RC}
fi

if [[ -f ${result_file} ]]; then
    echo "Results saved at file ${result_file}"
    echo "Conformance runner has finished successfully."

    # Used by report.sh
    # TODO(pre-release): improve the result inspection.
    # TODO(asap): remove dependency of report.sh
    # https://github.com/mtulio/openshift-provider-certification/issues/16
    test -f .tmp/ && mv .tmp/ .tmp/old-"$(date +%Y%m%d%H%M%S)"
    test -f .tmp/ || mkdir -p .tmp/
    echo "${result_file}" > .tmp/latest-result.txt
    cp "${result_file}" ./.tmp/
    exit 0
fi

echo "Results file not found. Execution has finished with errors."
exit 1
