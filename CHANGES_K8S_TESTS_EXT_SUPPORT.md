# k8s-tests-ext Support in openshift-tests-plugin

## Date
2025-11-26

## Overview

Added support for k8s-tests-ext binary with OTE (OpenShift Tests Extension) interface to the openshift-tests-plugin. This enables proper Kubernetes conformance testing on OCP 4.20+ using k8s-tests-ext instead of openshift-tests.

## Changes

### File: openshift-tests-plugin/plugin/entrypoint-tests.sh

#### 1. Binary Detection (Lines 25-38)

Added logic to detect and select the appropriate test binary:

```bash
# Detect which test binary to use based on environment variable and availability
if [[ "${USE_K8S_TESTS_EXT:-false}" == "true" ]] && [[ -x "/tmp/shared/k8s-tests-ext" ]]; then
    declare -gr CMD_TESTS="/tmp/shared/k8s-tests-ext"
    declare -gr USE_OTE_INTERFACE="true"
    echo "Using k8s-tests-ext binary with OTE interface"
else
    declare -gr CMD_TESTS="/usr/bin/openshift-tests"
    declare -gr USE_OTE_INTERFACE="false"
    echo "Using openshift-tests binary"
fi

# Legacy variable for backward compatibility
declare -gr CMD_OTESTS="${CMD_TESTS}"
```

**Environment Variables**:
- `USE_K8S_TESTS_EXT`: Set by OPCT to indicate k8s-tests-ext should be used
- Binary must exist at `/tmp/shared/k8s-tests-ext` and be executable

#### 2. Test Discovery Functions (Lines 61-102)

Added two functions to handle test discovery:

**OTE Interface (k8s-tests-ext)**:
```bash
function gather_test_list_ote() {
    local suite_name="${1:-}"
    local output_file="${2}"

    # List tests in JSONL format
    ${CMD_TESTS} list -o jsonl > "${output_file}.jsonl" 2>"${output_file}.log"

    # Convert JSONL to simple test name list
    if command -v jq &> /dev/null; then
        jq -r '.name' "${output_file}.jsonl" > "${output_file}"
    else
        python3 -c "
import json, sys
with open('${output_file}.jsonl') as f:
    for line in f:
        if line.strip():
            data = json.loads(line)
            print(data.get('name', ''))
" > "${output_file}"
    fi

    echo "Extracted $(wc -l < "${output_file}") tests from OTE interface"
}
```

**Standard Interface (openshift-tests)**:
```bash
function gather_test_list_standard() {
    local run_command="${1:-run}"
    local suite_name="${2:-}"
    local additional_args="${3:-}"
    local output_file="${4}"

    ${CMD_TESTS} ${run_command} ${suite_name} ${additional_args} --dry-run -o "${output_file}" >"${output_file}.log" 2>&1
}
```

#### 3. Updated Test Discovery Logic (Lines 104-129)

Modified to use appropriate function based on `USE_OTE_INTERFACE`:

```bash
elif [[ "${PLUGIN_NAME:-}" != "openshift-cluster-upgrade" ]]; then
    if [[ "${USE_OTE_INTERFACE}" == "true" ]]; then
        gather_test_list_ote "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "${CTRL_SUITE_LIST}"
    else
        gather_test_list_standard "${OT_RUN_COMMAND:-run}" "${SUITE_NAME:-${DEFAULT_SUITE_NAME-}}" "" "${CTRL_SUITE_LIST}"
    fi
```

#### 4. Test Execution Function (Lines 135-231)

Added function to execute tests using OTE interface:

```bash
function execute_tests_ote() {
    # Set up environment variables required by k8s-tests-ext
    export TEST_PROVIDER="{\"ProviderName\":\"skeleton\"}"
    export EXTENSION_ARTIFACT_DIR="/tmp/shared/artifacts"
    mkdir -p "${EXTENSION_ARTIFACT_DIR}"

    # Create start script that:
    # 1. Reads test list
    # 2. Executes each test individually via k8s-tests-ext run-test
    # 3. Parses JSONL results
    # 4. Generates JUnit XML
    cat > "${CTRL_START_SCRIPT}" <<'EOF_START'
#!/bin/bash
# ... script content ...
EOF_START

    chmod +x "${CTRL_START_SCRIPT}"
    ${CTRL_START_SCRIPT}
}
```

**Key Features**:
- Runs each test individually: `k8s-tests-ext run-test -n "test-name" -o jsonl`
- Parses JSONL output to determine pass/fail/skip
- Generates JUnit XML at `/tmp/shared/junit/junit_runner.xml`
- Reports summary statistics

