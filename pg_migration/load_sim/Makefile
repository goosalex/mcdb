PANTA_DIR := $(shell git rev-parse --show-toplevel)

CONTEXT := $(PANTA_DIR)
CONTAINER_NAME := osdb/tunnel_load
PLATFORM := linux/amd64

BUILDKIT_ENABLED := False
include $(PANTA_DIR)/configs/Makefile.buildkit

VERSION="snapshot"

.PHONY: build test snapshot release
# runs docker build
build:
	$(BUILD_CMD)

# runs docker build --target test
.PHONY: test
test:
	@echo "nothing to do"

.PHONY: release
release:
    docker tag $(CONTAINER_TAG)
	docker push $(CONTAINER_TAG)

.PHONY: snapshot


snapshot: build release


# To run it locally with a bash:
.PHONY: run
run: build
	docker run -it --rm --entrypoint=/bin/bash --platform=linux/amd64 $(CONTAINER_TAG)
