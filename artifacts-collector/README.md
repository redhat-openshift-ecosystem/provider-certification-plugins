# artifacts-collector plugin

Collector plugin/step is the final step of the default conformance workflow
executed by OPCT.

The step collects artifacts such as:

- e2e metadata executed by openshift-tests for previous steps - sent to the collector pod as a artifact server, saved with prefix  `artifacts_e2e-*`
- must-gather: used as a baseline to evaluate cluster information, and etcd performance during the conformance tests. Must-gather is the first data collected—running before performance tests—so our report won’t be impacted by non-e2e workloads.
- [camgi](https://github.com/elmiko/camgi.rs) report: generates camgi report if it is available in the running architecture
- run etcd FIO tool: to evaluate disk one-off performance of control plane nodes, and sample of compute/worker nodes
- kube-burner: run standard profiles to execute performance tests, collecting metrics and data to local index

## Prerequisites

- Download latest version of opct

### Build your custom image
Build and push (from the root directory):

```sh
make build-plugin-collector PLATFORMS=linux/amd64 COMMAND=push
```

## Usage

### Run individual collectors - kube-burner

It's possible to run individual collector by customizing the plugin manifest.

The kube-burner manifest file `manifests/kube-burner-only.yaml` enforce flags
to prevent collecting standard data, running only kube-burner in the target cluster.

To run the standalone plugin, you can use the wrapped API of Sonobuoy including OPCT:

> Update the `image` in the podSpec manifest file `manifests/kube-burner-only.yaml`

- Run
```bash
./opct sonobuoy run -p ./artifacts-collector/manifests/kube-burner-only.yaml \
    --dns-namespace=openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default
```

- Follow the execution or read the logs:

```sh
./opct sonobuoy status

# or read the logs

oc logs -l plugin-name=99-openshift-artifacts-collector -n sonobuoy
```

- When completed, retrieve the results:

```sh
./opct sonobuoy retrieve
```

- Then explore the performance data:


- When completed, retrieve the results:

```sh
$ tar xfz -C results/ 202502062032_sonobuoy_4afa09f6-24e1-4909-b9d2-7c158d604b02.tar.gz

$ ls -sh results/plugins/99-openshift-artifacts-collector/results/global/
total 424K
 52K artifacts_kube-burner_cluster-density-v2.log   52K artifacts_kube-burner_node-density-cni.log   52K artifacts_kube-burner_node-density.log  268K artifacts_kube-burner.tar.gz
```
