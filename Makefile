
##############
# Formatting #
##############

PREFIX ?= v0.0.0-devel
VERSION ?= $(PREFIX)-$(shell git rev-parse --short HEAD)

PLATFORMS ?= linux/amd64,linux/arm64
EXPIRE ?= 12h
COMMAND ?= build
WHAT ?= tools
# To create production images: make target VERSION_PREFIX='' EXPIRE=never

.PHONY: format
format: shellcheck

.PHONY: shellcheck
shellcheck:
	hack/shellcheck.sh

#> Build app

.PHONY: build
build:
	EXPIRE=$(EXPIRE) VERSION=$(VERSION) \
		./build.sh "$(COMMAND)" "$(WHAT)" "$(PLATFORMS)"

#>> tools
# tools release is build manually.
.PHONY: build-tools
build-tools: WHAT = tools
build-tools: build

.PHONY: build-tools-release
build-tools-release: WHAT = tools
build-tools-release: EXPIRES = never
build-tools-release: VERSION = $(shell cat tools/VERSION)
build-tools-release: build

#>> plugin-tests

.PHONY: build-plugin-tests
build-plugin-tests: WHAT = plugin-openshift-tests
build-plugin-tests: build

#>> must-gather-montioring

.PHONY: build-must-gather-monitoring
build-must-gather-monitoring: WHAT = must-gather-monitoring
build-must-gather-monitoring: build

.PHONY: images
images:
	$(MAKE) build-tools
	$(MAKE) build-plugin-tests
	$(MAKE) build-must-gather-monitoring
