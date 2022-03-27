# OpenShift Tests Provider Certification PLugin

[`sonobuoy`][sonobuoy] plugin to run OpenShift tests on Provider Certification program.

This plugin uses [`openshift-tests` tool][openshift-tests], OpenShift implementation for [e2e-test-framework][e2e-test-framework],
to generate and run the tests used to run the provider certification.

## Dependencies:

- podman

## Usage

Build container image:
```bash
make build
```

Generate tests for each Certification Level:
```bash
mak generate-openshift-tests
```

Run the sonobuoy plugin:
1. disable security
```
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts
```
2. run
> Make sure the image ref was updated on `plugin.yaml`
```bash
sonobuoy run --wait \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin plugin.yaml
```

## Developer

To include tests on Certification Level, a collector function
should be create to iteract with `openshift-tests` and save it
on a level-based text files which **are included on the plugin container
image on the build time**.

Steps to create the filter for Certification Level for each SIG:

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
1. Create the collector function
```bash
sig_cli() {
    level1_sig_cli
    level2_sig_cli
    level3_sig_cli
}
```
1. Add the new collector function to `collector`:
```diff
collector() {
    sig_storage >/dev/null
+   sig_cli     >/dev/null
}
collector
```
1. Generate the tests
1. Build a new image
1. Run the plugin

### Debug | Creating metadata for tests

[parser.md](./parser.md)


[sonobuoy]:https://github.com/vmware-tanzu/sonobuoy
[openshift-tests]:https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests
[e2e-test-framework]:https://github.com/kubernetes-sigs/e2e-framework
