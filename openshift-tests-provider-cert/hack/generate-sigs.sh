#!/usr/bin/env bash

#
# Provider certification tests generator.
#

run_openshift_tests() {
    podman run --rm --name openshift-tests \
        -it openshift-tests:latest openshift-tests run --dry-run "$@"
}


run_openshift_tests all |grep -Po '(\[sig-[a-zA-Z]*\])' |sort |uniq -c |sort -n
