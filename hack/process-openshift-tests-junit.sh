#!/bin/env bash

base_res_dir="./results"
processed_dir="${base_res_dir}/processed"

mkdir -p ${processed_dir}

truncate -s 0 ${processed_dir}/filter-tag.txt

for td in "${base_res_dir}"/*/; do
    echo -e "\n#> Processing" "${td}"
    test_id=$(basename "${td}")
    junit_file=$(ls "${td}"/*.xml 2>/dev/null || true)
    if [[ ! -f ${junit_file} ]]; then
        echo "There's no junit files inside" "${test_id}"
        continue
    fi
    xq -r ".testsuite | [\"${test_id}\", .[\"@time\"], .[\"@tests\"], .[\"@skipped\"], .[\"@failures\"]] | @tsv" "${junit_file}"

    # extract all test list
    all_file="${processed_dir}/${test_id}-all.txt"
    echo "#>> Writing all file to ${all_file}"
    xq  '.testsuite.testcase[]["@name"]' "${junit_file}" | sort > "${all_file}"

    echo "#>> Extracting first tag and saving to ${processed_dir}/filter-tag.txt"
    awk -F'\]' '{print$1}' "${all_file}" |awk -F'[' '{print$2}' |sort |uniq -c |awk -v test_id="${test_id}" '{print test_id ";" $2 ";" $1 }' |sort >> ${processed_dir}/filter-tag.txt
done
