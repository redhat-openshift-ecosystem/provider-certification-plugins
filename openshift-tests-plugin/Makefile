
IMG ?=  quay.io/opct/openshift-tests-plugin
VERSION = v0.0.0-devel
COMMIT = $(shell git rev-parse --short HEAD)
GO_BUILD_FLAGS ?= -ldflags "-s \
	-X github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/version.version=$(VERSION) \
	-X github.com/redhat-openshift-ecosystem/provider-certification-plugins/openshift-tests-plugin/pkg/version.commit=$(COMMIT) \
	"
GOOS ?= linux
GOARCH ?= amd64

.PHONY: clean
clean:
	rm ./openshift-tests-plugin

.PHONY: build
build:
	GOOS=$(GOOS) GOARCH=$(GOARCH) go build $(GO_BUILD_FLAGS) . \
		&& strip ./openshift-tests-plugin

.PHONY: build-image
build-image:
	podman manifest rm $(IMG):latest || true
	podman manifest create $(IMG):latest
	podman build --platform linux/amd64,linux/arm64 -f Containerfile --manifest $(IMG):latest .

.PHONY: push-image
push-image:
	podman manifest push $(IMG):latest

.PHONY: test
test:
	go test ./...
