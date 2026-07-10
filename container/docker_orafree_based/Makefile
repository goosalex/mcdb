PANTA_DIR := $(shell git rev-parse --show-toplevel)

CONTEXT := $(PANTA_DIR)
CONTAINER_NAME := osdb/local_ora_mcdb
PLATFORM := linux/amd64

BUILDKIT_ENABLED := False
include $(PANTA_DIR)/configs/Makefile.buildkit

# split off the major version part as MCDB_TAG for an easy stable tag
MCDB_TAG := $(word 1,$(subst ., ,$(VERSION)))
MCDB_CONTAINER_TAG := $(REPOSITORY)/$(CONTAINER_NAME):$(MCDB_TAG)


# runs docker build
.PHONY: build
build:
	$(BUILD_CMD)

# runs docker build --target test
.PHONY: test
test:
	$(TEST_CMD)

# OSBE docker sidecar does not yet use buildx,
# so the Makefile.buildkit fallback does not work here.
# kaeter will call build and test. We just do push here.
.PHONY: release
release:
	docker push $(CONTAINER_TAG)
	docker tag $(CONTAINER_TAG) $(MCDB_CONTAINER_TAG)
	docker push $(MCDB_CONTAINER_TAG)

.PHONY: snapshot
snapshot: build
	docker push $(CONTAINER_TAG)

# To run it locally with a bash:
.PHONY: run
run:
	docker run -it --rm --entrypoint=/bin/bash --platform=linux/amd64 $(CONTAINER_TAG)
