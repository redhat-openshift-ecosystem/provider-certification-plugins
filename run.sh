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
    --plugin tools/plugins/level-0-kube-conformance.yaml \
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
    # Detailed status
    st_file="/tmp/sonobuoy-status.json"
    sonobuoy status --json > "${st_file}"
    printf "\n\nGlobal Status: %s" "$(jq -r '.status // "Unknown"' ${st_file})"
    printf "\n%-30s | %-10s | %-10s | %-25s | %-50s" \
            "JOB_NAME" "STATUS" "RESULTS" "PROGRESS" "MESSAGE"
    for plugin_name in $(jq -r '.plugins[].plugin' /tmp/sonobuoy-status.json |sort); do
        pl_status=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").status" "${st_file}")
        pl_result=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-status\"]" "${st_file}" | tr -d '\n')

        pl_prog_total=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.total // \"\"" "${st_file}" | tr -d '\n')
        pl_prog_comp=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.completed // \"\"" "${st_file}" | tr -d '\n')
        pl_prog_failed=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.failures|length" "${st_file}" | tr -d '\n')
        pl_progress="${pl_prog_comp}/${pl_prog_total} (${pl_prog_failed} failures)"

        pl_count_fail=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].failed" "${st_file}" | tr -d '\n')
        pl_count_pass=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].passed" "${st_file}" | tr -d '\n')

        if [[ "${pl_status}" == "running" ]]; then
            pl_msg=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\") |.progress.msg // \"N/A\"" "${st_file}" | tr -d '\n')
        elif [[ "${pl_result}" == "" ]]; then
            pl_msg="waiting post-processor..."
        else
            pl_msg="Total tests processed: $(echo "$pl_count_pass + $pl_count_fail "|bc) (${pl_count_pass} pass / ${pl_count_fail} failed)"
        fi

        printf "\n%-30s | %-10s | %-10s | %-25s | %-50s" \
                "${plugin_name}" "${pl_status}" "${pl_result}" \
                "${pl_progress}" "${pl_msg}"
    done

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

set +o errexit
download_failed=true
retries=0
while ${download_failed}; do
    result_file=$(sonobuoy retrieve)
    RC=$?
    # TODO[1](release): need to collect artifacts if
    #  'sonobuoy retrieve' returned 'EOF' (download error).
    # https://github.com/mtulio/openshift-provider-certification/issues/4
    # TODO[2](asap): The filename could be set for 'retrieve' option,
    # so it can be an work arround while [1] is not fixed.
    if [[ ${RC} -eq 0 ]]; then
        #echo "One or more errors found to retrieve results"
        #exit ${RC}
        download_failed=false
    fi
    retries=$(( retries + 1 ))
    if [[ $retries -eq 10 ]]; then
        echo "Retries timed out. Check 'sonobuoy retrieve' command."
        exit 1
    fi
    echo "Error retrieving results. Waiting 10s to retry...[${retries}/10]"
    sleep 10
done
set -o errexit

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
