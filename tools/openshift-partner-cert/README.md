# plugin openshift-e2e

The plugin `openshift-e2e` is a base plugin to run e2e tests on OpenShift.


## Exporting tests

Export tests for conformance suites (`kubernetes/conformance`, `openshift/conformance`) and
extract metadata from name, exporting to CSV:

```bash
$ python parse-tests.py  
Json file saved in {base_output_file}.csv
Json file saved in {base_output_file}.json

```
