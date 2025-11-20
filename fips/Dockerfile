ARG GO_VERSION=1.24
FROM docker.io/library/golang:${GO_VERSION}-bookworm AS build

LABEL maintainer="vCluster Labs <support@vcluster.com>"
LABEL description="Kubernetes control plane components (apiserver, controller-manager, scheduler)"

ARG KUBERNETES_VERSION=1.33.0
ARG KUBERNETES_BINS="kube-apiserver kube-controller-manager kube-scheduler"

RUN apt-get update -y && \
  apt-get install -y --no-install-recommends \
  git \
  rsync \
  grep \
  coreutils \
  gcc;

RUN  mkdir -p "$GOPATH/src/github.com/kubernetes/kubernetes"; \
  git -c advice.detachedHead=false clone -b "v$KUBERNETES_VERSION" --depth=1 https://github.com/kubernetes/kubernetes.git "$GOPATH/src/github.com/kubernetes/kubernetes"

WORKDIR /go/src/github.com/kubernetes/kubernetes

ARG BUILD_GO_TAGS="providerless"
ARG BUILD_GO_FLAGS="-v"
ARG BUILD_GO_LDFLAGS_EXTRA

COPY base-images/go-assert-fips.sh /

RUN \
  set -ex; \
  export GOPATH=/go; \
  commands="${KUBERNETES_BINS}"; \
  # Ensure that all of the binaries are built with CGO \
  export CGO_ENABLED=1; \
  export KUBE_CGO_OVERRIDES="$commands"; \
  export GOFIPS140=v1.0.0; \
  mkdir /out; \
  SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct || date -u +%s)"; \
  export SOURCE_DATE_EPOCH; \
  export FORCE_HOST_GO=y; \
  export KUBE_VERBOSE=9; \
  export KUBE_GIT_VERSION="v$KUBERNETES_VERSION+loft-fips"; \
  export KUBE_GIT_TREE_STATE="clean"; \
  for cmd in $commands; do \
  make GOFLAGS="${BUILD_GO_FLAGS} -tags=${BUILD_GO_TAGS}" GOLDFLAGS="${BUILD_GO_LDFLAGS_EXTRA}" WHAT="cmd/$cmd" DBG=1; \
  mv /go/src/github.com/kubernetes/kubernetes/_output/local/bin/*/*/"$cmd" /out/; \
  /go-assert-fips.sh /out/$cmd; \
  done

FROM gcr.io/distroless/base-nossl:debug
COPY --from=build out/* /usr/local/bin/
# Must be aligned with https://github.com/loft-sh/kubernetes/blob/main/Dockerfile#L30-L33
COPY --from=build out/* /kubernetes/
