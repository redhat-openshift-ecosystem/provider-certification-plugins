#!/bin/sh

#
# Provider certification tests generator.
#

set -o pipefail
set -o nounset
set -o errexit

echo "> Running Tests Generator..."

openshift_tests_img="${OPENSHIFT_TESTS:-'openshift-tests:latest'}"

tests_path="$(dirname $0)/../tests"
tests_level1="${tests_path}/level1.txt"
tests_level2="${tests_path}/level2.txt"
tests_level3="${tests_path}/level3.txt"

>${tests_level1}
>${tests_level2}
>${tests_level3}

run_openshift_tests() {
    podman run --rm --name openshift-tests \
        -it openshift-tests:latest openshift-tests run --dry-run $@
}

#
# Tests by SIG
# Each sig should define the jobs which will run for each Level/Tier.
#

# SIG=sig-storage
level1_sig_storage() {
    #TODO(tests-by-level): temp truncate to 100 tests when the
    # tool development is in progress.
    # The original results (without 'tail') will retrieve 6k tests.
    run_openshift_tests "all" |grep '\[sig-storage\]' \
        |tail -n 100 | tee -a "${tests_level1}"
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

# SIG=sig-cli
level1_sig_cli() {
    :
}

level2_sig_cli() {
    #TODO(tests-by-level): Aligned real filter w/ SIG.
    # The filter below has being used on development process.
    run_openshift_tests "all" \
        | grep '\[sig-cli\]' |grep '\[Conformance\]' \
        | tee -a "${tests_level2}"
}

level3_sig_cli() {
    :
}

sig_cli() {
    level1_sig_cli
    level2_sig_cli
    level3_sig_cli
}

#
# Finalizer
#

# collect
collector() {
    sig_storage >/dev/null
    sig_cli >/dev/null
}
collector

# parser
cp ${tests_level1} ${tests_level1}.tmp
cat "${tests_level1}.tmp" |sort -u > ${tests_level1}

cp ${tests_level2} ${tests_level2}.tmp
cat "${tests_level2}.tmp" |sort -u > ${tests_level2}

cp ${tests_level3} ${tests_level3}.tmp
cat "${tests_level3}.tmp" |sort -u > ${tests_level3}

rm -rvf ${tests_path}/*.tmp

wc -l ${tests_path}/*.txt

echo "> Tests Generator Done."
