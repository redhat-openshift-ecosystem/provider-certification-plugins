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

VERSION_TOOLS="v0.0.0-oc41018-s0565"
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
mirror_sonobuoy() {
    echo "#>> Creating Sonobuoy mirror from ${CONTAINER_SONOBUOY} to ${CONTAINER_SONOBUOY_MIRROR}"
    podman pull ${CONTAINER_SONOBUOY} &&
        podman tag "${CONTAINER_SONOBUOY}" "${CONTAINER_SONOBUOY_MIRROR}" &&
        podman push "${CONTAINER_SONOBUOY_MIRROR}"
}

build_tools() {
    echo "#> Building Tools image"
    podman build \
        -t "${CONTAINER_TOOLS}-ubi" \
        -f Dockerfile.tools-ubi .

    podman build \
        -t "${CONTAINER_TOOLS}-alp" \
        -f Dockerfile.tools-alp .

    podman tag "${CONTAINER_TOOLS}-alp" "${IMAGE_TOOLS}:${VERSION_TOOLS}"
    podman tag "${CONTAINER_TOOLS}-alp" "${IMAGE_TOOLS}:latest"
}

build_plugin() {
    echo "#> Building Container images"
    echo "#>> Building Plugin Image"
    podman build \
        -t "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-ubi" \
        -f Dockerfile.ubi .

    podman build \
        -t "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-alp" \
        -f Dockerfile.alp .

    echo "#> Applying tags"
    echo "##> Tag devel ${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    podman tag \
        "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-ubi" \
        "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}-ubi"
    podman tag \
        "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-alp" \
        "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
}

push_tools() {
    echo "##> Upload images ${IMAGE_TOOLS}"
    podman push "${IMAGE_TOOLS}:latest"
    podman push "${IMAGE_TOOLS}:${VERSION_TOOLS}"
    podman push "${CONTAINER_TOOLS}-ubi"
    podman push "${CONTAINER_TOOLS}-alp"
}

push_plugin() {
    echo "#> Upload images"
    echo "##> Upload image ${CONTAINER_PLUGIN}"
    podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-ubi"
    podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN}-alp"
    podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}-ubi"
}

build() {
    echo "#> Checking sonobuoy container image"
    if [[ $(skopeo list-tags docker://"${REGISTRY}"/sonobuoy |jq -r ".Tags | index (\"${VERSION_SONOBUOY}\") // false") == false ]]; then
        echo "#>> Sonobuoy container version is missing, starting the mirror"
        mirror_sonobuoy
    fi

    echo "#> Checking Tools container image"
    TOOLS_EXISTS=$(skopeo list-tags docker://"${IMAGE_TOOLS}" |jq -r ".Tags | index (\"${VERSION_TOOLS}\") // false")
    if [[ ${TOOLS_EXISTS} == 1 || ${FORCE} == true ]]; then
        echo "#>> Tools container version is missing, starting the mirror"
        build_tools
        push_tools
    fi

    # Plugin
    build_plugin
    push_plugin
}

build
