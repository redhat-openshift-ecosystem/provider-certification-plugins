results_dir="${RESULTS_DIR:-/tmp/sonobuoy/results}"
results_pipe="${results_dir}/status_pipe"

results_script_dir="${results_dir}/plugin-scripts"
test -d ${results_script_dir} || mkdir -p ${results_script_dir}
