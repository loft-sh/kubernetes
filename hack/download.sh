# Default versions
KUBERNETES_VERSION=""
PAUSE_IMAGE_VERSION=""
CNI_BINARIES_VERSION="v1.6.0"
CONTAINERD_VERSION=""
RUNC_VERSION=""
CRICTL_VERSION="v1.33.0"
HELM_VERSION=""
ETCD_VERSION=""
KINE_VERSION=""
KONNECTIVITY_VERSION=""
TAILSCALED_VERSION="v1.78.1-loft.11"
TARGETARCH="amd64"

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --kubernetes-version)
      KUBERNETES_VERSION="$2"
      shift 2
      ;;
    --target-arch)
      TARGETARCH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --kubernetes-version <version>"
      exit 1
      ;;
  esac
done

# Kubernetes version is required
if [ -z "$KUBERNETES_VERSION" ]; then
  echo "Error: --kubernetes-version is required"
  echo "Usage: $0 --kubernetes-version <version>"
  exit 1
fi

# Trim kubernetes patch version to check if there is a file with that name
KUBERNETES_VERSION_TRIMMED=$(echo ${KUBERNETES_VERSION} | sed -E 's/^(v[0-9]+\.[0-9]+)\.[0-9]+$/\1/')
if [ ! -f "./kubernetes-${KUBERNETES_VERSION_TRIMMED}" ]; then
  echo "Error: kubernetes-${KUBERNETES_VERSION_TRIMMED} file does not exist"
  exit 1
fi

 # load the versions from the file
source ./kubernetes-${KUBERNETES_VERSION_TRIMMED}

# containerd version
if [ -z "$CONTAINERD_VERSION" ]; then
  echo "Error: containerd-version is required"
  exit 1
fi

# runc version
if [ -z "$RUNC_VERSION" ]; then
  echo "Error: runc-version is required"
  exit 1
fi

# helm version
if [ -z "$HELM_VERSION" ]; then
  echo "Error: helm-version is required"
  exit 1
fi

# etcd version
if [ -z "$ETCD_VERSION" ]; then
  echo "Error: etcd-version is required"
  exit 1
fi

# kine version
if [ -z "$KINE_VERSION" ]; then
  echo "Error: kine-version is required"
  exit 1
fi

# konnectivity version
if [ -z "$KONNECTIVITY_VERSION" ]; then
  echo "Error: konnectivity-version is required"
  exit 1
fi

# pause image version
if [ -z "$PAUSE_IMAGE_VERSION" ]; then
  echo "Error: pause-image-version is required"
  exit 1
fi

# Create the directory for the binaries
mkdir -p ./release

# Download kubeadm, kubelet, and kubectl
echo "Downloading kubeadm ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kubeadm "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kubeadm"; then
  echo "Error: failed to download kubeadm ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kubeadm
mv kubeadm ./release/kubeadm
echo "Downloading kubelet ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kubelet "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kubelet"; then
  echo "Error: failed to download kubelet ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kubelet
mv kubelet ./release/kubelet
echo "Downloading kubectl ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kubectl "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kubectl"; then
  echo "Error: failed to download kubectl ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kubectl
mv kubectl ./release/kubectl

# Install CNI plugins
echo "Downloading CNI plugins ${CNI_BINARIES_VERSION}..."
if ! curl -fsS -L -o cni.tgz "https://github.com/containernetworking/plugins/releases/download/${CNI_BINARIES_VERSION}/cni-plugins-linux-${TARGETARCH}-${CNI_BINARIES_VERSION}.tgz"; then
  echo "Error: failed to download CNI plugins ${CNI_BINARIES_VERSION} for ${TARGETARCH}"
  exit 1
fi
mkdir cni
tar -zxf cni.tgz -C cni
mkdir -p ./release/cni/bin
mv cni/loopback ./release/cni/bin
mv cni/portmap ./release/cni/bin
mv cni/bandwidth ./release/cni/bin
mv cni/bridge ./release/cni/bin
mv cni/firewall ./release/cni/bin
mv cni/host-local ./release/cni/bin
rm cni.tgz
rm -rf cni

