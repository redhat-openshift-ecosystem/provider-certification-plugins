#!/usr/bin/env bash

# Build openshift-tests binary
# https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests

PULL_SECRET="${HOME}/.openshift/pull-secret-latest.json"
tmp_origin="./tmp/origin"
rm -rf "${tmp_origin}"
git clone git@github.com:openshift/origin.git "$tmp_origin"

pushd "${tmp_origin}" || exit 1
podman build \
    --authfile "${PULL_SECRET}" \
    -t openshift-tests:latest \
    -f images/tests/Dockerfile.rhel .
popd || true
