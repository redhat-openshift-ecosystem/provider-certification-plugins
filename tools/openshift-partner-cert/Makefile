
IMAGE_REGISTRY ?= quay.io/mrbraga
PULL_SECRET ?= $(HOME)/.openshift/pull-secret-latest.json
TESTS_DIR ?= "./tmp/origin"
TESTS_REPO ?= "git@github.com:openshift/origin.git"

get-tests:
	rm -rf $(TESTS_DIR)
	git clone $(TESTS_REPO) $(TESTS_DIR)

build-tests:
	pushd ./tmp/origin && make && popd

build-image-tests:
	cd ./tmp/origin
	podman build \
    	--authfile $(PULL_SECRET) \
    	-t openshift-tests:latest \
    	-f images/tests/Dockerfile.rhel .
	popd

build-image-plugin:
	podman build -t $(IMAGE_REGISTRY)/openshift-partner-cert:latest .

push-image-plugin:
	podman push $(IMAGE_REGISTRY)/openshift-partner-cert:latest

update-tests: get-tests build-tests
update-image-tests: get-tests build-image-tests build-image-plugin push-image-plugin
