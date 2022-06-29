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
