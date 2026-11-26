# Builds the Kubernetes binaries from source with K8S_GO_DEP_PINS applied, for
# the non-FIPS release when an overlay pins Go dependencies. download.sh uses
# it in place of the upstream binaries from dl.k8s.io.
#
# It builds in upstream's own kube-cross image (KUBE_CROSS_VERSION comes from
# build/build-image/cross/VERSION of the release), so the Go version, the glibc
# kubelet links against and the static/cgo choice per binary match the
# dl.k8s.io binaries; only the pinned dependencies differ.
ARG KUBE_CROSS_VERSION
FROM --platform=$BUILDPLATFORM registry.k8s.io/build-image/kube-cross:${KUBE_CROSS_VERSION} AS build

# No defaults: download.sh always passes them, and a fallback would build a stale release.
ARG KUBERNETES_VERSION
ARG K8S_GO_DEP_PINS
ARG TARGETARCH

RUN git -c advice.detachedHead=false clone -b "$KUBERNETES_VERSION" --depth=1 https://github.com/kubernetes/kubernetes.git /src/kubernetes
WORKDIR /src/kubernetes

COPY pin-go-deps.sh /
RUN /pin-go-deps.sh "$K8S_GO_DEP_PINS"

RUN set -ex; \
  SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct)"; \
  export SOURCE_DATE_EPOCH; \
  export KUBE_BUILD_PLATFORMS="linux/${TARGETARCH}"; \
  export KUBE_GIT_VERSION="${KUBERNETES_VERSION}" KUBE_GIT_TREE_STATE=clean; \
  make WHAT="cmd/kube-apiserver cmd/kube-controller-manager cmd/kube-scheduler cmd/kubelet cmd/kubeadm cmd/kubectl"; \
  mkdir /out; \
  mv _output/local/bin/linux/${TARGETARCH}/kube-apiserver \
     _output/local/bin/linux/${TARGETARCH}/kube-controller-manager \
     _output/local/bin/linux/${TARGETARCH}/kube-scheduler \
     _output/local/bin/linux/${TARGETARCH}/kubelet \
     _output/local/bin/linux/${TARGETARCH}/kubeadm \
     _output/local/bin/linux/${TARGETARCH}/kubectl /out/

FROM scratch
COPY --from=build /out/ /
