#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

echo "##> "
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

echo "Ensuring the Tool will run in the privileged environment..."
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts

echo "Running OpenShift Provider Certification Tool..."
sleep 5

# Do not use timeout=0:
# https://github.com/mtulio/openshift-provider-certification/issues/17
PLUGIN_TIMEOUT=43200

sonobuoy run \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --timeout ${PLUGIN_TIMEOUT} \
    --plugin tools/plugins/openshift-kube-conformance.yaml \
    --plugin tools/plugins/openshift-provider-cert-level-1.yaml \
    --plugin tools/plugins/openshift-provider-cert-level-2.yaml \
    --plugin tools/plugins/openshift-provider-cert-level-3.yaml

# Show custom status
st_file="/tmp/sonobuoy-status.json"
update_status() {
    sonobuoy status --json > "${st_file}" 2>/dev/null || true
}

show_status() {
    update_status
    printf "\n\n$(date)> Global Status: %s" "$(jq -r '.status // "Unknown"' ${st_file})"
    printf "\n%-30s | %-10s | %-10s | %-25s | %-50s" \
            "JOB_NAME" "STATUS" "RESULTS" "PROGRESS" "MESSAGE"
    for plugin_name in $(jq -r '.plugins[].plugin' ${st_file} |sort); do
        pl_status=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").status" "${st_file}")
        pl_result=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-status\"]" "${st_file}" | tr -d '\n')

        pl_prog_total=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.total // \"\"" "${st_file}" | tr -d '\n')
        pl_prog_comp=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.completed // \"\"" "${st_file}" | tr -d '\n')
        pl_prog_failed=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").progress.failures|length" "${st_file}" | tr -d '\n')

        pl_progress=""
        if [[ -n "${pl_prog_total}" ]]; then
            pl_progress="${pl_prog_comp}/${pl_prog_total} (${pl_prog_failed} failures)"
        fi

        pl_count_fail=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].failed // 0" "${st_file}" | tr -d '\n')
        pl_count_pass=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].passed // 0" "${st_file}" | tr -d '\n')

        if [[ "${pl_status}" == "running" ]]; then
            pl_msg=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\") |.progress.msg // \"\"" "${st_file}" | tr -d '\n')
        elif [[ "${pl_result}" == "" ]]; then
            pl_msg="waiting post-processor..."
        else
            pl_msg="Total tests processed: $(echo "$pl_count_pass + $pl_count_fail "|bc) (${pl_count_pass} pass / ${pl_count_fail} failed)"
        fi

        printf "\n%-30s | %-10s | %-10s | %-25s | %-50s" \
                "${plugin_name}" "${pl_status}" "${pl_result}" \
                "${pl_progress}" "${pl_msg}"
    done
}

show_results_processor() {
    update_status
    printf "\n\n$(date)> Global Status: %s" "$(jq -r '.status // "Unknown"' ${st_file})"
    printf "\n%-30s | %-10s | %-10s | %-50s" \
            "JOB_NAME" "STATUS" "RESULTS" "PROCESSOR RESULTS"
    for plugin_name in $(jq -r '.plugins[].plugin' ${st_file} |sort); do
        pl_status=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\").status" "${st_file}")
        pl_result=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-status\"]" "${st_file}" | tr -d '\n')

        pl_count_fail=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].failed" "${st_file}" | tr -d '\n')
        pl_count_pass=$(jq -r ".plugins[] | select (.plugin==\"${plugin_name}\")[\"result-counts\"].passed" "${st_file}" | tr -d '\n')

        pl_msg="Total tests processed: $(echo "$pl_count_pass + $pl_count_fail "|bc) (${pl_count_pass} pass / ${pl_count_fail} failed)"

        printf "\n%-30s | %-10s | %-10s | %-50s" \
                "${plugin_name}" "${pl_status}" \
                "${pl_result}" "${pl_msg}"
    done
}

sleep 5 # waiting to leave from 'Pending' state
echo "$(date)> The certification tool is running, statuses will be reported every minute..."
sonobuoy status

cnt=0
while true; do
    update_status
    if [[ "$(jq -r .status ${st_file})" != "running" ]]; then
        break
    fi
    show_status
    sleep 10
done

show_status
echo -e "\n\n$(date)> Jobs has finished."
sleep 5
show_results_processor

#TODO(): Create a fn show_results w/ custom fields of processor,
# w/o PROGRESS field.
#TODO(): there's a bug on kube-conformance suite with is crashing
# the plugin, resulting in empty junit files. Report-progress should
# report crashs like that w/ some insights on MSG aggregator field.

echo -e "\nWaiting the post-processor to collect the results..."
cnt=0
while true; do
    update_status
    if [[ "$(jq -r .status ${st_file})" != "post-processing" ]]; then
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

echo -e "\n\nCollecting results..."
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
