
### Dev Debug | Creating metadata for tests

Export tests for conformance suites (`kubernetes/conformance`, `openshift/conformance`) and
extract metadata from name, exporting to CSV:

```bash
$ python parse-tests.py  
Json file saved in {base_output_file}.csv
Json file saved in {base_output_file}.json
```

export:
```bash
$ ./parse-tests.py  --filter-suites all --filter-key suite_k8s --filter-value true
Json file saved in ./tmp/openshift-e2e-suites.csv
Json file saved in ./tmp/openshift-e2e-suites.json
Text file saved in ./tmp/openshift-e2e-suites.txt
```

move to the correct directory:
```
$ cp ./tmp/openshift-e2e-suites.txt tests/sig-etcd.txt
```

use:
```
openshift-tests run  -f tests/sig-etcd.txt
```

example parsed metadata in json:

`jq .suites[].tests[0] tmp/openshift-e2e-suites.json`
```json
{
  "name": "\"[sig-storage] CSI Volumes [Driver: csi-hostpath] [Testpattern: CSI Ephemeral-volume (default fs)] ephemeral should create read-only inline ephemeral volume [Suite:openshift/conformance/parallel] [Suite:k8s]\"",
  "name_parsed": "CSI Volumes   ephemeral should create read-only inline ephemeral volume",
  "tags": [
    {
      "sig-storage": ""
    },
    {
      "Driver": " csi-hostpath"
    },
    {
      "Testpattern": " CSI Ephemeral-volume (default fs)"
    },
    {
      "Suite": "openshift/conformance/parallel"
    },
    {
      "Suite": "k8s"
    }
  ],
  "filters": {
    "in_kubernetes_conformance": "---",
    "in_openshift_conformance": "---",
    "sig": "sig-storage",
    "suite": "openshift/conformance/parallel",
    "suite_k8s": true
  }
}

```
