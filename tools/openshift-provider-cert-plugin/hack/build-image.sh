#!/usr/bin/env bash

set -o pipefail
set -o nounset
set -o errexit

REGISTRY="${REGISTRY:-quay.io/mrbraga}"
CONTAINER_IMAGE="${REGISTRY}/openshift-tests-provider-cert"
VERSION_BUILD="${1:-devel}"
VERSION=$(date +%Y%m%d%H%M%S)

TMP_DIR="./tmp"
SB_VERSION="0.56.6"
SB_FILENAME="sonobuoy_${SB_VERSION}_linux_amd64.tar.gz"
SB_URL="https://github.com/vmware-tanzu/sonobuoy/releases/download/v${SB_VERSION}/${SB_FILENAME}"
SB_CONTAINER_SRC="docker.io/sonobuoy/sonobuoy:v${SB_VERSION}"
SB_CONTAINER_DST="${REGISTRY}/sonobuoy:v${SB_VERSION}"

# build openshift-tests image (@openshift/origin)
test "$(podman image exists openshift-tests:latest; echo $?)" -eq 0 || \
    "$(dirname "$0")"/build-openshift-tests-image.sh

# generate tests
echo "#> Start generating the test tier"
"$(dirname "$0")"/generate-tests-tiers.sh
"$(dirname "$0")"/generate-tests-exception.sh

# Sonobuoy

mkdir -p ${TMP_DIR}

## Download Sonobuoy
echo "#> Check for Sonobuoy binary"
if [[ ! -f ${TMP_DIR}/${SB_FILENAME} ]]; then
    rm -rvf ${TMP_DIR}/*.tar.gz ${TMP_DIR}/sonobuoy
    wget ${SB_URL} -P ${TMP_DIR}/
fi

if [[ ! -f ${TMP_DIR}/sonobuoy ]]; then
    tar xvfz ${TMP_DIR}/${SB_FILENAME} -C ${TMP_DIR}/ sonobuoy
fi

echo "#> Sonobuoy version (want): v${SB_VERSION}"
${TMP_DIR}/sonobuoy version

# create plugin image
echo "#> Building container image ${CONTAINER_IMAGE}:${VERSION_BUILD}"
podman build -t "${CONTAINER_IMAGE}":"${VERSION_BUILD}" .

echo "#> Pushing image to registry: ${CONTAINER_IMAGE}:${VERSION_BUILD}"
podman push "${CONTAINER_IMAGE}":"${VERSION_BUILD}"

echo "#> Tagging and pushing image to registry: ${CONTAINER_IMAGE}:${VERSION}"
podman tag \
    "${CONTAINER_IMAGE}":"${VERSION_BUILD}" \
    "${CONTAINER_IMAGE}":"${VERSION}"

podman push "${CONTAINER_IMAGE}":"${VERSION}"

echo "#> Mirroring sonobuoy container image"
if [[ $(skopeo list-tags docker://"${REGISTRY}"/sonobuoy |jq -r ".Tags | index (\"v${SB_VERSION}\") // false") == false ]]; then
    echo "#>> Sonobuoy container version is missing, starting the mirror"
    podman pull ${SB_CONTAINER_SRC} &&
        podman tag "${SB_CONTAINER_SRC}" "${SB_CONTAINER_DST}" &&
        podman push "${SB_CONTAINER_DST}"
fi
