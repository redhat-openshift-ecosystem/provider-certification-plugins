# OpenShift Tests Provider Certification Plugin


[`sonobuoy`][sonobuoy] plugin to run OpenShift tests on Provider Certification program.

This plugin uses [`openshift-tests` tool][openshift-tests], OpenShift implementation for [e2e-test-framework][e2e-test-framework],
to generate and run the tests used to run the provider certification.

## Dependencies

- podman
- CI registry credentials to build [`openshift-tests` container][openshift-tests-dockerfile].

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