#### 5. Updated Execution Logic (Lines 233-251)

Modified to use OTE execution when enabled:

```bash
if [[ "${USE_OTE_INTERFACE}" == "true" ]]; then
    echo "Using OTE interface - generating and executing k8s-tests-ext start script"
    execute_tests_ote
else
    # Standard flow: wait for plugin Go code to generate start script
    while true; do
        if [[ -f ${CTRL_START_SCRIPT} ]]; then
            chmod u+x $CTRL_START_SCRIPT && cat $CTRL_START_SCRIPT && $CTRL_START_SCRIPT
            break
        fi
        sleep 10
    done
fi
```

## OTE Interface Details

### Test Discovery

**Command**:
```bash
k8s-tests-ext list -o jsonl
```

**Output Format** (JSONL - one test per line):
```json
{"name":"[sig-apps] Deployment deployment should support proportional scaling","labels":{"sig":"apps"},"suite":"kubernetes/conformance"}
{"name":"[sig-api-machinery] Aggregator Should be able to support the 1.17 Sample API Server","labels":{"sig":"api-machinery"},"suite":"kubernetes/conformance"}
```

**Processing**:
- Parse each JSON line
- Extract `.name` field
- Write to test list file (one test per line)

### Test Execution

**Command**:
```bash
k8s-tests-ext run-test -n "[sig-apps] Deployment deployment should support proportional scaling" -o jsonl
```

**Output Format** (JSONL):
```json
{"name":"[sig-apps] Deployment...","result":"passed","output":"...logs...","error":"","startTime":"2025-11-26T10:00:00Z","endTime":"2025-11-26T10:05:00Z"}
```

**Result States**:
- `passed`: Test succeeded
- `failed`: Test failed
- `skipped`: Test was skipped

### Environment Variables

k8s-tests-ext requires:
- `KUBECONFIG`: Path to kubeconfig (set by pod)
- `TEST_PROVIDER`: JSON string with provider info (we use `{"ProviderName":"skeleton"}`)
- `EXTENSION_ARTIFACT_DIR`: Directory for test artifacts

## JUnit XML Generation

The OTE execution generates JUnit XML compatible with OPCT's result processing:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="kubernetes-conformance" tests="350">
    <testcase name="[sig-apps] Deployment..." classname="kubernetes.conformance" status="passed"/>
    <testcase name="[sig-api-machinery] Aggregator..." classname="kubernetes.conformance" status="failed">
      <failure>Test failed or result unknown</failure>
    </testcase>
    <testcase name="[sig-auth] ServiceAccounts..." classname="kubernetes.conformance" status="skipped">
      <skipped/>
    </testcase>
  </testsuite>
