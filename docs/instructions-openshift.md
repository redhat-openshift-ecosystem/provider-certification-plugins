# OpenShift Provider Certification Tool

> temp file: when structured, move to `instructions.md`

## Setup

### Install dependencies

1. Download sonobuoy and extract [sonobuoy](https://github.com/vmware-tanzu/sonobuoy/releases/)

2. Disable container security[see container security restrictions are removed](https://github.com/openshift/kubernetes/blob/master/openshift-hack/conformance-k8s.sh#L47)
~~~
oc adm policy add-scc-to-group anyuid system:authenticated system:serviceaccounts
oc adm policy add-scc-to-group privileged system:authenticated system:serviceaccounts
~~~

Once conformance testing is completed, if you do not have the cluster cleaned up, be sure to restore the default security rules:

oc adm policy remove-scc-from-group anyuid system:authenticated system:serviceaccounts
oc adm policy remove-scc-from-group privileged system:authenticated system:serviceaccounts

### Create product metadata

```bash
git checkout -b cert-4.10-myProvider
mkdir -p 4.10/myProvider
cp templates/PROVIDER.json 4.10/myProvider/PROVIDER.json
```

## Run provider certification


3. Run certification tool to evaluate Level-3:
```sh
sonobuoy run --wait --mode certified-conformance \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin plugins/level-0-k8s.yaml \
    --plugin plugins/level-1.yaml \
    --plugin plugins/level-2.yaml \
    --plugin plugins/level-3.yaml
```

4. Check status
```sh
$ sonobuoy status
                     PLUGIN     STATUS   RESULT   COUNT   PROGRESS
   ocp-partner-cert-level-1   complete   passed       1           
   ocp-partner-cert-level-2   complete   passed       1           
   ocp-partner-cert-level-3   complete   passed       1           

Sonobuoy has completed. Use `sonobuoy retrieve` to get results.
```

5. Retrieve results
```sh
result_file=$(sonobuoy retrieve)
```

## Send the Certification results

### Get the credentials

Get the presigned URL to upload the results to S3:

```sh
curl https://opct/auth \
    -d4.10/myProvider/PROVIDER.json \
    -H 'Authorization: Basic dXNlcm5hbWVAcGFzc3dvcmQK' > credentials.json
```

### Upload the artifacts

```sh
aws s3 cp ${result_file} $(jq .artifact_url credentials.json)
```

### Open a Pull Request

```sh
git add 4.10/myProvider/
git push --set-upstream origin cert-4.10-myProvider
```

- https://github.com/mtulio/openshift-provider-certification/pull/new/cert-4.10-myProvider


## Remove the test tool

```sh
sonobuoy delete --wait
```

