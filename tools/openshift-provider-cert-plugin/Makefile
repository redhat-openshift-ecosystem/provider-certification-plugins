
VERSION ?= $(shell date +%Y%m%d%H%M%S)
DEV_REGISTRY ?= quay.io/ocp-cert

all: build
.PHONY: all

build-ci:
	hack/build-image.sh build-plugin
.PHONY: build-ci

build-dev:
	VERSION_DEVEL=devel REGISTRY_PLUGIN=$(DEV_REGISTRY) hack/build-image.sh build-dev
.PHONY: build-dev

release:
	VERSION_PLUGIN=$(VERSION) hack/build-image.sh release
.PHONY: release

test:
	hack/test_runner.sh
.PHONY: test

test-shellcheck:
	shellcheck *.sh hack/*.sh
.PHONY: test-shellcheck
