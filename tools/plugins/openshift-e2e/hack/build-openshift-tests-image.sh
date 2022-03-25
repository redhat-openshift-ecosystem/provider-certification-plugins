#!/bin/sh

# Build openshift-tests binary
# https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests

tmp_origin="./tmp/origin"
#rm -rf tmp/origin
git clone git@github.com:openshift/origin.git $tmp_origin

pushd ${tmp_origin}
podman build \
    --authfile $(PULL_SECRET) \
    -t openshift-tests:latest \
    -f images/tests/Dockerfile.rhel .
popd
