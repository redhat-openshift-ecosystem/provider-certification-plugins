#!/bin/env bash

for td in $(ls -d results/*/); do
    echo "Processing ${td}"
    test_id=$(basename ${td})
    junit_file=$(ls ${td}/*.xml 2>/dev/null || true)
    if [[ ! -f ${junit_file} ]]; then
        echo "There's no junit files inside ${test_id}"
        continue
    fi
    xq -r ".testsuite | [\"${test_id}\", .[\"@time\"], .[\"@tests\"], .[\"@skipped\"], .[\"@failures\"]] | @tsv" "${junit_file}"
done