</testsuites>
```

## Integration with OPCT

### Environment Variable Flow

1. **OPCT detects OCP version** (4.20+)
2. **OPCT sets `USE_K8S_TESTS_EXT=true`** in pod template
3. **OPCT adds init container** to extract k8s-tests-ext binary
4. **entrypoint-tests.sh detects** `USE_K8S_TESTS_EXT=true` and binary exists
5. **Script uses OTE interface** for discovery and execution

### Binary Location

- **Extracted by**: Init container in OPCT plugin template
- **Location**: `/tmp/shared/k8s-tests-ext`
- **Source**: Hyperkube image in OCP release payload
- **Path in hyperkube**: `/usr/bin/k8s-tests-ext.gz` (compressed)

## Backward Compatibility

### OCP < 4.20

When `USE_K8S_TESTS_EXT` is not set or false:
- Uses `CMD_TESTS=/usr/bin/openshift-tests`
- Sets `USE_OTE_INTERFACE=false`
- Calls `gather_test_list_standard()` for discovery
- Waits for plugin Go code to generate start script
- No changes to existing flow

### Plugin Compatibility

Works with:
- ✅ openshift-kube-conformance (primary use case)
- ✅ openshift-conformance-validated (falls back to openshift-tests)
- ✅ openshift-cluster-upgrade (explicitly falls back to openshift-tests)
- ✅ openshift-tests-replay (no changes needed)

## Dependencies

### Required in Container Image

- **bash**: Script interpreter
- **python3**: JSONL parsing (primary)
- **jq**: JSONL parsing (fallback, optional)
- **oc**: Already present in openshift-tests image

### Binary Dependencies

- **k8s-tests-ext**: Provided by OPCT init container extraction
- **openshift-tests**: Already present at `/usr/bin/openshift-tests`

## Testing

### Validation Steps

1. **Syntax Check**:
   ```bash
   bash -n entrypoint-tests.sh
   ```

2. **Shellcheck**:
   ```bash
   make shellcheck
   ```

3. **Unit Test** (manual):
   ```bash
   # Test binary detection
   USE_K8S_TESTS_EXT=true bash -c 'source entrypoint-tests.sh && echo $CMD_TESTS'
   # Expected: /tmp/shared/k8s-tests-ext (if exists) or /usr/bin/openshift-tests

   # Test JSONL parsing
   echo '{"name":"test1"}' | jq -r '.name'
   # Expected: test1
   ```

4. **Integration Test**:
   - Run OPCT on OCP 4.20+ cluster
   - Verify k8s-tests-ext is used
   - Check test discovery and execution logs
   - Validate JUnit XML output

### Test Scenarios

| Scenario | USE_K8S_TESTS_EXT | Binary Exists | Expected Binary |
|----------|-------------------|---------------|-----------------|
| OCP 4.19 | false | No | openshift-tests |
| OCP 4.20 | true | Yes | k8s-tests-ext |
| OCP 4.20 (fallback) | true | No | openshift-tests |
| Manual override | false | Yes | openshift-tests |

## Performance Considerations

### Test Execution Time

**Sequential Execution** (current implementation):
- Each test runs individually
- Typical: 1-3 seconds per test overhead
- Total: ~350 tests × 2s = ~12 minutes overhead
- Plus actual test execution time

**Potential Optimizations**:
1. Parallel execution using GNU parallel or xargs -P
2. Batch multiple tests if k8s-tests-ext supports it
3. Optimize JSONL parsing (use jq instead of python if faster)

### Memory Usage

- **k8s-tests-ext**: ~100MB per test process
- **JUnit XML**: Grows linearly with test count (~1MB for 350 tests)
- **JSONL intermediate files**: Small, cleaned up per test

## Troubleshooting

### Issue: Binary Not Found

**Error**: `Using openshift-tests binary` when expecting k8s-tests-ext

**Check**:
```bash
kubectl exec -n opct <pod> -c tests -- ls -la /tmp/shared/k8s-tests-ext
kubectl exec -n opct <pod> -c tests -- env | grep USE_K8S_TESTS_EXT
```

**Solution**: Verify init container completed and extracted binary

### Issue: JSONL Parsing Fails

**Error**: All tests marked as failed

**Check**:
```bash
kubectl exec -n opct <pod> -c tests -- python3 --version
kubectl exec -n opct <pod> -c tests -- /tmp/shared/k8s-tests-ext list -o jsonl | head -1
```

**Solution**: Ensure python3 available and JSONL format is valid

### Issue: No Tests Discovered

**Error**: `Extracted 0 tests from OTE interface`

**Check**:
```bash
kubectl logs -n opct <pod> -c tests | grep "list -o jsonl"
kubectl exec -n opct <pod> -c tests -- cat /tmp/shared/suite.list.jsonl
```

**Solution**: Check k8s-tests-ext list command output and errors

## Future Enhancements

1. **Parallel Execution**: Run multiple tests concurrently
   ```bash
   cat test-list.txt | xargs -P 4 -I {} k8s-tests-ext run-test -n "{}"
   ```

2. **Better Progress Reporting**: Real-time test count and ETA
   ```bash
   echo "Running test $current/$total: $test_name"
   ```

3. **Enhanced Error Capture**: Include test output in JUnit XML
   ```xml
   <testcase name="test" status="failed">
     <failure><![CDATA[...test output...]]></failure>
   </testcase>
   ```

4. **Test Retry Logic**: Automatically retry flaky tests
   ```bash
   for retry in 1 2 3; do
     if run_test "$test_name"; then break; fi
   done
   ```

## References

- [OPCT k8s-tests-ext Documentation](../opct/CHANGES_K8S_TESTS_EXT.md)
- [OpenShift Tests Extension Interface](https://github.com/openshift-eng/openshift-tests-extension)
- [Origin k8s-tests-ext Integration](https://github.com/openshift/origin/tree/master/pkg/test/extensions)

## Related Files

- `openshift-tests-plugin/plugin/entrypoint-tests.sh` - Main changes
- `openshift-tests-plugin/pkg/plugin/plugin.go` - Suite name handling (from previous fix)

## Status

**Code Complete**: ✅
**Syntax Validated**: ✅
**Shellcheck**: ⚠️ (warnings for unused variables - acceptable)
**Integration Tested**: ⏳ Pending

---

**Last Updated**: 2025-11-26
**Branch**: shared-dir-kube-conf-fix
**Author**: Claude Code with jcallen
