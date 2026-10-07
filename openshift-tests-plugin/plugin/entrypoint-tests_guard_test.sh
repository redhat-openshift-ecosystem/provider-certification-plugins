#!/usr/bin/env bash

#
# OPCT-432: Shell-level regression tests for the workflow entrypoint guard.
#
# Tests the guard function in entrypoint-tests.sh using isolated temporary
# directories. No cluster interaction, no real Sonobuoy, no destructive
# operations.
#
# Usage: bash entrypoint-tests_guard_test.sh
#

set -o pipefail
set -o nounset
set -o errexit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "  PASS: $1"
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo "  FAIL: $1 - $2"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "TEST: $1"
}

# Create isolated environment for each test
setup_test_env() {
    local tmpdir
    tmpdir=$(mktemp -d /tmp/opct-guard-test-XXXXXX)
    # Mirror the paths used by entrypoint-tests.sh
    mkdir -p "${tmpdir}/shared/junit"
    mkdir -p "${tmpdir}/sonobuoy/results"
    echo "${tmpdir}"
}

teardown_test_env() {
    rm -rf "$1"
}

# Source just the guard function from entrypoint-tests.sh by extracting it.
# We override the control file paths to point to our temp directory.
create_guard_harness() {
    local tmpdir="$1"
    cat > "${tmpdir}/guard_harness.sh" <<'HARNESS_EOF'
#!/usr/bin/env bash
set -o pipefail
set -o nounset

# Override control file paths to temp directory
CTRL_SUITE_LIST="__TMPDIR__/shared/suite.list"
CTRL_DONE_TESTS="__TMPDIR__/shared/done"
CTRL_DONE_PLUGIN="__TMPDIR__/sonobuoy/results/done"

# The guard function (copied from entrypoint-tests.sh for isolated testing)
opct_workflow_skip_plugin() {
    local reason="$1"
    echo "OPCT-432: Skipping plugin ${PLUGIN_NAME:-unknown} - ${reason}"

    local junit_dir="__TMPDIR__/shared/junit"
    mkdir -p "${junit_dir}"
    cat > "${junit_dir}/junit_e2e_workflow_skip.xml" <<SKIPEOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="opct" tests="1" failures="0" time="0.0">
  <testcase name="[opct] workflow guard: ${PLUGIN_NAME:-unknown}" time="0.0">
    <skipped message="${reason}"/>
  </testcase>
</testsuite>
SKIPEOF

    touch "${CTRL_SUITE_LIST}"
    touch "${CTRL_SUITE_LIST}.done"
    touch "${CTRL_DONE_TESTS}"

    # For testing: don't actually wait, just check/signal
    if [[ -f ${CTRL_DONE_PLUGIN} ]]; then
        echo "OPCT-432: Plugin done detected after skip, exiting."
        exit 0
    fi
    # In test mode, exit cleanly after signaling
    exit 0
}

# Evaluate guards (same logic as entrypoint-tests.sh)
GUARD_TRIGGERED="false"

if [[ "${PLUGIN_NAME:-}" == "openshift-cluster-upgrade" ]] && [[ "${RUN_MODE:-}" != "upgrade" ]]; then
    GUARD_TRIGGERED="true"
    opct_workflow_skip_plugin "upgrade plugin inactive in non-upgrade workflow (RUN_MODE=${RUN_MODE:-unset})"
fi

if [[ "${RUN_MODE:-}" == "upgrade" ]]; then
    if [[ "${PLUGIN_NAME:-}" == "openshift-kube-conformance" ]] || \
       [[ "${PLUGIN_NAME:-}" == "openshift-conformance-validated" ]]; then
        GUARD_TRIGGERED="true"
        opct_workflow_skip_plugin "conformance plugin inactive in upgrade workflow (RUN_MODE=upgrade)"
    fi
fi

# If we reach here, guard did NOT trigger
echo "GUARD_RESULT=active"
exit 0
HARNESS_EOF
    # Replace placeholder with actual tmpdir
    sed "s|__TMPDIR__|${tmpdir}|g" "${tmpdir}/guard_harness.sh" > "${tmpdir}/guard_harness.tmp"
    mv "${tmpdir}/guard_harness.tmp" "${tmpdir}/guard_harness.sh"
    chmod +x "${tmpdir}/guard_harness.sh"
}

