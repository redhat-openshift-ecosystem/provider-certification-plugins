# openshift-tests-plugin

The `openshift-tests-plugin` is a utility to schedule `openshift-tests` in the
OPCT test environment, backed by Sonobuoy.

## Build


- Create the binary:

```sh
make build
```

- Create the container image:


```sh
make build-image
```


- Create the container image used by Sonobuoy plugin:

```sh
cd .. && make build COMMAND=push PLATFORMS=linux/amd64
```
The following images will be created locally:
- `quay.io/opct/clients:devel`
- `quay.io/opct/plugin-openshift-tests:v0.0.0-devel-26ee6a7`
- `quay.io/opct/must-gather-monitoring:v0.0.0-devel-26ee6a7`

The following images will be pushed to the registry ([quay.io/opct]()):

- `quay.io/opct/plugin-openshift-tests:v0.0.0-devel-26ee6a7`
- `quay.io/opct/must-gather-monitoring:v0.0.0-devel-26ee6a7`

## Usage

### `run`

The main command use by plugin step in the OPCT workflow is the `run`.

The `run` command receives the plugin as argument `--plugin` and set the
correct configuration for built-in/hardcoded/valid OPCT plugins/step to schedule
OPCT workflows.

Example of running the plugin (requires aggregator server and worker sidecar, available only in the environment deployed by Sonobuoy) 


### `exec`

There are several functions used by the plugin workflow exported by subcommand `exec`.

Those commands are helpers for out-of-tree plugins - plugins running in bash as main flow, consuming `openshift-tests-plugin` capabilities like sonobuoy aggregator updates.

Some examples:

- Extract the failures from the JUnit (produced by `openshift-tests` execution), and getting a second list with only tests included in the suite (produced by `openshift-tests run <suite name> --dry-run -o suite.list`):

```sh
./openshift-tests-plugin exec parser-failures-junit \
    --suite suite.list \
    --xml junit_e2e__20240703-154429.xml \
    --out-failures-xml ./failures-xml.txt \
    --out-failures-suite ./failures-xml-suite-only.txt
```

- Extract the failures list which exists only in the suite:

```sh
./openshift-tests-plugin exec parser-failures-suite \
    --suite suite.list \
    --failures failures.txt \
    --output ./failures-suite.txt
```

- Extract all tests from a list which exists only in the suite:

```sh
./openshift-tests-plugin exec parser-test-suite \
    --e2e-log ./results-complete/podlogs/opct/sonobuoy-10-openshift-kube-conformance-job-79b165715ee74fc4/logs/tests.txt \
    --output /tmp/suite.list
```

- Send progress updates to aggregator server (used by collector plugin):

```sh
./openshift-tests-plugin exec progress-msg --message "status=running";
```

- Block execution waiting for the blocker plugin (used by collector plugin):


```sh
./openshift-tests-plugin exec wait-updater \
    --init-total="${PROGRESS["total"]:-0}" \
    --plugin "openshift-conformance-validated" \
    --blocker "openshift-kube-conformance" \
    --done "/tmp/sonobuoy/results/plugin.done"
```
