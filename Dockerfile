ARG GO_IMAGE=rancher/hardened-build-base:v1.25.0b1
FROM ${GO_IMAGE} as builder
# setup required packages
RUN set -x && \
    apk --no-cache add \
    jq \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    make
# setup the build
ARG PKG="github.com/kubernetes-sigs/cri-tools"
ARG SRC="github.com/kubernetes-sigs/cri-tools"
ARG TAG="v1.31.0"
ARG ARCH="amd64"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
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
RUN GO_LDFLAGS="-linkmode=external -X $(awk '/^module /{print $2}' go.mod)/pkg/version.Version=${TAG}" \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN go-assert-static.sh bin/*
RUN if [ "${ARCH}" = "amd64" ]; then \
        go-assert-boring.sh bin/* ; \
    fi
RUN install -s bin/* /usr/local/bin
RUN crictl --version

FROM scratch
COPY --from=builder /usr/local/bin/ /usr/local/bin/
