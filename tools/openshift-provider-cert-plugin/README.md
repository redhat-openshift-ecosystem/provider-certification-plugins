# OpenShift Tests Provider Certification Plugin


[`sonobuoy`][sonobuoy] plugin to run OpenShift tests on Provider Certification program.

This plugin uses [`openshift-tests` tool][openshift-tests], OpenShift implementation for [e2e-test-framework][e2e-test-framework],
to generate and run the tests used to run the provider certification.

## Dependencies

- podman
- CI registry credentials to build [`openshift-tests` container][openshift-tests-dockerfile].

## Requirements

Hardware:
- minimum for certification namespace*: 8 GiB, 4 vCPU
- cluster/control plane nodes: 3x 16 GiB, 4 vCPU
- cluster/compute nodes: ${TBD}x 16 GiB, 4 vCPU
- the control plane nodes (mainly etcd leader) needs consistent IOPS of minimum of 600 when running the tests

*As we run several disruption tests, it's highly recommended to run the certification in an dedicated node with proper scheduler tolerations. Please see the section below to setup an dedicated node.

| Node Role | Count | vCPU (rec*) | RAM (rec*) | vCPU (min) | RAM (min) |
| -- | -- | -- | -- | -- | -- |
| control plane | 3 | 4 | 16 GiB | -- | -- |
| compute | 3 |  4 | 16 GiB | 4 | 16 GiB |

*recommended sizing when running the default installation. It's recommended to
run in the dedicated nodes to avoid disruptions. Read the topic below for more details.

### Dedicated test environment (recommended)

Sometimes when the compute nodes has small size, it is recommended to
run the certification environment in one dedicated node to avoid
disruption on the test scheduler, otherwise the concurrency between
resources scheduled on the cluster, e2e-test manager (aka openshift-tests-plugin),
and other stacks like monitoring can disrupt the test environment, getting
unexpected results, like eviction of plugis or certification server (sonobuoy pod).

When it happened you can see the events on the namespace `sonobuoy`, and missing
plugin's pods, the sonobuoy sometimes does not detect it[1] and the certification
environment will run until the timeout, with expected failures.

