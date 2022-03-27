# OpenShift Provider Certification Plugins

Plugins used to evaluate the OpenShift installation.

## Usage

Disable container security [see container security restrictions are removed][disable-scc]:
~~~
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts
~~~

Run certification tool:
```bash
sonobuoy run --wait \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin tools/plugins/level-1.yaml \
    --plugin tools/plugins/level-2.yaml \
    --plugin tools/plugins/level-3.yaml
```


[disable-scc]:https://github.com/openshift/kubernetes/blob/master/openshift-hack/conformance-k8s.sh#L47
