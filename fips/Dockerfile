ARG KUBERNETES_BASE_IMAGE
FROM ${KUBERNETES_BASE_IMAGE} AS src

LABEL maintainer="vCluster Labs <support@vcluster.com>"
LABEL description="Kubernetes control plane components (apiserver, controller-manager, scheduler)"

FROM gcr.io/distroless/base-nossl:debug
COPY --from=src kubernetes/kube-apiserver /usr/local/bin/kube-apiserver
COPY --from=src kubernetes/kube-controller-manager /usr/local/bin/kube-controller-manager
COPY --from=src kubernetes/kube-scheduler /usr/local/bin/kube-scheduler
# Must be aligned with https://github.com/loft-sh/kubernetes/blob/main/Dockerfile#L30-L33
COPY --from=src kubernetes/kube-apiserver /kubernetes/kube-apiserver
COPY --from=src kubernetes/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=src kubernetes/kube-scheduler /kubernetes/kube-scheduler
