#!/usr/bin/env bash

#
# Container image builder.
# - Check if sonobuoy mirror exists, if not mirror it
# - Check if tools image exists, if not mirror it
# - Build the Plugin container image
#

set -o pipefail
set -o nounset
set -o errexit

REGISTRY="${REGISTRY:-quay.io/ocp-cert}"

VERSION_PLUGIN=$(date +%Y%m%d%H%M%S)
VERSION_PLUGIN_DEVEL="${1:-devel}"
FORCE="${2:-false}"

VERSION_TOOLS="latest"
VERSION_SONOBUOY="v0.56.5"
VERSION_OC="4.10.18"

IMAGE_BASE="registry.access.redhat.com/ubi8/ubi-minimal"
IMAGE_PLUGIN="${REGISTRY}/openshift-tests-provider-cert"
IMAGE_TOOLS="${REGISTRY}/tools"
IMAGE_SONOBUOY="docker.io/sonobuoy/sonobuoy"

CONTAINER_BASE="${IMAGE_BASE}:latest"
CONTAINER_SONOBUOY="${IMAGE_SONOBUOY}:${VERSION_SONOBUOY}"
CONTAINER_SONOBUOY_MIRROR="${REGISTRY}/sonobuoy:${VERSION_SONOBUOY}"
CONTAINER_TOOLS="${IMAGE_TOOLS}:${VERSION_TOOLS}"
CONTAINER_PLUGIN="${IMAGE_PLUGIN}:${VERSION_PLUGIN}"

# Sonobuoy
echo "#> Checking sonobuoy container image"
if [[ $(skopeo list-tags docker://"${REGISTRY}"/sonobuoy |jq -r ".Tags | index (\"${VERSION_SONOBUOY}\") // false") == false ]]; then
    echo "#>> Sonobuoy container version is missing, starting the mirror"
    podman pull ${CONTAINER_SONOBUOY} &&
        podman tag "${CONTAINER_SONOBUOY}" "${CONTAINER_SONOBUOY_MIRROR}" &&
        podman push "${CONTAINER_SONOBUOY_MIRROR}"
fi

echo "#> Checking Tools container image"
TOOLS_EXISTS=$(skopeo list-tags docker://"${IMAGE_TOOLS}" |jq -r ".Tags | index (\"${VERSION_TOOLS}\") // false")
if [[ ${TOOLS_EXISTS} == 1 || ${FORCE} == true ]]; then
    echo "#>> Sonobuoy container version is missing, starting the mirror"
    echo "#> Building Tools image"
    podman build \
        --build-arg CONTAINER_BASE="${CONTAINER_BASE}" \
        --build-arg CONTAINER_SONOBUOY="${CONTAINER_SONOBUOY_MIRROR}" \
        --build-arg VERSION_OC=${VERSION_OC} \
        -t "${CONTAINER_TOOLS}" \
        -f Dockerfile.tools .

    echo "##> Upload image ${CONTAINER_TOOLS}"
    podman push "${CONTAINER_TOOLS}"
fi

echo "#> Building Plugin Image"
podman build \
    --build-arg CONTAINER_BASE="${CONTAINER_BASE}" \
    --build-arg CONTAINER_TOOLS="${CONTAINER_TOOLS}" \
    -t "${CONTAINER_PLUGIN}" \
    -f Dockerfile .

echo "#> Applying tags"
echo "##> Tag devel ${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
podman tag \
    "${CONTAINER_PLUGIN}" \
    "${IMAGE_PLUGIN}":"${VERSION_PLUGIN_DEVEL}"

echo "#> Upload images"
echo "##> Upload image ${CONTAINER_PLUGIN}"
podman push "${CONTAINER_PLUGIN}"

echo "##> Upload image ${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
podman push "${IMAGE_PLUGIN}":"${VERSION_PLUGIN_DEVEL}"
