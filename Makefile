
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

.PHONY: build
all: build

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

#>> plugin-collector

.PHONY: build-plugin-collector
build-plugin-collector: WHAT = plugin-artifacts-collector
build-plugin-collector: build

#>> must-gather-montioring

.PHONY: build-must-gather-monitoring
build-must-gather-monitoring: WHAT = must-gather-monitoring
build-must-gather-monitoring: build

#>> all

.PHONY: images
images:
	$(MAKE) build-tools
	$(MAKE) build-plugin-tests
	$(MAKE) build-plugin-collector
	$(MAKE) build-must-gather-monitoring

##> tests openshift-tests-plugin

.PHONY: test-lint
test-lint:
	@echo "Running linting tools"
	# Download https://github.com/golangci/golangci-lint/releases/tag/v1.64.5
	# wget -O golangci-lint.tgz https://github.com/golangci/golangci-lint/releases/download/v1.64.5/golangci-lint-1.64.5-linux-amd64.tar.gz; tar xfvz golangci-lint.tgz
	cd openshift-tests-plugin && golangci-lint run --timeout=10m
	# shellcheck: hack/shellcheck.sh
	shellcheck ./build.sh ./openshift-tests-plugin/plugin/*.sh ./must-gather-monitoring/runner_plugin  ./must-gather-monitoring/collection-scripts/* hack/*.sh
	# yamllint: pip install yamllint
	yamllint .github/workflows/*.yaml

.PHONY: test
test:
	@echo "Running tests"
	$(MAKE) test-lint
	@echo "Running tests on openshift-tests-plugin"
	$(MAKE) -C openshift-tests-plugin test

.PHONY: test-ci-local
test-ci-local:
	# Depdends on act CLI
	# https://nektosact.com/installation/index.html
	@echo "Running build image workflow"
	SKIP_ANNOTATION=true act -j build-image pull_request

##> linters/format tests

.PHONY: format
format: shellcheck

.PHONY: shellcheck
shellcheck:
	hack/shellcheck.sh
