# HowTos related to openshift-tests plugin

That document describes common procedures used on the troubleshooting and development process for `openshift-tests` utility plugin, a.k.a `openshift-tests-provider-cert`. 

## openshift-tests utility

### Filter tests by sig

```bash
openshift-tests run --dry-run all \
    | grep -Po '(\[sig-[a-zA-Z]*\])' \
    | sort | uniq -c | sort -n
```

### Build container image

```bash
# Build openshift-tests binary
# https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests

PULL_SECRET="${HOME}/.openshift/pull-secret-latest.json"
tmp_origin="./tmp/origin"
rm -rf "${tmp_origin}"
git clone git@github.com:openshift/origin.git "$tmp_origin"

pushd "${tmp_origin}" || exit 1
podman build \
    --authfile "${PULL_SECRET}" \
    -t openshift-tests:latest \
    -f images/tests/Dockerfile.rhel .
popd || true
```


### Generate tests by tier

- Example filter all `sig-storage` tagged by `Conformance`:

```bash
./openshift-tests run --dry-run "all" \
    | grep -P '^(?=.*\[sig-storage\])(?=.*\[Conformance\])' \
    | tee -a "${tests_level1}"
```