[1] [SPLAT-524](https://issues.redhat.com/browse/SPLAT-524)

If you would like to isolate the test environment workload to an
specific node, you can do it by adjusting the plugin `podSpec`.

The cluster size also can be adjusted to smaller compute nodes (minimum) when running one dedicated
node to openshift-tests, the matrix can be updated:

| Node Role | Count | vCPU (rec*) | RAM (rec*) | vCPU (min) | RAM (min) |
| -- | -- | -- | -- | -- | -- |
| control plane | 3 | 4 | 16 GiB | -- | -- |
| compute | 3 |  4 | 16 GiB | 2 | 8 GiB |
| openshift-tests | 1 | 4 | 8 GiB | 2 | 8 GiB |

*recommended size

Steps to run dedicated environment:
- Choose one node with at least 8GiB of RAM and 4 vCPU
- Set the node-label to `tests`
- Taint the node taint to `NoSchedule`
```bash
oc label node <node_name> node-role.kubernetes.io/tests=""
oc taint node <node_name> node-role.kubernetes.io/tests="":NoSchedule
```
- Or set add on a **new MachineSet** (`.spec.template.spec`):
```yaml
      metadata:
        labels:
          openshift-tests: "true"
          node-role.kubernetes.io/tests: ""
      taints:
        - key: node-role.kubernetes.io/tests
          effect: NoSchedule
```
- Adjust the `podSpec` with `tolerations`:
```yaml
tolerations:
    - key: "node-role.kubernetes.io/tests"
      operator: "Equal"
      value: ""
      effect: "NoSchedule"
affinity:
    nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
            - key: node-role.kubernetes.io/worker
              operator: In
              values:
                - ""
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 99
        preference:
            matchExpressions:
            - key: node-role.kubernetes.io/tests
              operator: In
              values:
              - ""
        - weight: 1
        preference:
            matchExpressions:
            - key: node-role.kubernetes.io/worker
            operator: In
            values:
            - ""
```

- run the test environment

### Runtime Observations

**Tested scenario #1**:
- Provider AWS cluster: 3x Control Plane m6i.xlarge, 3x Compute m6i.xlarge, 1x test node m6i.xlarge
- m6i.xlarge spec: 16.0 GiB, 4 vCPUs, Network Up to 12.5 Gigabit, EBS 120 GiB Max IOPS 3k

Certification environment (dedicated node):
- Node insights: CPU bound. Peaks of 80% (avg 60%), and LA 2.5 in 4 vCPU node
- memory used the maximum of 4 GiB (node) and 3.3 CPU
- sonobuoy namespace had peak of 3.5 GiB RAM usage; 3 CPU, network: ~6 MiBps (IO), and 8kpps (IO)

Control Plane nodes:
- the LA of etcd leader will be higher than threshold in nodes with 4 vCPU. Constant 5 with peaks of ~6.90
- control plane IOPS (EBS metric) had peaks of 450, and consitent in 300 between openshift/conformance suite in all master nodes
- etcd peers increased 2.5x the round trip time (from ~12.6) to ~25ms, with peak of 40ms on leader
- etcd leader had peak of 50ms on fsync, other nodes increased 2x (7ms to 14ms)

Compute node:
- Overall low resource comsuption. Peaks: 6% disk IO and 50% saturation; 40% CPU Utilisation and 1.3 Load; 45-55% of Memory utilisation

Results (~2 hrs):
```log
Mon May 23 16:40:01 -03 2022> Global Status: post-processing
JOB_NAME                       | STATUS     | RESULTS    | PROGRESS                  | MESSAGE                                           
openshift-kube-conformance     | complete   |            | 345/345 (1 failures)      | waiting post-processor...                         
openshift-provider-cert-level1 | complete   |            | 3239/3239 (26 failures)   | waiting post-processor... 
....
Mon May 23 16:40:01 -03 2022 #> Jobs has finished.
...
Mon May 23 16:44:42 -03 2022 #> Use the 'results' option to check the certification tests summary.
...
Run Details:
API Server version: v1.23.5+9ce5071
Node health: 7/7 (100%)
Pods health: 267/267 (100%)

Plugin: openshift-kube-conformance
Status: failed
Total: 476
Passed: 473
Failed: 3
Skipped: 0

Plugin: openshift-provider-cert-level1
Status: failed
Total: 3386
Passed: 1416
Failed: 45
Skipped: 1925
```

**Tested scenario #2**:
- Provider AWS cluster: 3x Control Plane m6i.xlarge, 3x Compute m6i.large, 1x test node m6i.large
- [Machine spec](https://instances.vantage.sh/?compare_on=true&selected=m6i.xlarge,m6i.large,m6i.4xlarge), EBS 120 GiB Max IOPS 3k


**Other results (Benchmark)**
| # | Scenario > Size | Total Time | results T/P/F/S** | Note |
| -- | -- | -- | -- | -- |
| - | 3x/3x > m6i.xl/m6i.(l\|xl) | N/A | N/A | Most of Low&&medium size clusters crashed w/o dedicated node for tests. |
| 0 | 3x/9x > m6i.xl/m6i.4xl | ~1h:56m | 3383/1414/44/1925 | Large cluster after fixes on pipefail handling |
| 1 | 3x/3x/1x > m6i.xl/m6i.xl/m6i.xl | ~1h:59m | 3386/1416/45/1925 | Medium cluster, isolated test environment* |
| 2 | 3x/3x/1x > m6i.xl/m6i.l/m6i.l | ~2h:01m | 3387/1421/41/1925 | AWS IPI default size, isolated test environment*; High IOPS on compute (~1.2k) |

*One machineSet was created to launch one NonScheduled node to run the Certification
environment (aggregator+plugins) to avoid disruptions that had frequently impacted the execution.

**Total/Passed/Failed/Skipped

## Usage

### Build

The build process does:
- clone origin repository
- build the openshift-tests container image
- run the tests generator script
- build a container image for plugin (based on openshift-tests)

To run the process:

```bash
make
```

### Run the tests generator/parser

Manually generate tests for each Certification Level:

> That step is already triggered by build image.

```bash
mak generate-openshift-tests
```

### Run the plugin

To run the Provider Certification plugins you need to run the tool.

To run the plugin directly in development environment, you can trigger it
by following those steps:

1. Add privileged SCC policy for serviceAccounts

```
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts
```

2. Edit the plugin manifest (`plugin.yaml`) with your image and test file

3. run the sonobuoy plugin
> Adjust the test file name on plugin's env var `CUSTOM_TEST_FILE`
```bash
sonobuoy run \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin plugin.yaml
    --plugin-env openshift-tests-provider-cert.CUSTOM_TEST_FILE="./tests/level1.txt"
```

4. Check the execution:
```bash
sonobuoy status
```

5. Retrieve the results
```bash
result_file=$(sonobuoy retrieve)
mkdir -p results
tar -xfz ${result_file} -C results
```

6. Destroy the environment
```bash
sonobuoy delete --wait
```

## Development: create the test filter by SIG

To include tests for Certification Level, a collector function
should be created. The generation process creates a container image based on the `openshift-tests` image, including the plugin scripts and an level-based text files with **the tests by Level**. To update the tests you need to build a new image.

> TODO(release): define the frequency to build this image

Steps to create the filter by SIG and Certification Level:

1. Create the functions to extract the test names for the SIG. Example for `sig-cli` collecting only for Certification `Level1`, considering that there's
no tests for upper levels:

`hack/generate-tests-tiers.sh`
```bash
# SIG=sig-cli
level1_sig_cli() {
    run_openshift_tests "all" |grep -E '\[sig-cli\]' \
        | tee -a "${tests_level1}"
}

level2_sig_cli() {
    :
}

level3_sig_cli() {
    :
}
```

2. Create the collector function
```bash
sig_cli() {
    level1_sig_cli
    level2_sig_cli
    level3_sig_cli
}
```

3. Add the new collector function to `collector`:
```diff
collector() {
    sig_storage >/dev/null
+   sig_cli     >/dev/null
}
collector
```

4. Generate the tests
5. Build a new image
6. Run the plugin

### Debug | Creating metadata for tests

[parser.md](./parser.md)


[sonobuoy]:https://github.com/vmware-tanzu/sonobuoy
[openshift-tests]:https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests
[e2e-test-framework]:https://github.com/kubernetes-sigs/e2e-framework
[openshift-tests-dockerfile]:https://github.com/openshift/origin/blob/master/images/tests/Dockerfile.rhel
