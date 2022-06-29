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

REGISTRY_PLUGIN="${REGISTRY_PLUGIN:-quay.io/ocp-cert}"
REGISTRY_TOOLS="${REGISTRY_TOOLS:-quay.io/ocp-cert}"
REGISTRY_MIRROR="${REGISTRY_TOOLS:-quay.io/ocp-cert}"

COMMAND="${1:-}";

TS=$(date +%Y%m%d%H%M%S)
VERSION_PLUGIN="${VERSION:-dev${TS}}";
VERSION_PLUGIN_DEVEL="${VERSION_DEVEL:-}";
FORCE="${FORCE:-false}";

# TOOLS version is created by suffix of oc and sonobuoy versions w/o dots
export VERSION_TOOLS="v0.0.0-oc41018-s0565"
export VERSION_SONOBUOY="v0.56.5"
export VERSION_OC="4.10.18"

IMAGE_PLUGIN="${REGISTRY_PLUGIN}/openshift-tests-provider-cert"
IMAGE_TOOLS="${REGISTRY_TOOLS}/tools"
IMAGE_SONOBUOY="docker.io/sonobuoy/sonobuoy"

export CONTAINER_BASE="alpine:3.14"
export CONTAINER_SONOBUOY="${IMAGE_SONOBUOY}:${VERSION_SONOBUOY}"
export CONTAINER_SONOBUOY_MIRROR="${REGISTRY_MIRROR}/sonobuoy:${VERSION_SONOBUOY}"
export CONTAINER_TOOLS="${IMAGE_TOOLS}:${VERSION_TOOLS}"
export CONTAINER_PLUGIN="${IMAGE_PLUGIN}:${VERSION_PLUGIN}"

build_info() {
    cat << EOF > ./VERSION
BUILD_VERSION=${VERSION_PLUGIN}
BUILD_TIMESTAMP=${TS}
BUILD_COMMIT=$(git rev-parse --short HEAD)
VERSION_TOOLS_IMAGE=${VERSION_TOOLS}
VERSION_TOOL_SONOBUOY=${VERSION_SONOBUOY}
VERSION_TOOL_OC=${VERSION_OC}
EOF
}

gen_containerfiles() {
    envsubst < Containerfile.alp > Containerfile
    test -f Containerfile && echo "Containerfile created"
    envsubst < Containerfile.tools-alp > Containerfile.tools
    test -f Containerfile && echo "Containerfile.tools created"
}

