# Running openshift-tests-provider-cert plugin in dedicated environment

By default the Conformance test environment will run in the minimal nodes correctly, but sometimes it needs a dedicated environment when the e2e tests are disrupting the node which is running the sonobuoy components (server and plugins). The steps below share how to create a dedicated node to run the test environment.

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
