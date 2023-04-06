ARG BCI_IMAGE=registry.suse.com/bci/bci-base:15.3.17.20.12
ARG GO_IMAGE=rancher/hardened-build-base:1.20.3b1
FROM ${BCI_IMAGE} as bci
FROM ${GO_IMAGE} as builder
# setup required packages
RUN set -x \
 && apk --no-cache add \
    file \
    gcc \
    git \
    libselinux-dev \
    libseccomp-dev \
    make
# setup the build
ARG PKG="github.com/kubernetes-sigs/cri-tools"
ARG SRC="github.com/kubernetes-sigs/cri-tools"
ARG TAG="v1.26.1"
ARG ARCH="amd64"
RUN git clone --depth=1 https://${SRC}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git fetch --all --tags --prune
RUN git checkout tags/${TAG} -b ${TAG}
ENV GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.Version=${TAG}"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN go-assert-static.sh bin/*
RUN if [ "${ARCH}" != "s390x" ]; then \
      go-assert-boring.sh bin/* ; \
    fi
RUN install -s bin/* /usr/local/bin
RUN crictl --version

FROM bci
COPY --from=builder /usr/local/bin/ /usr/local/bin/
