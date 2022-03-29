#!/bin/sh

#
# Provider certification tests generator.
#

openshift_tests_img="${OPENSHIFT_TESTS:-'openshift-tests:latest'}"

run_openshift_tests() {
    podman run --rm --name openshift-tests \
        -it openshift-tests:latest openshift-tests run --dry-run $@
}


run_openshift_tests all |grep -Po '(\[sig-[a-zA-Z]*\])' |sort |uniq -c |sort -n
