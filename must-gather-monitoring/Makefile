
CMD_CNT ?= podman
IMAGE_NAME ?= quay.io/opct/must-gather-monitoring
VERSION ?= $(shell git rev-parse --short HEAD)-$(shell date +%Y%m%d%H%M%S)

.PHONY: all
all: build-image

.PHONY: build-image
build-image:
	@echo "\n>> Build image: $(IMAGE_NAME):$(VERSION)"
	$(CMD_CNT) build -f Containerfile -t $(IMAGE_NAME):$(VERSION) .
	@echo "Build success! When you are ready to push:"
	@echo "export IMG=$(IMAGE_NAME):$(VERSION)"