# Download containerd & runc
echo "Downloading containerd ${CONTAINERD_VERSION}..."
if ! curl -fsS -L -o containerd.tgz "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${TARGETARCH}.tar.gz"; then
  echo "Error: failed to download containerd ${CONTAINERD_VERSION} for ${TARGETARCH}"
  exit 1
fi
tar -zxf containerd.tgz bin
chmod +x bin/containerd-shim-runc-v2
mv bin/containerd-shim-runc-v2 ./release/containerd-shim-runc-v2
chmod +x bin/containerd
mv bin/containerd ./release/containerd
chmod +x bin/ctr
mv bin/ctr ./release/ctr
rm containerd.tgz
rm -rf bin
echo "Downloading runc ${RUNC_VERSION}..."
if ! curl -fsS -L -o runc "https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${TARGETARCH}"; then
  echo "Error: failed to download runc ${RUNC_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x runc
mv runc ./release/runc

# Download crictl
echo "Downloading crictl ${CRICTL_VERSION}..."
if ! curl -fsS -L "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz" --output "crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz"; then
  echo "Error: failed to download crictl ${CRICTL_VERSION} for ${TARGETARCH}"
  exit 1
fi
tar -zxf crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz -C ./release
rm -f crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz

# Download vcluster-tunnel
echo "Downloading vcluster-tunnel ${TAILSCALED_VERSION}..."
if ! curl -fsS -L -o vcluster-tunnel "https://github.com/loft-sh/tailscale/releases/download/${TAILSCALED_VERSION}/tailscaled-linux-${TARGETARCH}"; then
  echo "Error: failed to download vcluster-tunnel ${TAILSCALED_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x ./vcluster-tunnel
mv ./vcluster-tunnel ./release/vcluster-tunnel

# Download pause image
echo "Downloading pause image ${PAUSE_IMAGE_VERSION}..."
docker pull --platform=linux/${TARGETARCH} registry.k8s.io/pause:${PAUSE_IMAGE_VERSION}
docker save -o ./release/pause-image.tar registry.k8s.io/pause:${PAUSE_IMAGE_VERSION}
echo "registry.k8s.io/pause:${PAUSE_IMAGE_VERSION}" > ./release/pause-image.txt

# Pack the release folder into a tar.gz file
echo "Packing the release folder into kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}.tar.gz..."
tar -zcf kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}.tar.gz ./release

# Write the notes to a file
cat <<EOF > ./kubernetes-${KUBERNETES_VERSION}.txt
This release contains required binaries for Kubernetes ${KUBERNETES_VERSION}.

For more details on what's new, see the [Kubernetes release notes](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}).

