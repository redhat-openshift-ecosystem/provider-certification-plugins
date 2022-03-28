# OpenShift Provider Certification Plugins

Plugins used to evaluate the OpenShift installation.

## Usage

### Running
Disable container security [see container security restrictions are removed][scc-add]:
~~~
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts
~~~

Run certification tool:
```bash
./run.sh
```

Check results:
- Sonobuoy result file should be placed on current directory

### Check results


### Destroy

Destroy certification environment:
```bash
./destroy.sh
```

Remove custom SCC:
```bash
oc adm policy remove-scc-from-group anyuid system:authenticated system:serviceaccounts
oc adm policy remove-scc-from-group privileged system:authenticated system:serviceaccounts
```

## Troubleshooting

### Failed executions

1. Check the tests statusess and error tests:

```bash
./report.sh
```

1. Check the [documentation](TODO:path/to/tests/doc) to troubleshoot the failing tests

> The documentation referencing the test definition should be delivered on the main repo as part of the tool. For reference, the k8s-conformance auto generates that doc for each release. https://github.com/cncf/k8s-conformance/tree/master/docs



[scc-add]:https://github.com/openshift/kubernetes/blob/master/openshift-hack/conformance-k8s.sh#L47
