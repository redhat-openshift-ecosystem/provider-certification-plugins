

.PHONY: clean
clean:
	rm ./openshift-tests-plugin

.PHONY: build
build:
	go build .

.PHONY: build-image
build-image:
	podman build -f Containerfile -t quay.io/opct/openshift-tests-plugin:latest .
