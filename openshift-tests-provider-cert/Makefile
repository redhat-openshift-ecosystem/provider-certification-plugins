
TS ?= $(shell date +%Y%m%d%H%M%S)
PREFIX ?= dev
VERSION ?= $(PREFIX)-$(shell date +%Y%m%d%H%M%S)
DEV_REGISTRY ?= quay.io/ocp-cert

all: build-plugin
.PHONY: all

build-plugin:
	VERSION=$(VERSION) hack/build-image.sh build-plugin
.PHONY: build-plugin

push-plugin:
	VERSION=$(VERSION) hack/build-image.sh push-plugin
.PHONY: push-plugin

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
	shellcheck plugin/*.sh hack/*.sh
.PHONY: test-shellcheck