image_exists() {
    img=$1; shift
    ver=$1;
    tools_exists=$(skopeo list-tags docker://"${img}" |jq -r ".Tags | index (\"${ver}\") // false")
    if [[ ${tools_exists} == false ]]; then
        false
        return
    fi
    true
}

#
# Sonobuoy image
#
mirror_sonobuoy() {
    echo "#> Checking sonobuoy container image"
    SB_EXISTS=$(skopeo list-tags docker://"${REGISTRY_MIRROR}"/sonobuoy |jq -r ".Tags | index (\"${VERSION_SONOBUOY}\") // false")
    if [[ ${SB_EXISTS} == false ]]; then
        echo "#>> Sonobuoy container version is missing, starting the mirror"
        echo "#>> Creating Sonobuoy mirror from ${CONTAINER_SONOBUOY} to ${CONTAINER_SONOBUOY_MIRROR}"
        podman pull ${CONTAINER_SONOBUOY} &&
            podman tag "${CONTAINER_SONOBUOY}" "${CONTAINER_SONOBUOY_MIRROR}" &&
            podman push "${CONTAINER_SONOBUOY_MIRROR}"
        return
    fi
    echo "#>> Sonobuoy container is present[${REGISTRY_MIRROR}/sonobuoy:${VERSION_SONOBUOY}], ignoring mirror."
}

#
# Tools image
#

builder_tools() {
    echo "#> Building Tools image"
    podman build \
        -t "${CONTAINER_TOOLS}" \
        -f Containerfile.tools .

    echo "#> Applying tags"
    echo "#>> ${CONTAINER_TOOLS} => ${IMAGE_TOOLS}:${VERSION_TOOLS}"
    podman tag "${CONTAINER_TOOLS}" "${IMAGE_TOOLS}:${VERSION_TOOLS}"

    echo "#>> ${CONTAINER_TOOLS} => ${IMAGE_TOOLS}:latest"
    podman tag "${CONTAINER_TOOLS}" "${IMAGE_TOOLS}:latest"
}

pusher_tools() {
    echo "#> Upload images ${IMAGE_TOOLS}"

    echo "#>> ${CONTAINER_TOOLS}"
    podman push "${CONTAINER_TOOLS}"

    echo "#>> ${IMAGE_TOOLS}:latest"
    podman push "${IMAGE_TOOLS}:latest"

    echo "#>> ${IMAGE_TOOLS}:${VERSION_TOOLS}"
    podman push "${IMAGE_TOOLS}:${VERSION_TOOLS}"
}

build_tools() {
    echo "#> Checking Tools container image: ${IMAGE_TOOLS}:${VERSION_TOOLS}"
    cmd_succeeded=$( image_exists "${IMAGE_TOOLS}" "${VERSION_TOOLS}"; echo $? )
    if [[ $cmd_succeeded -eq 0 ]] && [[ $FORCE == false ]]; then
        echo "#>> Tools container version already exists. Ignoring build."
        exit 1
    fi
    echo "#> Starting Tools container builder"
    builder_tools
}

push_tools() {
    echo "#> Checking Tools container image: ${IMAGE_TOOLS}:${VERSION_TOOLS}"
    cmd_succeeded=$( image_exists "${IMAGE_TOOLS}" "${VERSION_TOOLS}"; echo $? )
    if [[ $cmd_succeeded -eq 0 ]] && [[ $FORCE == false ]]; then
        echo "#>> Tools container already exists. Ignoring push."
        exit 1
    fi
    echo "#> Starting Tools container pusher"
    pusher_tools
}

#
# Plugin image
#
builder_plugin() {
    echo "#> Building Container images"
    echo "#>> Building Plugin Image"
    podman build \
        -t "${IMAGE_PLUGIN}:${VERSION_PLUGIN}" \
        -f Containerfile .

    echo "#> Applying tags"
    if [[ -n ${VERSION_PLUGIN_DEVEL} ]]; then
        echo "##> Tag devel ${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
        podman tag \
            "${IMAGE_PLUGIN}:${VERSION_PLUGIN}" \
            "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    fi
    echo "You can now use push-tools to upload the image"
}

pusher_plugin() {
    echo "#> Upload images"
    echo "##> Upload image ${CONTAINER_PLUGIN}"
    podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN}"
    if [[ -n ${VERSION_PLUGIN_DEVEL} ]]; then
        podman push "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    fi
}

build_plugin() {
    echo "#> Checking Tools container image"
    cmd_succeeded=$( image_exists "${IMAGE_TOOLS}" "${VERSION_TOOLS}"; echo $? )
    if [[ $cmd_succeeded -eq 1 ]] && [[ $FORCE == false ]]; then
        echo "#>> Tools container already exists. Ignoring push."
        exit 1
    fi
    builder_plugin
}

release() {
    FORCE=true
    mirror_sonobuoy
    build_tools
    push_tools
    build_plugin
    pusher_plugin
}

build_info
gen_containerfiles
case $COMMAND in
    "mirror-sonobuoy") mirror_sonobuoy;;
    "build-plugin") build_plugin ;;
    "build-tools") build_tools ;;
    "push-tools") push_tools ;;
    "build-dev") build_plugin ; pusher_plugin ;;
    "release") release;;
    *) echo "Option [$COMMAND] not found"; exit 1 ;;
esac
