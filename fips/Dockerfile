ARG KUBERNETES_BASE_IMAGE
FROM ${KUBERNETES_BASE_IMAGE} AS src

LABEL maintainer="vCluster Labs <support@vcluster.com>"
LABEL description="Kubernetes control plane components (apiserver, controller-manager, scheduler)"

FROM gcr.io/distroless/base-nossl:debug
COPY --from=src out/* /usr/local/bin/kube-apiserver
COPY --from=src out/* /usr/local/bin/kube-controller-manager
COPY --from=src out/* /usr/local/bin/kube-scheduler
# Must be aligned with https://github.com/loft-sh/kubernetes/blob/main/Dockerfile#L30-L33
COPY --from=src out/* /kubernetes/kube-apiserver
COPY --from=src out/* /kubernetes/kube-controller-manager
COPY --from=src out/* /kubernetes/kube-scheduler
