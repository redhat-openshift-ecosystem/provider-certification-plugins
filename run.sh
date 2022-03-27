#!/bin/sh

$(which time) sonobuoy run --wait \
    --dns-namespace openshift-dns \
    --dns-pod-labels=dns.operator.openshift.io/daemonset-dns=default \
    --plugin tools/plugins/level-1.yaml \
    --plugin tools/plugins/level-2.yaml \
    --plugin tools/plugins/level-3.yaml \
    && sonobuoy retrieve
