#!/bin/sh

# Build openshift-tests binary
# https://github.com/openshift/origin#end-to-end-e2e-and-extended-tests

rm -rf tmp/origin
git clone git@github.com:openshift/origin.git tmp/origin
cd tmp/origin
make
