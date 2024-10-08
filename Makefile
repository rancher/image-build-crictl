SEVERITIES = HIGH,CRITICAL

UNAME_M = $(shell uname -m)
ARCH=
ifeq ($(UNAME_M), x86_64)
	ARCH=amd64
else ifeq ($(UNAME_M), aarch64)
	ARCH=arm64
else 
	ARCH=$(UNAME_M)
endif

BUILD_META=-build$(shell TZ=UTC date +%Y%m%d)
ORG ?= rancher
PKG ?= github.com/kubernetes-sigs/cri-tools
SRC ?= github.com/kubernetes-sigs/cri-tools
TAG ?= ${GITHUB_ACTION_TAG}

ifeq ($(TAG),)
TAG := v1.31.1$(BUILD_META)
endif

ifeq (,$(filter %$(BUILD_META),$(TAG)))
$(error TAG needs to end with build metadata: $(BUILD_META))
endif

GOLANG_VERSION := $(shell ./scripts/golang-version.sh $(TAG))

.PHONY: image-build
image-build:
	docker buildx build \
		--platform=$(ARCH) \
		--pull \
		--build-arg PKG=$(PKG) \
		--build-arg SRC=$(SRC) \
		--build-arg TAG=$(TAG:$(BUILD_META)=) \
 		--build-arg ARCH=$(ARCH) \
		--tag $(ORG)/hardened-crictl:$(TAG) \
		--tag $(ORG)/hardened-crictl:$(TAG)-$(ARCH) \
		--load \
	.

.PHONY: image-push
image-push:
	docker push $(ORG)/hardened-crictl:$(TAG)-$(ARCH)

.PHONY: image-scan
image-scan:
	trivy --severity $(SEVERITIES) --no-progress --ignore-unfixed $(ORG)/hardened-crictl:$(TAG)

.PHONY: log
log:
	@echo "ARCH=$(ARCH)"
	@echo "TAG=$(TAG:$(BUILD_META)=)"
	@echo "ORG=$(ORG)"
	@echo "PKG=$(PKG)"
	@echo "SRC=$(SRC)"
	@echo "BUILD_META=$(BUILD_META)"
	@echo "UNAME_M=$(UNAME_M)"
	@echo "GOLANG_VERSION=$(GOLANG_VERSION)"
