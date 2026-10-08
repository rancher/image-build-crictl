ARG GO_IMAGE=rancher/hardened-build-base:v1.26.9b1
# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
# copy xx scripts to the build stage
COPY --from=xx / /
RUN apk add --no-cache file make git clang lld llvm
ARG TARGETPLATFORM
RUN set -x && \
    xx-info env &&\
    xx-apk --no-cache add musl-dev gcc \
    libselinux-dev \
    libseccomp-dev 

# setup the build
ARG PKG="github.com/kubernetes-sigs/cri-tools"
ARG TAG
RUN git clone --depth=1 https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
RUN set -x; \
    TAG_MINOR=$(echo ${TAG} | awk -F. '{printf "%s.%s.\n", $1, $2}'); \
    K8S_VERSION=$(curl -sL https://proxy.golang.org/k8s.io/kubernetes/@v/list | grep -v - | grep ${TAG_MINOR} | sort -V | tail -n 1); \
    K8S_VERSION_MOD=$(echo ${K8S_VERSION} | awk -F. '{printf "v0.%s.%s\n", $2, $3}'); \
    go mod edit -replace github.com/docker/docker=github.com/docker/docker@v27.1.1+incompatible -replace k8s.io/kubernetes=k8s.io/kubernetes@${K8S_VERSION}; \
    for MODULE in $(go mod edit --json | jq -r '.Replace[] | select(.Old.Path | test("^k8s.io/")) | select(.Old.Path | test("^k8s.io/(kubernetes|klog|utils|kube-openapi)") | not) | .Old.Path'); do go mod edit --replace ${MODULE}=${MODULE}@${K8S_VERSION_MOD}; done; \
    for MODULE in $(go mod edit --json | jq -r '.Require[] | select(.Path | test("^k8s.io/")) | select(.Path | test("^k8s.io/(kubernetes|klog|utils|kube-openapi)") | not) | .Path'); do go mod edit --require ${MODULE}@${K8S_VERSION_MOD}; done; \
    go mod tidy && go mod vendor
COPY go-mod-overrides ./go-mod-overrides
RUN go-mod-overrides.sh ./go-mod-overrides
RUN go mod download

ARG TARGETARCH
RUN xx-go --wrap && \
    GO_LDFLAGS="-linkmode=external -X $(awk '/^module /{print $2}' go.mod)/pkg/version.Version=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN xx-verify --static bin/* && \
    go-assert-static.sh bin/*
RUN if [ "$(xx-info arch)" = "amd64" ]; then \
        go-assert-boring.sh bin/* ; \
    fi
# llvm-strip is arch-agnostic, where gnu strip needs to running on target arch
RUN llvm-strip bin/*
RUN install bin/* /usr/local/bin

FROM scratch
COPY --from=builder /usr/local/bin/ /usr/local/bin/
