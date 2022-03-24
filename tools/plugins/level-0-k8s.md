# k8s-e2e

The build-in e2e job was exported to run stacked with other plugins.

Steps to update the plugin definition:

```bash
sonobuoy gen plugin e2e \
    --mode certified-conformance \
    | sed 's/plugin-name: e2e/plugin-name: k8s-conformance/g' \
    > plugins/level-0-k8s-conformance.yaml
```

Reference:
- [e2e plugin](https://github.com/vmware-tanzu/sonobuoy-plugins/tree/main/e2e)
- [example e2e-skeleton](https://github.com/vmware-tanzu/sonobuoy-plugins/tree/main/examples/e2e-skeleton)