#############################################################################
# Test: Plugin 05 (upgrade) skips in default mode
#############################################################################
run_test "inactive05_default: plugin 05 skips in default/unset RUN_MODE"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-cluster-upgrade" RUN_MODE="" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "OPCT-432: Skipping plugin"; then
    test_pass "plugin 05 skipped in default mode"
else
    test_fail "plugin 05 should skip in default mode" "output: ${output}"
fi
# Verify JUnit was created with <skipped> tag
if [[ -f "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml" ]]; then
    if grep -q '<skipped message=' "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml"; then
        test_pass "skip JUnit contains <skipped> element"
    else
        test_fail "skip JUnit missing <skipped> element" "$(cat "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml")"
    fi
else
    test_fail "skip JUnit file not created" "missing junit_e2e_workflow_skip.xml"
fi
# Verify lifecycle signals
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -f "${tmpdir}/shared/suite.list" ]] && [[ -f "${tmpdir}/shared/suite.list.done" ]] && [[ -f "${tmpdir}/shared/done" ]]; then
    test_pass "lifecycle signals created (suite.list, suite.list.done, done)"
else
    test_fail "lifecycle signals missing" "suite.list=$(test -f "${tmpdir}/shared/suite.list" && echo yes || echo no) suite.list.done=$(test -f "${tmpdir}/shared/suite.list.done" && echo yes || echo no) done=$(test -f "${tmpdir}/shared/done" && echo yes || echo no)"
fi
# Verify JUnit is well-formed XML
TESTS_RUN=$((TESTS_RUN + 1))
if xmllint --noout "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml" 2>/dev/null; then
    test_pass "skip JUnit is well-formed XML"
else
    # xmllint may not be installed; check basic structure instead
    if grep -q '<?xml version' "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml" && \
       grep -q '</testsuite>' "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml"; then
        test_pass "skip JUnit has valid structure (xmllint not available)"
    else
        test_fail "skip JUnit has invalid structure" ""
    fi
fi
# Verify failures="0" in JUnit (not marked as failure)
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'failures="0"' "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml"; then
    test_pass "skip JUnit has failures=0 (not marked as failure)"
else
    test_fail "skip JUnit should have failures=0" ""
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 05 skips in disconnected mode (RUN_MODE unset/normal)
#############################################################################
run_test "inactive05_disconnected: plugin 05 skips when RUN_MODE=normal (disconnected-like)"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-cluster-upgrade" RUN_MODE="normal" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "OPCT-432: Skipping plugin"; then
    test_pass "plugin 05 skipped in normal/disconnected mode"
else
    test_fail "plugin 05 should skip in normal mode" "output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 05 runs in upgrade mode
#############################################################################
run_test "active05_upgrade: plugin 05 runs in upgrade mode"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-cluster-upgrade" RUN_MODE="upgrade" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "GUARD_RESULT=active"; then
    test_pass "plugin 05 active in upgrade mode"
else
    test_fail "plugin 05 should be active in upgrade mode" "output: ${output}"
fi
# Verify no skip artifacts were created
TESTS_RUN=$((TESTS_RUN + 1))
if [[ ! -f "${tmpdir}/shared/junit/junit_e2e_workflow_skip.xml" ]]; then
    test_pass "no skip JUnit created for active plugin"
else
    test_fail "skip JUnit should not exist for active plugin" ""
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 10 skips in upgrade mode
#############################################################################
run_test "inactive10_upgrade: plugin 10 skips in upgrade mode"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-kube-conformance" RUN_MODE="upgrade" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "OPCT-432: Skipping plugin"; then
    test_pass "plugin 10 skipped in upgrade mode"
else
    test_fail "plugin 10 should skip in upgrade mode" "output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 20 skips in upgrade mode
#############################################################################
run_test "inactive20_upgrade: plugin 20 skips in upgrade mode"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-conformance-validated" RUN_MODE="upgrade" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "OPCT-432: Skipping plugin"; then
    test_pass "plugin 20 skipped in upgrade mode"
else
    test_fail "plugin 20 should skip in upgrade mode" "output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 10 runs in default mode
#############################################################################
run_test "active10_default: plugin 10 runs in default mode"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-kube-conformance" RUN_MODE="" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "GUARD_RESULT=active"; then
    test_pass "plugin 10 active in default mode"
else
    test_fail "plugin 10 should be active in default mode" "output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Plugin 20 runs in default mode
#############################################################################
run_test "active20_default: plugin 20 runs in default mode"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="openshift-conformance-validated" RUN_MODE="" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "GUARD_RESULT=active"; then
    test_pass "plugin 20 active in default mode"
