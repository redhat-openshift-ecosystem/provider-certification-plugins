#!/usr/bin/env bash

#
# Build and push container images for openshift-tests-plugin and must-gather-monitoring.
#
# Usage examples:
# $ ./build.sh build plugin-openshift-testslinux/amd64
# $ ./build.sh build all linux/amd64,linux/arm64
#

set -o pipefail
set -o nounset
set -o errexit

############
# Input args
#
# Example: ./build.sh build plugin-openshift-tests linux/amd64
#
############

COMMAND=${1}; shift
BUILD_IMG=${1}; shift
PLATFORMS=${1:-linux/amd64,linux/arm64};

########################
# Version vars
########################
# # shellcheck disable=SC1091
# source "$(dirname "$0")/build.env"

# Current Versions
export VERSION="${VERSION:-devel}"
export IMAGE_EXPIRE_TIME="${EXPIRE:-12h}"

export TOOLS_VERSION=${TOOLS_VERSION:-$VERSION}
export TOOLS_REPO=${TOOLS_REPO:-quay.io/opct/tools}
export TOOLS_IMG=${TOOLS_REPO}:${TOOLS_VERSION}

export PLUGIN_TESTS_VERSION=${PLUGIN_TESTS_VERSION:-$VERSION}
export PLUGIN_TESTS_REPO=${PLUGIN_TESTS_REPO:-quay.io/opct/plugin-openshift-tests}
export PLUGIN_TESTS_IMG=${PLUGIN_TESTS_REPO}:${PLUGIN_TESTS_VERSION}

export MGM_VERSION=${MGM_VERSION:-$VERSION}
export MGM_REPO=${MGM_REPO:-quay.io/opct/must-gather-monitoring}
export MGM_IMG=${MGM_REPO}:${MGM_VERSION}

export PLUGIN_COLLECTOR_REPO=${PLUGIN_COLLECTOR_REPO:-quay.io/opct/plugin-artifacts-collector}
export PLUGIN_COLLECTOR_IMG=${PLUGIN_COLLECTOR_REPO}:${PLUGIN_TESTS_VERSION}

########################
# Build functions
########################

# Building quay.io/opct/tools image.
# This image is built manually, and it's not part of the pipeline.
# When bumping tools shipped in this image, remember to update the version
# in the file tools/VERSION. The SemVer is used, in general we bump the minor (v0.y.0).
# to trigger a new build, run: make build WHAT=tools COMMAND=push
function build_tools() {
    local build_root
    build_root=$(dirname "$0")/tools
    img_name="${TOOLS_IMG}"
    manifest="${TOOLS_IMG}"

    echo "Removing manifest ${manifest} if exists..."
    podman manifest rm "${manifest}" || true

    echo "Creating manifests..."
    podman manifest create "${manifest}"

    echo -e "\n\n\t>> Building ${manifest}\n"
    for platform in $(echo "${PLATFORMS}" | tr ',' ' '); do
        echo -e "\n\n\t>> Building ${manifest} for ${platform}\n"
        TARGET_OS=$(echo "${platform}" | cut -d'/' -f1)
        TARGET_ARCH=$(echo "${platform}" | cut -d'/' -f2)
        BUILD_ARCH="$TARGET_OS-$TARGET_ARCH"

        jq_bin="jq-${BUILD_ARCH}"
        jq_version=1.7
        jq_url="https://github.com/jqlang/jq/releases/download/jq-${jq_version}/${jq_bin}"

        # yq_bin="yq_${TARGET_OS}_${TARGET_ARCH}"
        # yq_url="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${yq_bin}"

        # TODO: build CAMGI in other supported arches.
        # https://issues.redhat.com/browse/OPCT-275
        camgi_archive="camgi-0.9.0-linux-x86_64.tar"
        camgi_url="https://github.com/elmiko/camgi.rs/releases/download/v0.9.0/${camgi_archive}"

        ocp_version="stable-4.16"
        oc_archive="openshift-client-linux.tar.gz"
        oc_url="https://mirror.openshift.com/pub/openshift-v4/${TARGET_ARCH}/clients/ocp/${ocp_version}/${oc_archive}"

        podman build --platform "${platform}" \
            --manifest "${manifest}" \
            -f "${build_root}"/Containerfile \
            --build-arg=JQ_URL="${jq_url}" \
            --build-arg=JQ_BIN="${jq_bin}" \
            --build-arg=CAMGI_URL="${camgi_url}" \
            --build-arg=CAMGI_TAR="${camgi_archive}" \
            --build-arg=OC_TAR="${oc_archive}" \
            --build-arg=OC_URL="${oc_url}" \
            --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
            --build-arg=TARGETPLATFORM="${platform}" \
            --build-arg=TARGETARCH="${TARGET_ARCH}" \
            --build-arg=TARGETOS="${TARGET_OS}" \
            -t "${img_name}-${TARGET_OS}-${TARGET_ARCH}" "${build_root}"
    done

    if [[ "$COMMAND" == "push" ]]; then
        echo -e "\n\tPushing manifest ${manifest}...\n\n"
        podman manifest push "${manifest}" "docker://${manifest}"
    fi

    echo "#>>>>
Images built for platforms: ${PLATFORMS}
Manifest image: ${manifest}
<<<#"
}

