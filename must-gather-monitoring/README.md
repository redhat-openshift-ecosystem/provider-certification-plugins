# must-gather-monitoring

The must-gather-monitoring collects metrics from monitoring
stack (Prometheus) on OpenShift/OKD.

The must-gather-monitoring container image is available in
the repository `quay.io/opct/must-gather-monitoring`.

OPCT runs the must-gather-monitoring in the collector plugin `99-openshift-artifacts-collector` (instance of `openshift-tests-provider-cert`).

You can find the tarball file with the metrics collected by OPCT plugin in the following path of OPCT result tarball:
`plugins/99-openshift-artifacts-collector/results/global/artifacts_must-gather-metrics.tar.xz`.

## Usage

### Exploring the metrics collected by OPCT

1. Retrieve OPCT results

```bash
./opct retrieve
```

1. Extract the metrics from archive

```bash
tar xfz opct_archive.tar.gz plugins/99-openshift-artifacts-collector/results/global/artifacts_must-gather-metrics.tar.xz
```

1. Extract the compressed metrics

```bash
mkdir metrics-gather;
tar xfJ plugins/99-openshift-artifacts-collector/results/global/artifacts_must-gather-metrics.tar.xz -C metrics-gather
```

1. Explore the metrics, each query are saved into a file:

```bash
$ ls metrics-gather/monitoring/prometheus/metrics/
query_range-api-kas-request-duration-p99.json.gz     query_range-etcd-disk-fsync-wal-duration-p10.json.gz  query_range-etcd-total-leader-elections-day.json.gz
query_range-api-kas-request-duration-p99.stderr      query_range-etcd-disk-fsync-wal-duration-p10.stderr   query_range-etcd-total-leader-elections-day.stderr

```

1. Explore the metrics data points

```bash
jq . $(zcat metrics-gather/monitoring/prometheus/metrics/query_range-api-kas-request-duration-p99.json.gz)
```

### Using as a standalone collector with must-gather

#### Default execution

```bash
oc adm must-gather --image=quay.io/opct/must-gather-monitoring:devel
```

#### Customizing variables

Use the following steps to run the must-gather directly replacing the default vars:

1. Create the config map with queries to collect:

```bash
cat << EOF > ./collect-metrics.env
GATHER_MONIT_START_DATE='6 hours ago'
GATHER_MONIT_QUERY_STEP='1m'
# API Request Duration by Verb - 99th Percentile [api-kas-request-duration-p99]
declare -A OPT_GATHER_QUERY_RANGE=( [api-kas-request-duration-p99]='histogram_quantile(0.99, sum(resource_verb:apiserver_request_duration_seconds_bucket:rate:5m{apiserver="kube-apiserver"}) by (verb, le))' )
EOF
```

2. Collect the metrics running must-gather

```bash
oc adm must-gather --image=quay.io/opct/must-gather-monitoring:devel -- /usr/bin/gather --use-cm "$ENV_POD_NAMESPACE"/must-gather-metrics
```

### Using as a standalone collector with sonobuoy plugin

- Run
```bash
./opct sonobuoy run  -p ./plugin.yaml --dns-namespace=openshift-dns --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default
```

- Review the execution

```bash
./opct sonobuoy status
oc get pods -n sonobuoy
oc logs -n sonobuoy -f -c plugin -l sonobuoy-plugin=must-gather-monitoring
oc logs -n sonobuoy -f -c sonobuoy-worker -l sonobuoy-plugin=must-gather-monitoring
oc logs -n sonobuoy -f sonobuoy
```

- Wait the results to be ready by the server:

```bash
$ ./opct sonobuoy status

                   PLUGIN     STATUS   RESULT   COUNT   PROGRESS
   must-gather-monitoring   complete   passed       1           

Sonobuoy has completed. Use `sonobuoy retrieve` to get results.

```

- Collect the results

```bash
RESULT=$(./opct sonobuoy retrieve)
./opct sonobuoy results $RESULT
```

- Review the results

```bash
$ ./opct sonobuoy results $RESULT
Plugin: must-gather-monitoring
Status: passed
Total: 1
Passed: 1
Failed: 0
Skipped: 0

Run Details:
API Server version: v1.27.4+2c83a9f
Node health: 6/6 (100%)
Pods health: 262/262 (100%)
Errors detected in files:
Warnings:
73 podlogs/sonobuoy/sonobuoy/logs/kube-sonobuoy.txt
```

- Destroy tbe environment

```bash
./opct sonobuoy delete
oc delete ns sonobuoy
```


## Build a container image

1. Build the image:

```bash
make build-image
```

or to create a custom version:

```bash
make build-image VERSION=v0.1.0
```