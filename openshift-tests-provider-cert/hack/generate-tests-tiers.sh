#!/usr/bin/env bash

#
# Provider certification tests generator.
#

set -o pipefail
set -o nounset
set -o errexit

echo "> Running Tests Generator..."

openshift_tests_img="${OPENSHIFT_TESTS:-"openshift-tests:latest"}"

#TODO: Need to find a strategy to collect and save tests by
# OCP release. Example: Make sure all tests ran on 4.y.z should store
# and be the same.
openshift_version="${1:-"v4.10"}"
tests_path="$(dirname "$0")/../tests/${openshift_version}"
tests_level1="${tests_path}/level1.txt"
tests_level2="${tests_path}/level2.txt"
tests_level3="${tests_path}/level3.txt"

mkdir -p "${tests_path}"
truncate -s0 "${tests_level1}"
truncate -s0 "${tests_level2}"
truncate -s0 "${tests_level3}"

run_openshift_tests() {
    podman run --rm --name openshift-tests \
        -it "${openshift_tests_img}" openshift-tests run --dry-run "$@"
}

#
# Tests by SIG
# Each sig should define the jobs which will run for each Level/Tier.
#

# SIG=sig-storage
level1_sig_storage() {
    #TODO(tests-by-level): temp filter to run only [Conformance] and
    # avoid endless execution. Original partner should be:
    # '^(?=.*\[sig-storage\])'
    run_openshift_tests "all" \
        | grep -P '^(?=.*\[sig-storage\])(?=.*\[Conformance\])' \
        | tee -a "${tests_level1}"
}

level2_sig_storage() {
    :
}

level3_sig_storage() {
    :
}

sig_storage() {
    level1_sig_storage
    level2_sig_storage
    level3_sig_storage
}

#
# Finalizer
#

# collect
collector() {
    sig_storage >/dev/null
}
collector

# Creating unique test names by Tier
cp "${tests_level1}" "${tests_level1}.tmp"
sort -u "${tests_level1}.tmp" > "${tests_level1}"

cp "${tests_level2}" "${tests_level2}.tmp"
sort -u "${tests_level2}.tmp" > "${tests_level2}"

cp "${tests_level3}" "${tests_level3}.tmp"
sort -u "${tests_level3}.tmp" > "${tests_level3}"

rm -rvf "${tests_path}"/*.tmp

# TODO(pre-release): Removing duplicate tests by Tier.

# Review tests count by Tier
wc -l "${tests_path}"/*.txt

echo "> Tests Generator Done."
