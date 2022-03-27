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

### Exporting tests with filters:

- export it
```bash
$ ./parse-tests.py  --filter-suites all --filter-key sig --filter-value sig-etcd
Json file saved in ./tmp/openshift-e2e-suites.csv
Json file saved in ./tmp/openshift-e2e-suites.json
Text file saved in ./tmp/openshift-e2e-suites.txt
```

- move to correct directory

```
$ cp ./tmp/openshift-e2e-suites.txt tests/sig-etcd.txt
```


- use it

```
openshift-tests run  -f tests/sig-etcd.txt
```
