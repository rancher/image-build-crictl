ARG GO_IMAGE=rancher/hardened-build-base:v1.22.7b1
FROM ${GO_IMAGE} as builder
# setup required packages
RUN set -x && \
    apk --no-cache add \
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
ENV GO_LDFLAGS="-linkmode=external -X ${PKG}/pkg/version.Version=${TAG}"
RUN go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o bin/crictl ./cmd/crictl
RUN go-assert-static.sh bin/*
RUN if [ "${ARCH}" = "amd64" ]; then \
        go-assert-boring.sh bin/* ; \
    fi
RUN install -s bin/* /usr/local/bin
RUN crictl --version

FROM scratch
COPY --from=builder /usr/local/bin/ /usr/local/bin/
