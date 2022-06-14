#!/bin/env bash

#
# Convert sonobuoy_results.yaml to CSV
# > Plugins supported: openshift-conformance, kube-conformance
#
# > Usage:
# # ${0} ${tarball_results_file}
#

result_file="${1}"
if [[ ! -f $result_file ]]; then
    echo "Result file not found [$result_file]"
    exit 1
fi

filename="$(basename -s .tar.gz "${result_file}")"
test_id="$(basename -s .tar.gz "${result_file}" |awk -F'_sonobuoy_' '{print$1}')"

base_res_dir="./results"
processed_dir="${base_res_dir}/processed-${filename}"

csv_header="test_id , plugin , file , job , test , result , tag_sig"
csv_file_aggregated="${processed_dir}/plugins-results-aggregated.csv"
echo "${csv_header}" > "${csv_file_aggregated}"

mkdir -p "${processed_dir}"
rm -rvf "${processed_dir}/plugins"

PLUGINS=()
PLUGINS+=("openshift-kube-conformance")
PLUGINS+=("openshift-conformance-validated")

for plugin_name in "${PLUGINS[@]}"; do

    echo "[${plugin_name}] extracting test results"
    tar -xzvf "${result_file}" \
        -C "${processed_dir}" \
        "plugins/${plugin_name}/sonobuoy_results.yaml"

    echo "[${plugin_name}] exporting as json"
    yq . "${processed_dir}/plugins/${plugin_name}/sonobuoy_results.yaml" \
        > "${processed_dir}/${plugin_name}.json"

    #
    # Mount the csv headers
    #
    echo "[${plugin_name}] starting create the CSV"
    csv_file="${processed_dir}/${plugin_name}.csv"

    t_plugin=$(jq .name "${processed_dir}/${plugin_name}.json")
    t_file=$(jq .items[0].name "${processed_dir}/${plugin_name}.json")
    t_job=$(jq .items[0].items[0].name "${processed_dir}/${plugin_name}.json")

    echo "[${plugin_name}] parsing results json to csv"
    jq -r ".items[0].items[0].items[] |
        [ \"${test_id}\", ${t_plugin}, ${t_file}, ${t_job}, .name, .status, \"_todo_replace_sig_tag_\" ] 
        | @csv " "${processed_dir}/${plugin_name}.json" \
        > "${csv_file}.tmp"

    echo "[${plugin_name}] creating the CSV"
    echo "${csv_header}" > "${csv_file}"
    while read -r line; do

        sig_tag=$(echo "${line}" | grep -Po '(\[sig-[a-zA-Z-]*\])')
        new_line="${line//_todo_replace_sig_tag_/${sig_tag}}"

        echo "$new_line" >> "${csv_file}"
        echo "$new_line" >> "${csv_file_aggregated}"
    done < "${csv_file}.tmp"

    echo "[${plugin_name}] CSV saved at ${csv_file}"
done
