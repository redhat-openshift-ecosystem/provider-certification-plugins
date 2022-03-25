#!/bin/sh

mkfifo /tmp/sonobuoy/results/status_pipe; 

export KUBECONFIG=/tmp/kubeconfig;
declare -g CA_PATH="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
declare -g SA_TOKEN="/var/run/secrets/kubernetes.io/serviceaccount/token"
suite="${E2E_SUITE:-kubernetes/conformance}"

#
# login
#
oc login https://172.30.0.1:443 \
    --token=$(cat ${SA_TOKEN}) \
    --certificate-authority=${CA_PATH};

PUBLIC_API_URL=$(oc get infrastructure cluster -o=jsonpath='{.status.apiServerURL}');
oc login ${PUBLIC_API_URL} \
    --token=$(cat ${SA_TOKEN}) \
    --certificate-authority=${CA_PATH};

#
# runner
#

# To run custom tests, set the environment CUSTOM_TEST_FILE on plugin definition.
# To generate the test file, use the parse-test.py.
if [[ ! -z ${CUSTOM_TEST_FILE:-} ]]; then
    echo "Running openshift-tests for custom tests [${CUSTOM_TEST_FILE}]..."
    openshift-tests run \
        --junit-dir /tmp/sonobuoy/results \
        -f ./tests/${CUSTOM_TEST_FILE} | tee /tmp/sonobuoy/results/status_pipe
else
    echo "Running openshift-tests for suite [${suite}]..."
    openshift-tests run \
        --junit-dir /tmp/sonobuoy/results \
        ${suite} | tee /tmp/sonobuoy/results/status_pipe
fi

RESULT=$?;
echo RESULT ${RESULT};

#
# feedback
#

cd /tmp/sonobuoy/results;

JUNIT_OUTPUT=$(ls junit*.xml);
chmod 644 ${JUNIT_OUTPUT};

echo '/tmp/sonobuoy/results/'${JUNIT_OUTPUT} > /tmp/sonobuoy/results/done     
