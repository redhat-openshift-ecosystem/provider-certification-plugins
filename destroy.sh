#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

sonobuoy delete --wait

sleep 5
# Check if there's 'e2e-' namespaces (it should be deleted when starting new tests)
# TODO: Is there any other reuqirement to simulate a clean installation to start
#  running the suite of tests instead of providing a new cluster installation?
for project in $(oc get projects |awk '{print$1}' |grep ^e2e |sort -u || true); do
    echo "Stale namespace was found: [${project}], removing..."
    oc delete project "${project}"
done
