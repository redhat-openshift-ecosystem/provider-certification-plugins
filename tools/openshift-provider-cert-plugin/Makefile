
all: build
.PHONY: all

generate-openshift-tests:
	hack/generate-tests-tiers.sh
.PHONY: generate-openshift-tests

build: generate-openshift-tests
	hack/build-image.sh
.PHONY: build

test:
	hack/test_runner.sh
.PHONY: test
