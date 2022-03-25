#!/bin/sh
mkfifo /tmp/sonobuoy/results/status_pipe; 
export KUBECONFIG=/tmp/kubeconfig;
oc login https://172.30.0.1:443 --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt;
PUBLIC_API_URL=$(oc get infrastructure cluster -o=jsonpath='{.status.apiServerURL}');
oc login ${PUBLIC_API_URL} --token=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token) --certificate-authority=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt;       
openshift-tests run --junit-dir /tmp/sonobuoy/results openshift/conformance/parallel | tee /tmp/sonobuoy/results/status_pipe
RESULT=$?;
echo RESULT ${RESULT};
cd /tmp/sonobuoy/results;
JUNIT_OUTPUT=$(ls junit*.xml);
chmod 644 ${JUNIT_OUTPUT};
echo '/tmp/sonobuoy/results/'${JUNIT_OUTPUT} > /tmp/sonobuoy/results/done     
