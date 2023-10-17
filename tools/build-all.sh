#!/usr/bin/env bash

#
# Container image builder.
# - Check if tools image exists, if not mirror it
# - Build the Plugin container image
#

set -o pipefail
set -o nounset
set -o errexit

# shellcheck disable=SC1091
source "$(dirname "$0")/../build.env"

build_info() {
    cat << EOF > ./VERSION
BUILD_VERSION=${VERSION_PLUGIN}
BUILD_TIMESTAMP=${TS}
BUILD_COMMIT=$(git rev-parse --short HEAD)
IMAGE=${CONTAINER_PLUGIN}
VERSION_TOOLS_IMAGE=${VERSION_TOOLS}
VERSION_TOOL_SONOBUOY=${VERSION_SONOBUOY}
VERSION_TOOL_OC=${VERSION_OC}
EOF
}

gen_containerfiles() {
    envsubst < hack/Containerfile.alp > Containerfile
    test -f Containerfile && echo "Containerfile created"
    envsubst < hack/Containerfile.tools-alp > Containerfile.tools
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

push_image() {
    echo "##> Uploading image ${1}"
    podman push "${1}"
}

tag_image() {
    echo "##> Tagging images: ${1} => ${2}"
    podman tag "${1}" "${2}"
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
    tag_image "${CONTAINER_TOOLS}" "${IMAGE_TOOLS}:${VERSION_TOOLS}"
    tag_image "${CONTAINER_TOOLS}" "${IMAGE_TOOLS}:latest"
}

pusher_tools() {
    echo "#> Upload images ${IMAGE_TOOLS}"
    push_image "${CONTAINER_TOOLS}"
    push_image "${IMAGE_TOOLS}:latest"
    push_image "${IMAGE_TOOLS}:${VERSION_TOOLS}"
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
        return
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
        tag_image \
            "${IMAGE_PLUGIN}:${VERSION_PLUGIN}" \
            "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    else
        # 'latest' will be created only when 'devel' is not set
        tag_image \
            "${IMAGE_PLUGIN}:${VERSION_PLUGIN}" \
            "${IMAGE_PLUGIN}:latest"
    fi
    echo "You can now use push-tools to upload the image"
}

pusher_plugin() {
    echo "#> Upload images"
    push_image "${IMAGE_PLUGIN}:${VERSION_PLUGIN}"
    if [[ -n ${VERSION_PLUGIN_DEVEL} ]]; then
        push_image "${IMAGE_PLUGIN}:${VERSION_PLUGIN_DEVEL}"
    else
        push_image "${IMAGE_PLUGIN}:latest"
    fi
}

build_plugin() {
    echo "#> Checking Tools container image"
    cmd_succeeded=$( image_exists "${IMAGE_TOOLS}" "${VERSION_TOOLS}"; echo $? )
    if [[ $cmd_succeeded -eq 1 ]] && [[ $FORCE == false ]]; then
        echo "#>> Tools image [${IMAGE_TOOLS}:${VERSION_TOOLS}] does not exists. build it with options build-tools and push-tools."
        exit 1
    fi
    builder_plugin
}

release() {
    FORCE=true
    build_tools
    push_tools
    build_plugin
    pusher_plugin
}

build_info
gen_containerfiles
case $COMMAND in
    "build-plugin") build_plugin ;;
    "build-tools") build_tools ;;
    "push-tools") push_tools ;;
    "build-dev") build_plugin ; pusher_plugin ;;
    "release") release;;
    *) echo "Option [$COMMAND] not found"; exit 1 ;;
esac