# build_plugin_tests builds and push the openshift-tests-plugin container image.
function build_plugin_tests() {
    echo -e "\n\n\t>> Building openshift-tests-plugin image..."

    build_root=$(dirname "$0")/openshift-tests-plugin
    echo "${PLUGIN_TESTS_VERSION}" > "${build_root}"/VERSION
    img_name="${PLUGIN_TESTS_IMG}"
    manifest="quay.io/opct/plugin-openshift-tests:${PLUGIN_TESTS_VERSION}"

    echo -e "\n\t>> creating manifest for ${PLUGIN_TESTS_IMG}"

    echo "Removing manifest ${manifest} and imags if exists..."
    podman manifest rm "${manifest}" || true
    podman rmi --force "${manifest}" || true

    echo "Creating manifests..."
    podman manifest create "${manifest}"

    echo -e "\n\n\t>> Building ${manifest}\n"
    podman build -f "${build_root}"/Containerfile \
        --platform "${PLATFORMS}" \
        --manifest "${manifest}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        --build-arg=RELEASE_TAG="${PLUGIN_TESTS_VERSION}" \
        -t "${img_name}-buildx" "${build_root}"

    # Build to latest to be used in the artifacts collector (pipeline)
    local_image=localhost/plugin-openshift-tests:latest
    if [[ "${img_name}" != "${local_image}" ]]; then
        podman tag "${img_name}-buildx" "${local_image}"
    fi

    if [[ "$COMMAND" == "push" ]]; then
        echo -e "\n\tPushing manifest ${manifest}...\n\n"
        podman manifest push "${manifest}" "docker://${manifest}"
    fi

    echo "#>>>>
Images built for platforms: ${PLATFORMS}
Manifest image: ${manifest}
<<<#"
}

# build_collector builds and push the artifacts collector container image.
function build_collector() {
    build_root=$(dirname "$0")/artifacts-collector

    echo "${PLUGIN_TESTS_VERSION}" > "${build_root}"/VERSION
    img_name="${PLUGIN_COLLECTOR_IMG}"
    manifest="${PLUGIN_COLLECTOR_IMG}"

    echo "Removing manifest ${manifest} if exists..."
    podman manifest rm "${manifest}" || true

    echo "Creating manifests..."
    podman manifest create "${manifest}"

    echo -e "\n\n\t>> Building ${manifest}\n"
    podman build -f "${build_root}"/Containerfile \
        --platform "${PLATFORMS}" \
        --manifest "${manifest}" \
        --build-arg=PLUGIN_IMAGE="${PLUGIN_IMAGE_OVERRIDE:-${PLUGIN_TESTS_IMG}}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        --build-arg=RELEASE_TAG="${PLUGIN_TESTS_VERSION}" \
        --build-arg=TOOLS_VERSION="${TOOLS_VERSION}" \
        -t "${img_name}-buildx" "${build_root}"

    if [[ "$COMMAND" == "push" ]]; then
        echo -e "\n\tPushing manifest ${manifest}...\n\n"
        podman manifest push "${manifest}" "docker://${manifest}"
    fi

    echo "#>>>>
Images built for platforms: ${PLATFORMS}
Manifest image: ${manifest}
<<<#"
}

# build_mgm builds and push the must-gather-monitoring container image.
function build_mgm() {
    build_root=$(dirname "$0")/must-gather-monitoring

    echo "${MGM_VERSION}" > "${build_root}"/VERSION
    img_name="${MGM_IMG}"
    manifest="quay.io/opct/must-gather-monitoring:${MGM_VERSION}"

    echo "Removing manifest ${manifest} if exists..."
    podman manifest rm "${manifest}" || true

    echo "Creating manifests..."
    podman manifest create "${manifest}"

    echo -e "\n\n\t>> Building ${manifest}\n"
    podman build -f "${build_root}"/Containerfile \
        --platform "${PLATFORMS}" \
        --manifest "${manifest}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        -t "${img_name}-buildx" "${build_root}"

    if [[ "$COMMAND" == "push" ]]; then
        echo -e "\n\tPushing manifest ${manifest}...\n\n"
        podman manifest push "${manifest}" "docker://${manifest}"
    fi

    echo "#>>>>
Images built for platforms: ${PLATFORMS}
Manifest image: ${manifest}
<<<#"
}

function build_all() {
    build_plugin_tests
    build_collector
    build_mgm
}

function help() {
    echo "WHAT/App not mapped to build: $BUILD_IMG";
    echo "Valid values:
make build WHAT=tools COMMAND=build ARCH=linux-amd64
make build WHAT=plugin-openshift-tests COMMAND=build ARCH=linux-amd64
make build WHAT=must-gather-monitoring COMMAND=build ARCH=linux-amd64"
    exit 1
}

case $BUILD_IMG in
    "tools") build_tools ;;
    "plugin-openshift-tests") build_plugin_tests ;;
    "plugin-artifacts-collector") build_collector ;;
    "must-gather-monitoring") build_mgm ;;
    "all") build_all ;;
    *) help;;
esac