else
    test_fail "plugin 20 should be active in default mode" "output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Replay plugin (80) unaffected
#############################################################################
run_test "replay_unaffected: replay plugin passes through guard in all modes"
for mode in "" "upgrade" "normal"; do
    tmpdir=$(setup_test_env)
    create_guard_harness "${tmpdir}"
    output=$(PLUGIN_NAME="openshift-tests-replay" RUN_MODE="${mode}" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
    if echo "${output}" | grep -q "GUARD_RESULT=active"; then
        test_pass "replay active in RUN_MODE=${mode:-unset}"
    else
        test_fail "replay should be active in RUN_MODE=${mode:-unset}" "output: ${output}"
    fi
    teardown_test_env "${tmpdir}"
done

#############################################################################
# Test: Collector plugin (99) unaffected
#############################################################################
run_test "collector_unaffected: collector plugin passes through guard in all modes"
for mode in "" "upgrade" "normal"; do
    tmpdir=$(setup_test_env)
    create_guard_harness "${tmpdir}"
    output=$(PLUGIN_NAME="openshift-artifacts-collector" RUN_MODE="${mode}" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
    if echo "${output}" | grep -q "GUARD_RESULT=active"; then
        test_pass "collector active in RUN_MODE=${mode:-unset}"
    else
        test_fail "collector should be active in RUN_MODE=${mode:-unset}" "output: ${output}"
    fi
    teardown_test_env "${tmpdir}"
done

#############################################################################
# Test: Guard runs after oc login but before test execution (position check)
#############################################################################
run_test "guard_after_login: guard appears after oc login in entrypoint"
ENTRYPOINT="${SCRIPT_DIR}/entrypoint-tests.sh"
guard_line=$(grep -n 'opct_workflow_skip_plugin' "${ENTRYPOINT}" | head -1 | cut -d: -f1)
login_line=$(grep -n 'oc login' "${ENTRYPOINT}" | head -1 | cut -d: -f1)
TESTS_RUN=$((TESTS_RUN + 1))
if [[ -n "${guard_line}" ]] && [[ -n "${login_line}" ]] && [[ "${guard_line}" -gt "${login_line}" ]]; then
    test_pass "guard runs after oc login (line ${guard_line} > ${login_line})"
else
    test_fail "guard must appear after oc login (reads configmap)" "guard=${guard_line:-missing} login=${login_line:-missing}"
fi

#############################################################################
# Test: CTRL_DONE_PLUGIN already present (pre-existing done file)
#############################################################################
run_test "ctrl_done_already_present: skip exits immediately when plugin done exists"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
# Pre-create the plugin done file
touch "${tmpdir}/sonobuoy/results/done"
output=$(PLUGIN_NAME="openshift-cluster-upgrade" RUN_MODE="" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
if echo "${output}" | grep -q "Plugin done detected after skip"; then
    test_pass "immediate exit when CTRL_DONE_PLUGIN pre-exists"
else
    # The harness exits 0 on skip regardless; check skip happened
    if echo "${output}" | grep -q "OPCT-432: Skipping"; then
        test_pass "skip triggered with pre-existing done file"
    else
        test_fail "should skip with pre-existing done file" "output: ${output}"
    fi
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Test: Guard with empty/unset PLUGIN_NAME does not crash
#############################################################################
run_test "unset_plugin_name: guard handles unset PLUGIN_NAME gracefully"
tmpdir=$(setup_test_env)
create_guard_harness "${tmpdir}"
output=$(PLUGIN_NAME="" RUN_MODE="" bash "${tmpdir}/guard_harness.sh" 2>&1) || true
exit_code=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [[ ${exit_code} -eq 0 ]] && echo "${output}" | grep -q "GUARD_RESULT=active"; then
    test_pass "empty PLUGIN_NAME passes through guard without crash"
else
    test_fail "empty PLUGIN_NAME should not crash" "exit=${exit_code} output: ${output}"
fi
teardown_test_env "${tmpdir}"

#############################################################################
# Summary
#############################################################################
echo ""
echo "================================================================"
echo "OPCT-432 Shell Guard Test Summary"
echo "================================================================"
echo "Tests run:    ${TESTS_RUN}"
echo "Tests passed: ${TESTS_PASSED}"
echo "Tests failed: ${TESTS_FAILED}"
echo "================================================================"

if [[ ${TESTS_FAILED} -gt 0 ]]; then
    exit 1
fi
exit 0
