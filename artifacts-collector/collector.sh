#!/usr/bin/env bash

#
# collector plugin
#

set -o pipefail
set -o nounset

declare -gr TOTAL_TEST_COUNT=10
declare -gx TOTAL_TEST_RUN=0

#
# Collector functions
#

inc_test_run() {
    TOTAL_TEST_RUN=$((TOTAL_TEST_RUN+1))
}

send_test_progress() {
    inc_test_run
    # N/D is unexpected, but it's a fallback to avoid empty messages.
    openshift-tests-plugin exec progress-msg \
        --message "${1:-N/D}" \
        --total "${TOTAL_TEST_COUNT}" \
        --current "${TOTAL_TEST_RUN}";
}

# Collect must-gather and pre-process any data* from it, then create a tarball file.
collect_must_gather() {
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Collecting must-gather"
    ${UTIL_OC_BIN} adm must-gather --dest-dir=must-gather-opct

    # TODO: Pre-process data from must-gather to avoid client-side extra steps.
    # Examples of data to be processed:
    # > insights rules

    # extracting msg from etcd logs: request latency apply took too long (attl)
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Collecting etcd log filters"

    # generate camgi report
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Generating camgi report"
    camgi must-gather-opct/ > artifacts_must-gather_camgi.html || true

    # Create the tarball file artifacts_must-gather.tar.xz
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Packing must-gather"
    tar cfJ artifacts_must-gather.tar.xz must-gather-opct*

    os_log_info "[executor][PluginID#${PLUGIN_ID}] must-gather collector done."
}

# collect_performance_etcdfio run the recommended method to measure the disk information
# for etcd deployments. It will run into two nodes for each role (master and worker).
collect_performance_etcdfio() {
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Starting Artifacts Collector - Performance - etcdfio"
    local image
    local msg_prefix

    msg_prefix="[executor][PluginID#${PLUGIN_ID}][performance][etcdfio]:"

    image=quay.io/openshift-scale/etcd-perf:latest
    if [ -n "${MIRROR_IMAGE_REPOSITORY:-}" ]; then
        from=$image
        image="${MIRROR_IMAGE_REPOSITORY}/etcd-perf:latest"
        os_log_info "${msg_prefix} image overrided for disconnected. from=[$from] to=[$image]"
    fi

    os_log_info "${msg_prefix} running tests on master nodes"
    local idx=0
    node_role="controlplane"
    for node in $(${UTIL_OC_BIN} get nodes -l 'node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
        os_log_info "[executor][PluginID#${PLUGIN_ID}][performance][etcdfio] ${node_role}#${idx}: ${node}"
        send_test_progress "status=running=collecting performance data=fio=${node_role}[${idx}]=${node}";

        result_file="./artifacts_performance_etcdfio_${node_role}-${idx}.txt"
        oc debug node/"${node}" -- chroot /host /bin/bash -c "podman run --volume /var/lib/etcd:/var/lib/etcd:Z ${image}" > "${result_file}";
        echo "etcdfio=${node}=$(grep ^'INFO: 99th percentile of fsync is ' ${result_file} | awk -F'of fsync is ' '{print$2}')" >> ${result_file}

        idx=$((idx+1))
        test $idx -ge 3 && break
    done

    os_log_info "${msg_prefix} running tests on worker nodes"
    idx=0
    node_role="worker"
    for node in $(${UTIL_OC_BIN} get nodes -l '!node-role.kubernetes.io/master' -o jsonpath='{.items[*].metadata.name}'); do
        os_log_info "[executor][PluginID#${PLUGIN_ID}][performance][etcdfio] ${node_role}#${idx}: ${node}"
        send_test_progress "status=running=collecting performance data=fio=${node_role}[${idx}]=${node}";

        result_file="./artifacts_performance_etcdfio_${node_role}-${idx}.txt"
        oc debug node/"${node}" -- chroot /host /bin/bash -c "mkdir /var/cache/opct; podman run --volume /var/cache/opct:/var/lib/etcd:Z ${image}" > "${result_file}";
        echo "etcdfio=${node}=$(grep ^'INFO: 99th percentile of fsync is ' ${result_file} | awk -F'of fsync is ' '{print$2}')" >>  ${result_file}

        idx=$((idx+1))
        test $idx -ge 2 && break
    done

    os_log_info "${msg_prefix} finished!"
}

# collect performance tests
collect_performance() {
    # Collect disk performance information with: etcdfio
    collect_performance_etcdfio
}

# collect_metrics extracts metrics from Prometheus within the time frame the
# OPCT was executed (~6 hours), saving it as a raw data into the
# artifact path. The Prometheus expression are preferred than the raw metric to
# save storage and server-side CPU/RAM processing raw data.
# The expressions are extracted from OpenShift Dashboards.
# There is no automation to load the extracted data at this moment. There were
# some initial work backfilling raw prometheus query in this project:
# https://github.com/mtulio/must-gather-monitoring#load-metrics-to-a-local-prometheus-deployment
# The collector script (must-gather-monitoring) was adapted from the original proposal:
# https://github.com/openshift/must-gather/pull/214
collect_metrics() {
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Starting Metrics Collector"

    local image
    local msg_prefix

    msg_prefix="[executor][PluginID#${PLUGIN_ID}][collector][metrics]:"

    image=${IMAGE_OVERRIDE_MUST_GATHER}
    if [ -n "${MIRROR_IMAGE_REPOSITORY:-}" ]; then
        from=$image
        image="${MIRROR_IMAGE_REPOSITORY}/must-gather-monitoring:${VERSION_IMAGE_MUST_GATHER}"
        os_log_info "${msg_prefix} image overrided for disconnected. from=[$from] to=[$image]"
    fi

    os_log_info "${msg_prefix} collecting metrics..."
    ${UTIL_OC_BIN} adm must-gather --dest-dir=must-gather-metrics --image="${image}"

    # Create the tarball file removing the image name from the path of must-gather
    test ! -d must-gather-metrics/*/monitoring/ && {
        os_log_info "${msg_prefix} ERROR: must-gather not found, task collect_metrics done."
        return
    }

    os_log_info "${msg_prefix} Packing must-gather-metrics..."
    cp -v must-gather-metrics/timestamp must-gather-metrics/event-filter.html must-gather-metrics/*/monitoring/
    tar cfJ artifacts_must-gather-metrics.tar.xz -C must-gather-metrics/*/ monitoring/

    os_log_info "${msg_prefix} finished!"
}

# Run Plugin for Collecor. The Collector plugin is the last one executed on the
# cluster. It will collect custom files used on the Validation environment, at the
# end it will generate a tarbal file to submit the raw results to Sonobuoy.
run_plugin_collector() {
    os_log_info "[executor][PluginID#${PLUGIN_ID}] Starting Artifacts Collector"

    pushd "${RESULTS_DIR}" || true

    # Collecting must-gather
    send_test_progress "status=running=collecting must-gather";
    collect_must_gather || true

    # Experimental: Collect performance data
    # running after must-gather to prevent impacting in etcd logs when testing etcdfio.
    send_test_progress "status=running=collecting performance data";
    collect_performance || true

    # Experimental: Collect metrics
    send_test_progress "status=running=collecting metrics";
    collect_metrics || true

    # Creating Result file used to publish to sonobuoy. (last step)
    send_test_progress "status=running=saving artifacts";

    os_log_info "[executor][PluginID#${PLUGIN_ID}] Packing all results..."
    ls -sh ./artifacts_*
    tar cfz raw-results.tar.gz ./artifacts_*

    openshift-tests-plugin exec progress-msg --message "status=done";
    popd || true;
}

run_plugin_collector
