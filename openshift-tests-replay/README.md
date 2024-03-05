# Run openshigt-tests replay plugin

Standalone plugin to replay custom e2e tests using `openshift-tests` using opct/sonobuoy plugin workflow.

Steps:

- Export KUBECONFIG

- Create replay file

> The tests must have double brackets sepparated by line

```sh
cat << EOF > ./example-replay.txt
"[sig-api-machinery] CustomResourceDefinition Watch [Privileged:ClusterAdmin] CustomResourceDefinition Watch watch on custom resource definition objects [Conformance] [Suite:openshift/conformance/parallel/minimal] [Suite:k8s]"
EOF
```

- Download the Plugin spec (devel path):

```sh
wget -qO /tmp/replay-plugin.yaml https://raw.githubusercontent.com/mtulio/provider-certification-plugins/plugin-openshift-tests-replay/openshift-tests-replay/plugin.yaml
```

- Create ConfigMap

> The key must be `replay.list`

```sh
oc create ns tmp-opct
oc create configmap -n tmp-opct openshift-tests-replay --from-file=replay.list=./example-replay.txt
```

- Run plugin

```sh
opct-devel sonobuoy run \
    -p /tmp/replay-plugin.yaml  \
    --plugin-env openshift-tests-replay.REPLAY_NAMESPACE=tmp-opct \
    --plugin-env openshift-tests-replay.REPLAY_CONFIG=openshift-tests-replay \
    --dns-namespace=openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default
```

- Check the status:

```sh
oc get pods -n sonobuoy -w
opct-devel sonobuoy status
```

- Follow the execution:

```sh
oc logs -n sonobuoy -l sonobuoy-plugin=openshift-tests-replay -f -c plugin
```

- Collect the results when it finished

> Note 1) Wait for sonobuoy clean the message `Preparing results for download.` on `status`: `watch -n 5 opct-devel sonobuoy status`

> Note 2) Retry when getting the error `error retrieving results: unexpected EOF`


```sh
opct-devel sonobuoy retrieve
```

- Check the results

```sh
opct-devel sonobuoy results -m dump tarball.tgz
```

- Explore the logs

```sh
mkdir -p /tmp/plugin-replay-res
tar xfz tarball.tgz -C /tmp/plugin-replay-res
```

- Read the documentation to understand [the directory structure](https://redhat-openshift-ecosystem.github.io/provider-certification-tool/troubleshooting-guide/#review-results-archive)

- Destroy the environment

```sh
opct-devel sonobuoy delete
oc delete ns tmp-opct
```
