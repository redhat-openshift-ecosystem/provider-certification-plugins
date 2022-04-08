#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

echo "##> "
echo "#> Starting destroy flow..."

sonobuoy delete --wait

sleep 5
# Check if there's 'e2e-' namespaces (it should be deleted when starting new tests)
# TODO: Is there any other reuqirement to simulate a clean installation to start
#  running the suite of tests instead of providing a new cluster installation?
echo "Removing NSs created by openshift-tests"
mapfile -t NS_DELETE < <(oc get projects |awk '{print$1}' |grep ^e2e- |sort -u || true)
for project in "${NS_DELETE[@]}"; do
    echo "Stale namespace was found: [${project}], removing..."
    oc delete project "${project}" || true
done

# Projects created by k8s-e2e conformance tests.
# echo "Removing NSs created by kube-conformance"
# mapfile -t NS_DELETE < <(oc get projects |awk '{print$1}' |grep -P '^(statefulset-[\d+].*)|(proxy-[\d+].*)|(cronjob-[\d+].*)|(kubectl-[\d+].*)|(replication-controller-[\d+].*)|(sched-preemption-[\d+].*)|(taint-multiple-pods-[\d+].*)' || true)

sleep 10;
echo "Removing non-openshift NS (don't do it on the final release =] )"
mapfile -t NS_DELETE < <(oc get projects |awk '{print$1}' |grep -vP '^(NAME)|(openshift)|(kube-(system|public|node-lease))|(default)' |sort -u || true)
for project in "${NS_DELETE[@]}"; do
    echo "Stale namespace was found: [${project}], removing..."
    oc delete project "${project}" || true
done

echo "Removing status file"
st_file="/tmp/sonobuoy-status.json"
rm ${st_file} || true

echo "Restoring privileged environment..."
oc adm policy remove-scc-from-group anyuid system:authenticated system:serviceaccounts || true
oc adm policy remove-scc-from-group privileged system:authenticated system:serviceaccounts  || true

echo "Destroy Done!"
