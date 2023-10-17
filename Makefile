
##############
# Formatting #
##############

PREFIX ?= v0.0.0-devel
VERSION ?= $(PREFIX)-$(shell git rev-parse --short HEAD)

ARCH ?= linux-amd64
EXPIRE ?= 1w
COMMAND ?= build
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
		./build.sh $(COMMAND) "$(WHAT)" $(ARCH)

#>> tools

.PHONY: build-tools
build-tools: WHAT = tools
build-tools: build

.PHONY: build-tools-linux-amd64
build-tools-linux-amd64: ARCH = linux-amd64
build-tools-linux-amd64: build-tools

.PHONY: build-tools-linux-arm64
build-tools-linux-arm64: ARCH = linux-arm64
build-tools-linux-arm64: build-tools

#>> plugin-tests

.PHONY: build-plugin-tests
build-plugin-tests: WHAT = plugin-openshift-tests
build-plugin-tests: build

.PHONY: build-plugin-tests-linux-amd64
build-plugin-tests-linux-amd64: ARCH = linux-amd64
build-plugin-tests-linux-amd64: build-plugin-tests

.PHONY: build-plugin-tests-linux-arm64
build-plugin-tests-linux-arm64: ARCH = linux-arm64
build-plugin-tests-linux-arm64: build-plugin-tests

#>> must-gather-montioring

.PHONY: build-must-gather-monitoring
build-must-gather-monitoring: WHAT = must-gather-monitoring
build-must-gather-monitoring: build

.PHONY: build-must-gather-monitoring-linux-amd64
build-must-gather-monitoring-linux-amd64: ARCH = linux-amd64
build-must-gather-monitoring-linux-amd64: build-must-gather-monitoring

.PHONY: build-must-gather-monitoring-linux-arm64
build-must-gather-monitoring-linux-arm64: ARCH = linux-arm64
build-must-gather-monitoring-linux-arm64: build-must-gather-monitoring

#> Build all by arch

.PHONY: build-arch-amd64
build-arch-amd64: ARCH = linux-amd64
build-arch-amd64:
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=tools
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=plugin-openshift-tests
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=must-gather-monitoring

.PHONY: build-push-arch-amd64
build-push-arch-amd64: COMMAND = push
build-push-arch-amd64: build-arch-amd64

.PHONY: build-arch-arm64
build-arch-arm64: ARCH = linux-arm64
build-arch-arm64:
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=tools
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=plugin-openshift-tests
	$(MAKE) build EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=must-gather-monitoring

.PHONY: build-push-arch-arm64
build-push-arch-arm64: COMMAND = push
build-push-arch-arm64: build-arch-arm64

##> Production release only

.PHONY: prod-build-push-arch-amd64
prod-build-push-arch-amd64: COMMAND = push
prod-build-push-arch-amd64: EXPIRE = never
prod-build-push-arch-amd64: build-arch-amd64

.PHONY: prod-build-push-arch-arm64
prod-build-push-arch-arm64: COMMAND = push
prod-build-push-arch-arm64: EXPIRE = never
prod-build-push-arch-arm64: build-arch-arm64

## Manifests

.PHONY: build-manifest
build-manifest:
	EXPIRE=$(EXPIRE) VERSION=$(VERSION) \
		hack/build-manifest.sh $(COMMAND) $(WHAT)

.PHONY: build-manifests
build-manifests:
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=tools
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=plugin-openshift-tests
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=must-gather-monitoring

.PHONY: push-manifests
push-manifests: COMMAND = push
push-manifests:
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=tools
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=plugin-openshift-tests
	$(MAKE) build-manifest EXPIRE=$(EXPIRE) ARCH=$(ARCH) COMMAND=$(COMMAND) WHAT=must-gather-monitoring

##> Production release only

.PHONY: prod-build-push-manifests
prod-build-push-manifests: EXPIRE = never
prod-build-push-manifests: push-manifests

.PHONY: remove-manifests
remove-manifests:
	podman manifest rm quay.io/opct/tools:$(TOOLS_VERSION) || true
	podman manifest rm quay.io/opct/plugin-openshift-tests:$(PLUGIN_TESTS_VERSION) || true
	podman manifest rm quay.io/opct/must-gather-monitoring:$(MGM_VERSION) || true

