#!/bin/bash

#
# Clone one worker MachineSet in AWS to setup dedicated test environment node.
# Changes:
#  + label: node-role.kuberntes.io/tests
#  + taint: NoSchedule
#

# Check of the cluster is running on AWS
if [[ "$(oc get infrastructure cluster -o jsonpath='{.status.platform}')" != "AWS" ]]; then
  echo "This script supports clusters running only in AWS integrated platform."
  exit 1
fi

# Ge the cluster ID
CLUSTER_ID="$(oc get infrastructure cluster \
    -o jsonpath='{.status.infrastructureName}')"

# select the first worker machineset that has replicas
MS=$(oc get machinesets -n openshift-machine-api -o json \
    | jq -r '.items[] | select(.spec.replicas>=1).metadata.name' \
    | grep worker | head -n1)

oc get machineset -n openshift-machine-api "${MS}" -o json > /tmp/ms-info.json

NODE_ROLE=tests
KEY_PREF=".spec.template.spec.providerSpec.value"
AZ_NAME=$(jq -r "${KEY_PREF}.placement.availabilityZone" /tmp/ms-info.json)
INSTANCE_TYPE=$(jq -r "${KEY_PREF}.instanceType" /tmp/ms-info.json)
REGION=$(jq -r "${KEY_PREF}.placement.region" /tmp/ms-info.json)
SUBNET_NAME=$(jq -r "${KEY_PREF}.subnet.filters[0].values[0]" /tmp/ms-info.json)
AMI_ID=$(jq -r "${KEY_PREF}.ami.id" /tmp/ms-info.json)
rm /tmp/ms-info.json

cat <<EOF | envsubst | oc create -f -
apiVersion: machine.openshift.io/v1beta1
kind: MachineSet
metadata:
  labels:
    machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
  name: ${CLUSTER_ID}-${NODE_ROLE}-${AZ_NAME}
  namespace: openshift-machine-api
spec:
  replicas: 1
  selector:
    matchLabels:
      machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
      machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-${NODE_ROLE}-${AZ_NAME}
  template:
    metadata:
      labels:
        machine.openshift.io/cluster-api-cluster: ${CLUSTER_ID}
        machine.openshift.io/cluster-api-machine-role: ${NODE_ROLE}
        machine.openshift.io/cluster-api-machine-type: ${NODE_ROLE}
        machine.openshift.io/cluster-api-machineset: ${CLUSTER_ID}-${NODE_ROLE}-${AZ_NAME}
    spec:
      metadata:
        labels:
          node-role.kubernetes.io/${NODE_ROLE}: ""
      taints:
        - key: node-role.kubernetes.io/${NODE_ROLE}
          effect: NoSchedule
      providerSpec:
        value:
          kind: AWSMachineProviderConfig
          ami:
            id: ${AMI_ID}
          apiVersion: awsproviderconfig.openshift.io/v1beta1
          credentialsSecret:
            name: aws-cloud-credentials
          iamInstanceProfile:
            id: ${CLUSTER_ID}-worker-profile
          instanceType: ${INSTANCE_TYPE}
          placement:
            availabilityZone: ${AZ_NAME}
            region: ${REGION}
          securityGroups:
          - filters:
            - name: tag:Name
              values:
              - ${CLUSTER_ID}-worker-sg
          subnet:
            filters:
            - name: tag:Name
              values:
              - ${SUBNET_NAME}
          tags:
          - name: kubernetes.io/cluster/${CLUSTER_ID}
            value: owned
          userDataSecret:
            name: worker-user-data
EOF
