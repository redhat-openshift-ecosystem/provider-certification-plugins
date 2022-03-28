#!/usr/bin/env sh

set -o pipefail
set -o nounset
set -o errexit

tmp_dir="$(dirname $0)/.tmp"
result_file=$(cat ${tmp_dir}/latest-result.txt)
result_dir=${tmp_dir}/results
test -d ${result_dir} || mkdir -p $result_dir

plugin_names=()
for i in $(seq 1 3); do
  plugin_names+=("openshift-provider-cert-level$i")
done

pushd ${tmp_dir}  >/dev/null

if [[ ! -f $result_file ]]; then
  echo "Result file not found"
  exit 1
fi

echo "Inspecting latest result file: ${result_file}"

echo "Extracting sonobuoy results..."

for plugin_name in ${plugin_names[@]}; do
  tar -C results -xvf ./$result_file plugins/${plugin_name}/sonobuoy_results.yaml
done

echo "Getting result feedback..."

echo "Getting tests count by status for each Level:"

statusess="passed skipped failed";
for plugin_name in ${plugin_names[@]}; do
    for st in $statusess; do
        echo "#> ${plugin_name} [${st}]:";
        yq -r ".items[].items[].items[] | select (.status==\"$st\").name" \
            results/plugins/${plugin_name}/sonobuoy_results.yaml 2>/dev/null |wc -l || true ;
    done;
done

echo -e "\nGetting 'failed' test names by Level:"

statusess="failed";
for st in $statusess; do
    for plugin_name in ${plugin_names[@]}; do
        echo -e "\n#> ${plugin_name} [${st}]:";
        yq -r ".items[].items[].items[] | select (.status==\"$st\").name" \
            results/plugins/${plugin_name}/sonobuoy_results.yaml 2>/dev/null || true;
    done;
done

popd >/dev/null

echo -e "\n\nReport finished."
