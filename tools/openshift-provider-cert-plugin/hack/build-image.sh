#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

registry="quay.io/mrbraga"

# build openshift-tests image (@openshift/origin)
test "$(podman image exists openshift-tests:latest; echo $?)" -eq 0 || \
    "$(dirname "$0")"/build-openshift-tests-image.sh

# generate tests
"$(dirname "$0")"/generate-tests-tiers.sh

# create plugin image
podman build -t ${registry}/openshift-tests-provider-cert:latest .
podman push ${registry}/openshift-tests-provider-cert:latest
