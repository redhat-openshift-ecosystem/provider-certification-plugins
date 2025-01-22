#!/usr/bin/env bash

set -o nounset

#
# Platform-specific setup/functions
#
# See also # https://github.com/openshift/release/blob/master/ci-operator/step-registry/openshift/e2e/test/openshift-e2e-test-commands.sh

declare -gx PLATFORM_TYPE
declare -gx OPENSHIFT_TESTS_EXTRA_ARGS
# shellcheck disable=SC2034
declare -gr UTIL_OC_BIN=/usr/bin/oc
declare -gr SERVICE_NAME="platform"


os_log_info() {
    caller_src=$(caller | awk '{print$2}')
    caller_name="$(basename -s .sh "$caller_src"):$(caller | awk '{print$1}')"
    echo "$(date --iso-8601=seconds) | [${SERVICE_NAME}] | $caller_name> " "$@"
}
export -f os_log_info


function setup_provider_azure() {
    os_log_info "[executor] setting provider configuration for [${PLATFORM_TYPE}]"

    # openshift-tests args
    export TEST_PROVIDER=azure
    OPENSHIFT_TESTS_EXTRA_ARGS+="--provider ${TEST_PROVIDER}"

    # setup credentials file
    export AZURE_AUTH_LOCATION=/tmp/osServicePrincipal.json
    creds_file=/tmp/cloud-creds.json
    ${UTIL_OC_BIN} get secret/azure-credentials -n kube-system -o jsonpath='{.data}' > $creds_file
    cat <<EOF > ${AZURE_AUTH_LOCATION}
{
  "subscriptionId": "$(jq -r .azure_subscription_id $creds_file | base64 -d)",
  "clientId": "$(jq -r .azure_client_id $creds_file | base64 -d)",
  "clientSecret": "$(jq -r .azure_client_secret $creds_file | base64 -d)",
  "tenantId": "$(jq -r .azure_tenant_id $creds_file | base64 -d)"
}
EOF
    echo "${OPENSHIFT_TESTS_EXTRA_ARGS}" > /tmp/shared/platform-args
}



function setup_provider_gcp() {
    os_log_info "[executor] setting provider configuration for [${PLATFORM_TYPE}]"

    PROJECT="$(oc get -o jsonpath='{.status.platformStatus.gcp.projectID}' infrastructure cluster)"
    REGION="$(oc get -o jsonpath='{.status.platformStatus.gcp.region}' infrastructure cluster)"
    export TEST_PROVIDER="{\"type\":\"gce\",\"region\":\"${REGION}\",\"multizone\": true,\"multimaster\":true,\"projectid\":\"${PROJECT}\"}"

    OPENSHIFT_TESTS_EXTRA_ARGS+="--provider ${TEST_PROVIDER}"

    export GOOGLE_APPLICATION_CREDENTIALS="${GCP_SHARED_CREDENTIALS_FILE}"
    # In k8s 1.24 this is required to run GCP PD tests. See: https://github.com/kubernetes/kubernetes/pull/109541
    export ENABLE_STORAGE_GCE_PD_DRIVER="yes"
    export KUBE_SSH_USER=core

    echo "${OPENSHIFT_TESTS_EXTRA_ARGS}" > /tmp/shared/platform-args
}

function setup_provider_aws() {
    os_log_info "[executor] setting provider configuration for [${PLATFORM_TYPE}]"

    # openshift-tests args
    export PROVIDER_ARGS="-provider=aws -gce-zone=us-east-1"
    REGION="$(${UTIL_OC_BIN} get -o jsonpath='{.status.platformStatus.aws.region}' infrastructure cluster)"
    ZONE="$(${UTIL_OC_BIN} get -o jsonpath='{.items[0].metadata.labels.failure-domain\.beta\.kubernetes\.io/zone}' nodes)"
    export TEST_PROVIDER="{\"type\":\"aws\",\"region\":\"${REGION}\",\"zone\":\"${ZONE}\",\"multizone\":true,\"multimaster\":true}"

    OPENSHIFT_TESTS_EXTRA_ARGS+="--provider ${TEST_PROVIDER}"

    # setup credentials file
    export AWS_SHARED_CREDENTIALS_FILE=/tmp/.awscred
    creds_file=/tmp/cloud-creds.json
    ${UTIL_OC_BIN} get secret/aws-creds -n kube-system -o jsonpath='{.data}' > $creds_file
    cat <<EOF > ${AWS_SHARED_CREDENTIALS_FILE}
[default]
aws_access_key_id=$(jq -r .aws_access_key_id $creds_file | base64 -d)
aws_secret_access_key=$(jq -r .aws_secret_access_key $creds_file | base64 -d)
EOF
    echo "${OPENSHIFT_TESTS_EXTRA_ARGS}" > /tmp/shared/platform-args
}

function setup_provider_vsphere() {
    os_log_info "[executor] setting provider configuration for [${PLATFORM_TYPE}]"

    # openshift-tests args
    export TEST_PROVIDER=vsphere
    OPENSHIFT_TESTS_EXTRA_ARGS+="--provider ${TEST_PROVIDER}"

    # setup credentials file
    export VSPHERE_CONF_FILE="${SHARED_DIR}/vsphere.conf"
    ${UTIL_OC_BIN} -n openshift-config get cm/cloud-provider-config -o jsonpath='{.data.config}' > "$VSPHERE_CONF_FILE"

    ## The test suite requires a vSphere config file with explicit user and password fields.
    creds_file=/tmp/cloud-creds.json
    ${UTIL_OC_BIN} get secret/vsphere-cloud-credentials -n openshift-cloud-controller-manager -o jsonpath='{.data}' > $creds_file

    USER_KEY=$(jq -r ". | keys[] | select(. | endswith(\".username\"))" $creds_file)
    PASS_KEY=$(jq -r ". | keys[] | select(. | endswith(\".password\"))" $creds_file)
    GOVC_USERNAME=$(jq -r ".[\"${USER_KEY}\"]" $creds_file | base64 -d)
    GOVC_PASSWORD=$(jq -r ".[\"${PASS_KEY}\"]" $creds_file | base64 -d)

    sed -i "/secret-name \=/c user = \"${GOVC_USERNAME}\"" "$VSPHERE_CONF_FILE"
    sed -i "/secret-namespace \=/c password = \"${GOVC_PASSWORD}\"" "$VSPHERE_CONF_FILE"
    echo "${OPENSHIFT_TESTS_EXTRA_ARGS}" > /tmp/shared/platform-args
}


# Check the platform type
os_log_info "[executor] discovering platform type..."
PLATFORM_TYPE=$(${UTIL_OC_BIN} get infrastructure cluster -o jsonpath='{.spec.platformSpec.type}' | tr '[:upper:]' '[:lower:]')
touch /tmp/shared/platform-args;

os_log_info "[executor] platform type=[${PLATFORM_TYPE}]"
# Setup integrated providers / credentials and extra params required to the test environment.
case $PLATFORM_TYPE in
    azure)   setup_provider_azure ;;
    aws)     setup_provider_aws ;;
    gcp) setup_provider_gcp ;;
    vsphere) setup_provider_vsphere ;;
    none|external) echo "INFO: platform type [${PLATFORM_TYPE}] does not require credentials for tests." ;;
    *) echo "WARN: provider setup is ignored or not supported for platform type=[${PLATFORM_TYPE}]" ;;
esac