## Component Versions
| Component | Version |
|---|---|
| Kube ApiServer | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| Kube Controller Manager | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| Kube Scheduler | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| Helm | [${HELM_VERSION}](https://github.com/helm/helm/releases/tag/${HELM_VERSION}) |
| Etcd | [${ETCD_VERSION}](https://github.com/etcd-io/etcd/releases/tag/${ETCD_VERSION}) |
| Kine | [${KINE_VERSION}](https://github.com/loft-sh/kine/releases/tag/${KINE_VERSION}) |
| Konnectivity | [${KONNECTIVITY_VERSION}](https://github.com/kubernetes-sigs/apiserver-network-proxy/releases/tag/${KONNECTIVITY_VERSION}) |
| Kubeadm | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| Kubelet | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| Kubectl | [${KUBERNETES_VERSION}](https://github.com/kubernetes/kubernetes/releases/tag/${KUBERNETES_VERSION}) |
| CNI Binaries | [${CNI_BINARIES_VERSION}](https://github.com/containernetworking/plugins/releases/tag/${CNI_BINARIES_VERSION}) |
| Containerd | [v${CONTAINERD_VERSION}](https://github.com/containerd/containerd/releases/tag/v${CONTAINERD_VERSION}) |
| Runc | [${RUNC_VERSION}](https://github.com/opencontainers/runc/releases/tag/${RUNC_VERSION}) |
| Crictl | [${CRICTL_VERSION}](https://github.com/kubernetes-sigs/cri-tools/releases/tag/${CRICTL_VERSION}) |
| Pause Image | registry.k8s.io/pause:${PAUSE_IMAGE_VERSION} |
EOF

# delete the release folder
rm -rf ./release

# Create the directory for the control plane binaries again
mkdir -p ./release

# Download kube-apiserver
echo "Downloading kube-apiserver ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kube-apiserver "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kube-apiserver"; then
  echo "Error: failed to download kube-apiserver ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kube-apiserver
cp kube-apiserver ./kube-apiserver-${TARGETARCH}
mv kube-apiserver ./release/kube-apiserver
echo "Downloading kube-controller-manager ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kube-controller-manager "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kube-controller-manager"; then
  echo "Error: failed to download kube-controller-manager ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kube-controller-manager
cp kube-controller-manager ./kube-controller-manager-${TARGETARCH}
mv kube-controller-manager ./release/kube-controller-manager
echo "Downloading kube-scheduler ${KUBERNETES_VERSION}..."
if ! curl -fsS -L -o kube-scheduler "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/kube-scheduler"; then
  echo "Error: failed to download kube-scheduler ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kube-scheduler
cp kube-scheduler ./kube-scheduler-${TARGETARCH}
mv kube-scheduler ./release/kube-scheduler

# Install helm
echo "Downloading helm ${HELM_VERSION}..."
if ! curl -fsS -L -o helm3.tar.gz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz"; then
  echo "Error: failed to download helm ${HELM_VERSION} for ${TARGETARCH}"
  exit 1
fi
tar -zxf helm3.tar.gz linux-${TARGETARCH}/helm
chmod +x linux-${TARGETARCH}/helm
cp linux-${TARGETARCH}/helm ./helm-${TARGETARCH}
mv linux-${TARGETARCH}/helm ./release/helm
rm helm3.tar.gz
rm -R linux-${TARGETARCH}

# Install etcd
echo "Downloading etcd ${ETCD_VERSION}..."
if ! curl -fsS -L -o "./etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz" "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz"; then
  echo "Error: failed to download etcd ${ETCD_VERSION} for ${TARGETARCH}"
  exit 1
fi
mkdir -p ./etcd
tar xzf ./etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz -C ./etcd --strip-components=1 --no-same-owner
rm -f ./etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz
chmod +x ./etcd/etcd
chmod +x ./etcd/etcdctl
cp ./etcd/etcd ./etcd-${TARGETARCH}
mv ./etcd/etcd ./release/etcd
cp ./etcd/etcdctl ./etcdctl-${TARGETARCH}
mv ./etcd/etcdctl ./release/etcdctl
rm -R ./etcd

# Install kine
echo "Downloading kine ${KINE_VERSION}..."
if ! curl -fsS -L -o kine "https://github.com/loft-sh/kine/releases/download/${KINE_VERSION}/kine-${TARGETARCH}"; then
  echo "Error: failed to download kine ${KINE_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kine
cp kine ./kine-${TARGETARCH}
mv kine ./release/kine

# Install konnektivity
echo "Downloading konnektivity ${KONNECTIVITY_VERSION}..."
docker pull --platform linux/${TARGETARCH} registry.k8s.io/kas-network-proxy/proxy-server:${KONNECTIVITY_VERSION}
KONNECTIVITY_DOCKER_CONTAINER=$(docker create --platform linux/${TARGETARCH} registry.k8s.io/kas-network-proxy/proxy-server:${KONNECTIVITY_VERSION})
docker cp ${KONNECTIVITY_DOCKER_CONTAINER}:/proxy-server ./release/konnectivity-server
cp ./release/konnectivity-server ./konnectivity-server-${TARGETARCH}
docker rm ${KONNECTIVITY_DOCKER_CONTAINER}

# Copy the agent binaries
cp ./kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}.tar.gz ./release/kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}.tar.gz

# Pack the kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}-control-plane.tar.gz
echo "Packing the control plane folder into kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}-full.tar.gz..."
tar -zcf kubernetes-${KUBERNETES_VERSION}-${TARGETARCH}-full.tar.gz ./release

# delete the release folder
rm -rf ./release
