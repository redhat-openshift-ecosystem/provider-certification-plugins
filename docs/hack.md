# Plugin Hacking

The monorepo/project (plugins) is used to host plugins/extensions images used by OPCT conformance workflow.

The following images is hosted by this project:

| Component | Image repo | Description |
| -- | -- | -- |
| openshift-tests-plugin | quay.io/opct/plugin-openshift-tests | Plugin/step used to orchestrate conformance tests using `openshift-tests` utility |
| artifacts-collector-plugin | quay.io/opct/plugin-artifacts-collector | Plugin responsible to collect artifact as post step in the conformance workflow |
| must-gather-monitoring | quay.io/opct/must-gather-monitoring | Standalone plugin responsible to collect metrics from Prometheus. Image is must-gather compatible used by artifactis collector |
| tools | quay.io/opct/tools | Image responsible to standarize external tools used by projects |


## Build Instructions

To build the project with multi-arch support, you must run the following steps:

- Build images for Tools, Plugin openshif-tests, must-gather-monitoring:

```bash
# For x86_64
make build-push-arch-amd64

# For ARM64
make build-push-arch-arm64
```

> Note 1: The images expires quickly, to production set the arg `EXPIRES=never`

> Note 2: By default the images are built appending `-devel-${git_commit}`, to override it set the arg `VERSION='v0.5.0'`.

- Create image manifest (multi-arch) for each component:

```bash
# build and push
make push-manifests
```

### Release

To create a custom release, you can set the version in `build.env` or replace in the command line:

- Update the versions in `build.env`

- Build and push:

amd64:

```bash
TOOLS_VERSION="v0.3.0" \
    PLUGIN_TESTS_VERSION="v0.5.0-alpha.3" \
    MGM_VERSION="v0.2.0" \
    make prod-build-push-arch-amd64
```

arm64:

```bash
TOOLS_VERSION="v0.3.0" \
    PLUGIN_TESTS_VERSION="v0.5.0-alpha.3" \
    MGM_VERSION="v0.2.0" \
    make prod-build-push-arch-arm64
```

Create manifests:

```bash
TOOLS_VERSION="v0.3.0" \
    PLUGIN_TESTS_VERSION="v0.5.0-alpha.3" \
    MGM_VERSION="v0.2.0" \
    make prod-build-push-manifests
```

## Utils

Remove manifests:

```bash
TOOLS_VERSION="v0.3.0" \
    PLUGIN_TESTS_VERSION="v0.5.0-alpha.3" \
    MGM_VERSION="v0.2.0" \
    make remove-manifests
```
