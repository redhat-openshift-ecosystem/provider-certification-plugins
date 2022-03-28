#!/bin/sh

$(which time) sonobuoy run \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin tools/plugins/level-1.yaml \
    --plugin tools/plugins/level-2.yaml \
    --plugin tools/plugins/level-3.yaml
#    && sonobuoy retrieve

has_finished=false
cnt=0
while ${has_finished}; do
    if [[ $(sonobuoy status --json |jq -r .status) != "running" ]]; then
        has_finished=true
        break
    fi
    cnt=$(( cnt + 1 ))
    if [[ $(( cnt % 6 )) -eq 0 ]]; then
        echo "$(date)> Sonobuoy is still running..."
        sonobuoy status
    fi
    sleep 10
done
echo "$(date)> Sonobuoy has finished."
sonobuoy status

echo "Collecting results..."
sleep 10
result_file=$(sonobuoy retrieve)
if [[ $? -ne 0 ]]; then
    echo "One or more errors found to retrieve results"
    # Not exiting, sometimes sonobuoy returns error and retrive file
    #exit 1
fi

fi
if [[ -f ${result_file} ]]; then
    echo "Results saved at file ${result_file}"
    echo "Conformance runner has finished successfully."
    exit 0
fi

echo "Results file not found. Execution has finished with errors."
exit 1
