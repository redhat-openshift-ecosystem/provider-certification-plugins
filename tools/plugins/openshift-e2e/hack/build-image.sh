#!/bin/sh

registry="quay.io/mrbraga"

podman build -t ${registry}/openshift-partner-cert:latest .
podman push ${registry}/openshift-partner-cert:latest
