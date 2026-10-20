PANTA_DIR := $(shell git rev-parse --show-toplevel)

CONTEXT := $(PANTA_DIR)
CONTAINER_NAME := osdb/local_ora_mcdb_arm
PLATFORM := linux/arm64

BUILDKIT_ENABLED := False
include $(PANTA_DIR)/configs/Makefile.buildkit

# split off the major version part as MCDB_TAG for an easy stable tag
MCDB_TAG := $(word 1,$(subst ., ,$(VERSION)))
MCDB_CONTAINER_TAG := $(REPOSITORY)/$(CONTAINER_NAME):$(MCDB_TAG)


.PHONY: build
build:
	$(BUILD_CMD)

.PHONY: test
test:
	$(TEST_CMD)

# Commands run local
.PHONY: release
release:
	docker push $(CONTAINER_TAG)
	docker tag $(CONTAINER_TAG) $(MCDB_CONTAINER_TAG)
	docker push $(MCDB_CONTAINER_TAG)

.PHONY: snapshot
snapshot: build
	@echo "no snapshots"

# To run it locally with a bash:
.PHONY: run
run:
	docker run -it --rm --entrypoint=/bin/bash --platform=linux/arm64 $(CONTAINER_TAG)

.PHONY: start
start:
	docker run --rm -p 1521:1521 --platform=linux/arm64 $(CONTAINER_TAG)
