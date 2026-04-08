# Final Alpine-based image
FROM alpine:3.23
ARG TARGETARCH

LABEL maintainer="Loft Labs Inc <support@loft.sh>"
LABEL description="Kubernetes control plane components (apiserver, controller-manager, scheduler)"

# Install necessary packages
RUN apk --no-cache add \
      ca-certificates bash curl tzdata \
    && addgroup -g 1000 kubernetes \
    && adduser -D -u 1000 -G kubernetes kubernetes \
    && mkdir -p /kubernetes \
    && chown -R kubernetes:kubernetes /kubernetes

# Copy binaries from each component
COPY --chown=kubernetes:kubernetes ./kube-apiserver-${TARGETARCH} /kubernetes/kube-apiserver
COPY --chown=kubernetes:kubernetes ./kube-controller-manager-${TARGETARCH} /kubernetes/kube-controller-manager
COPY --chown=kubernetes:kubernetes ./kube-scheduler-${TARGETARCH} /kubernetes/kube-scheduler
COPY --chown=kubernetes:kubernetes ./helm-${TARGETARCH} /kubernetes/helm
COPY --chown=kubernetes:kubernetes ./etcd-${TARGETARCH} /kubernetes/etcd
COPY --chown=kubernetes:kubernetes ./etcdctl-${TARGETARCH} /kubernetes/etcdctl
COPY --chown=kubernetes:kubernetes ./kine-${TARGETARCH} /kubernetes/kine
COPY --chown=kubernetes:kubernetes ./konnectivity-server-${TARGETARCH} /kubernetes/konnectivity-server
COPY --chown=kubernetes:kubernetes ./kubernetes-*-amd64.tar.gz /kubernetes/
COPY --chown=kubernetes:kubernetes ./kubernetes-*-arm64.tar.gz /kubernetes/

# Set up the container
WORKDIR /
USER kubernetes
