# OpenShift Tests Provider Certification Plugin

[`sonobuoy`][sonobuoy] plugin to run OpenShift tests on Provider Certification program.

This plugin uses [`openshift-tests` tool][openshift-tests], OpenShift implementation for [e2e-test-framework][e2e-test-framework], to run the e2e suites used to evaluate OpenShift installations.

## Limitations

### Environment

Because of the limitations of the architecture (sonobuoy plugin), it's not possible to run this plugin locally, you should have a sonobuot aggregator to schedule and handle the plugin.

### Plugin dependencies

It's required, and hardcoded, to run the plugins ordered, that is you should run all the instances of this plugin to have a successfull execution.

The definition of required instances are defined on file [plugin/global_fn.sh#init_config](./plugin/global_fn.sh) on the variable `PLUGIN_BLOCKED_BY`.

Some examples:
- it's possible to run the `CERT_LEVEL=0` ("openshift-kube-conformance"), without `CERT_LEVEL=1` ("openshift-conformance-validated"). But the opposite is not allowed as the `CERT_LEVEL=1` depends on, is blocked by, "openshift-kube-conformance".

All the instance provisioning should be handled, and resolved, by the CLI ([openshift-provider-cert](https://github.com/redhat-openshift-ecosystem/provider-certification-tool)).


## Build

The build process on CI runs:

- enter on the plugin directory: `openshift-tests-provider-cert/`
- build a container image for plugin: `make build-ci`

The build process for Development environment, uploading it to custom registry:

```bash
make build-dev DEV_REGISTRY="quay.io/mrbraga"
```

## Release

The steps to create a new release is manually. You should create the tag on the SCM and push it, then the CI will run the tests, and if passed the new container image will be created on the registry:

- Create a tag

```
git tag -a v0.0.0-demo1 -m 'Release v0.0.0-demo1'
```

- Push the tag to SCM

```
git push origin v0.0.0-demo1
```

- Follow the [CI jobs](https://github.com/redhat-openshift-ecosystem/provider-certification-plugins/actions)

- If CI jobs passes, the new version will be available on the repo:

1. [Tools image (only when modified)](https://quay.io/repository/ocp-cert/tools?tab=tags)
2. [Plugin image](https://quay.io/repository/ocp-cert/openshift-tests-provider-cert?tab=tags)

### Steps to promote the release to `stable`

Along the Preview release (v0.*), the CLI will use the tag `stable` on the plugin manifest to run the most recent and stable version of plugins.

The steps to promote a release to stable are manual, please follow those steps:

1. Create a cluster on 4.11+ (usually in AWS)
1. Add a dedicated node (optional): `./hack/oc-create-machineset-aws-dedicated.sh`
1. Follow [these steps](https://github.com/redhat-openshift-ecosystem/provider-certification-tool/blob/main/docs/dev.md#running-customized-certification-plugins) to use the new tag in the plugin manifests.
```bash
./openshift-provider-cert-linux-amd64 assets
./openshift-provider-cert-linux-amd64 run -w --dedicated \
  --plugin=./openshift-kube-conformance_env-shared.yaml \
  --plugin=./openshift-conformance-validated_env-shared.yaml \
```
1. Make sure the dedicated node is running, ROLE=tests (`node-role.kubernetes.io/tests=''`): `oc get nodes`
1. Run the certification environment: `./openshift-provider-cert-linux-amd64 run -w --dedicated`
1. Check if the plugin image was created correctly with your new release: `oc describe pods -n openshift-provider-certification | grep Image:`
1. Wait for the tests to be finished.
1. Once the execution has been finished, the post processor should display the results, somehting like `Total tests processed: 1837 (1777 pass / 60 failed)` (valid counters)
1. Collect the archive `./openshift-provider-cert-linux-amd64 retrieve`
1. Inspect the results `./openshift-provider-cert-linux-amd64 results <artchive>.tar.gz`

If you did not see any errors when running the tool, check the results and inspect the tarball, we are safe to promote the release to `stable`.

> Note: Even if the execution has a few errors on e2e tests, it should not be directly related with the tool or plugins itself, so we are considering `stable` successfull executions, not the content of the e2e that has been addressed in different issue.

Promoting to the new release to stable:

1. Pull the current release created by CI
```bash
podman pull quay.io/ocp-cert/openshift-tests-provider-cert:v0.1.0
```
1. Tag the release to `stable`
```bash
podman tag quay.io/ocp-cert/openshift-tests-provider-cert:v0.1.0 quay.io/ocp-cert/openshift-tests-provider-cert:stable
```
1. Upload the image
```bash
podman push quay.io/ocp-cert/openshift-tests-provider-cert:stable
```



## Run the plugin

To use the Plugin you should look at the Usage documentation.

To use the custom version of plugins, you should:

1. change the image on the plugin manifests
2. build the cli
3. run the environment using your custom CLI build


[sonobuoy]:https://github.com/vmware-tanzu/sonobuoy
[openshift-tests]:https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests
[e2e-test-framework]:https://github.com/kubernetes-sigs/e2e-framework
[openshift-tests-dockerfile]:https://github.com/openshift/origin/blob/master/images/tests/Dockerfile.rhel
