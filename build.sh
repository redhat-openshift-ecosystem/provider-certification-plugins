#!/usr/bin/env bash

# Mirror jq image to OPCT repo.

set -o pipefail
set -o nounset
set -o errexit

COMMAND=${1}; shift
BUILD_IMG=${1}; shift
BUILD_ARCH=${1};

# shellcheck disable=SC1091
source "$(dirname "$0")/build.env"

declare -g TARGET_OS
declare -g TARGET_ARCH
case $BUILD_ARCH in
    "linux-amd64")
        TARGET_OS=linux;
        TARGET_ARCH=amd64;
        ;;
    "linux-arm64")
        TARGET_OS=linux;
        TARGET_ARCH=arm64;
        ;;
    "linux-ppc64le")
        TARGET_OS=linux;
        TARGET_ARCH=ppc64le;
        ;;
    "linux-s390x")
        TARGET_OS=linux;
        TARGET_ARCH=s390x;
        ;;
    *) echo "ERROR: invalid architecture [${BUILD_ARCH}]"; exit 1;;
esac

function push_image() {
    img_name=$1
    if [[ $COMMAND == "push" ]]; then
        podman push "${img_name}";
    fi
}

function build_tools() {

    build_root=$(dirname "$0")/tools

    jq_bin="jq-${BUILD_ARCH}"
    jq_url="https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${jq_bin}"

    # TODO: build CAMGI in other supported arches.
    # https://issues.redhat.com/browse/OPCT-275
    camgi_archive="camgi-0.9.0-linux-x86_64.tar"
    camgi_url="https://github.com/elmiko/camgi.rs/releases/download/v0.9.0/${camgi_archive}"

    ocp_version=4.13.3
    oc_archive="openshift-client-linux.tar.gz"
    oc_url="https://mirror.openshift.com/pub/openshift-v4/${TARGET_ARCH}/clients/ocp/${ocp_version}/${oc_archive}"

    img_name="${TOOLS_IMG}-${BUILD_ARCH}"
    echo "${TOOLS_VERSION}" > "${build_root}"/VERSION
    podman build --platform "${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        -f "${build_root}"/Containerfile \
        --build-arg=JQ_URL="${jq_url}" \
        --build-arg=JQ_BIN="${jq_bin}" \
        --build-arg=CAMGI_URL="${camgi_url}" \
        --build-arg=CAMGI_TAR="${camgi_archive}" \
        --build-arg=OC_TAR="${oc_archive}" \
        --build-arg=OC_URL="${oc_url}" \
        --build-arg=SONOBUOY_VERSION="${SONOBUOY_VERSION}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        --build-arg=TARGETPLATFORM="${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        --build-arg=TARGETARCH="${TARGET_ARCH}" \
        --build-arg=TARGETOS="${TARGET_OS}" \
        -t "${img_name}" "${build_root}"

    push_image "${img_name}"
}

function build_plugin_tests() {

    build_root=$(dirname "$0")/openshift-tests-provider-cert

    echo "${PLUGIN_TESTS_VERSION}" > "${build_root}"/VERSION
    img_name="${PLUGIN_TESTS_IMG}-${BUILD_ARCH}"
    podman build --platform "${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        -f "${build_root}"/Containerfile \
        --build-arg=TOOLS_IMG="${TOOLS_IMG}-${BUILD_ARCH}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        --build-arg=TARGETPLATFORM="${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        --build-arg=TARGETARCH="${TARGET_ARCH}" \
        --build-arg=TARGETOS="${TARGET_OS}" \
        -t "${img_name}" "${build_root}"

    push_image "${img_name}"
}

function build_mgm() {
    
    build_root=$(dirname "$0")/must-gather-monitoring

    echo "${MGM_VERSION}" > "${build_root}"/VERSION
    img_name="${MGM_IMG}-${BUILD_ARCH}"
    podman build --platform "${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        -f "${build_root}"/Containerfile \
        --build-arg=TOOLS_IMG="${TOOLS_IMG}-${BUILD_ARCH}" \
        --build-arg=QUAY_EXPIRATION="${IMAGE_EXPIRE_TIME}" \
        --build-arg=TARGETPLATFORM="${BUILD_PLATFORMS[$BUILD_ARCH]}" \
        --build-arg=TARGETARCH="${TARGET_ARCH}" \
        --build-arg=TARGETOS="${TARGET_OS}" \
        -t "${img_name}" "${build_root}"

    if [[ $COMMAND == "push" ]]; then
        podman push "${img_name}";
    fi
}

function help() {
    echo "WHAT/App not mapped to build: $BUILD_IMG";
    echo "Valid values:
make build WHAT=tools COMMAND=build ARCH=linux-amd64
make build WHAT=pugin-openshift-tests COMMAND=build ARCH=linux-amd64
make build WHAT=must-gather-monitoring COMMAND=build ARCH=linux-amd64"
    exit 1
}

case $BUILD_IMG in
    "tools") build_tools;;
    "plugin-openshift-tests") build_plugin_tests;;
    "must-gather-monitoring") build_mgm;;
    *) help;;
esac