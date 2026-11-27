#!/usr/bin/env bash

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
# Default; per-k8s overlays (hack/kubernetes-v1.X) may set TAILSCALED_VERSION to override.
TAILSCALED_VERSION="v1.78.1-loft.15"
TARGETARCH="amd64"
# Go dependency pins of this version, from the overlay (see pin-deps/pins-for.sh).
K8S_GO_DEP_PINS=""
# When set, use this pre-built tailscaled binary instead of downloading from the fork's GitHub releases.
VCLUSTER_TUNNEL_PATH=""

# sha256 of every fork release binary this script downloads, keyed by
# <repo>/<version>/<asset>. A fork release asset can be replaced after it is
# published, so the build accepts only the bytes recorded here. When an overlay
# bumps KINE_VERSION or TAILSCALED_VERSION, add the new asset digests (the
# "digest" field of the release asset in the GitHub API) or the build fails.
# hack/check-fork-sha256.sh catches a missing entry on the pull request.
fork_asset_sha256() {
  case "$1" in
    kine/v0.14.5/kine-amd64) echo 4f2caeed0ad09e130eb790b89438611aad14a94daf6d06981d91deb74c35a6cc ;;
    kine/v0.14.5/kine-arm64) echo 6bb2c7182bf135523fdafecee436e4a33a5de9077a9908b201c370974c13097d ;;
    kine/v0.14.10/kine-amd64) echo 96d1ad0d4b205de0f6c5420706c7d6fadfaa69b174189faf5c002a42cd695317 ;;
    kine/v0.14.10/kine-arm64) echo 576d1da09e852674219ed66afdcd6ec42d361dcae4b59ce7a3e1429d5211ec34 ;;
    kine/v0.14.10.vcluster.0/kine-amd64) echo 97ec69bd2e803634eae29fa1ad497276abc56517643ef43cb3dc43a34fa88381 ;;
    kine/v0.14.10.vcluster.0/kine-arm64) echo d66ebd84847e76507ce2c1bd9f8db8aa69273c4bc4ee5e2fb33ac2a897d01d9f ;;
    kine/v0.14.16.vcluster.3/kine-amd64) echo 782eafcec28db1a9d854b874b09b4a83c8189c31638dab54e8744326d998c243 ;;
    kine/v0.14.16.vcluster.3/kine-arm64) echo a22b2ab3245b6eafd9de99d70fae2d136985adbee5f67bc58e0b5098f056796e ;;
    kine/v0.14.16.vcluster.4/kine-amd64) echo 8ffd188135137048546c445439ad53ece55299001aeeea56048903eb4a2cddd6 ;;
    kine/v0.14.16.vcluster.4/kine-arm64) echo 948e988426883994f3f4602e9c1b1a7afe7acdf49a56325c56a1baf10c0e0a58 ;;
    kine/v0.17.2.vcluster.0/kine-amd64) echo 43269a40f13560911f485ff9cb3a02c5ebc8dc50451ebdd27b6d0b5c2f1e2c66 ;;
    kine/v0.17.2.vcluster.0/kine-arm64) echo d6005e4d20124fbd1c8fa6d8f8a4a1d3b67641e77864ba941b4e7d4128e125db ;;
    kine/v0.16.5.vcluster.2/kine-amd64) echo 398759c0ddfca4acd16af45253910299461a1d552c8bc6788c1c471079b4d140 ;;
    kine/v0.16.5.vcluster.2/kine-arm64) echo 00ca19b0d002e10bac159abadf208d528c04ccec800b8c317eb05bc4fafe0457 ;;
    kine/v0.17.5.vcluster.0/kine-amd64) echo bf96ef63c0da30ea138a9f239b690acbfdf25f155713f1c9a73008e10d5d07b5 ;;
    kine/v0.17.5.vcluster.0/kine-arm64) echo 06035d50ed445a10e390365623da10514510536db1729972adbafaa8d63ec919 ;;
    tailscale/v1.78.1-loft.11/tailscaled-linux-amd64) echo dcea869998d08d22c5f899eb878d30a17674e9a0b58a408f01a298cd872923d3 ;;
    tailscale/v1.78.1-loft.11/tailscaled-linux-arm64) echo 009b65d563939613340c9ce856ef535efce90a90da7760e2a96b6d774cee2b8d ;;
    tailscale/v1.78.1-loft.15/tailscaled-linux-amd64) echo 8cd198fef877c04588f13fdbb98e8063f8ab9a0547264a77559b89ff7a086a66 ;;
    tailscale/v1.78.1-loft.15/tailscaled-linux-arm64) echo 083e214e6ab8b130ac8b2f9396d339410097c0a6ec929ef31ec0f5dce2d9799e ;;
    tailscale/v1.96.4-loft.2/tailscaled-linux-amd64) echo 2efcc605350bee5d00d5dff3ad0cad7ae9091f47d66f42bdb28997cf4fe081c3 ;;
    tailscale/v1.96.4-loft.2/tailscaled-linux-arm64) echo c08e7917f46d5119de69fbf748c0acb96d378d27c62ce798c17223cde6940a5d ;;
    tailscale/v1.96.4-loft.3/tailscaled-linux-amd64) echo fab1f70e5ba5568e82734aff42d15a193c2c30af7ca01aec2cb46047cda4bc9d ;;
    tailscale/v1.96.4-loft.3/tailscaled-linux-arm64) echo 35711b43a2f92be808d3b7caaad1960794a3e37cf9d2804bf7a909c4f4ce86ac ;;
    *) return 1 ;;
  esac
}

# verify_fork_asset <repo> <version> <asset> <file> fails the build unless the
# file matches the recorded sha256.
verify_fork_asset() {
  local expected
  if ! expected=$(fork_asset_sha256 "$1/$2/$3"); then
    echo "Error: no sha256 recorded for loft-sh/$1 $2 $3; add it to fork_asset_sha256 in hack/download.sh"
    exit 1
  fi
  if ! echo "${expected}  $4" | sha256sum -c --quiet -; then
    echo "Error: loft-sh/$1 $2 $3 does not match its recorded sha256 ${expected}"
    exit 1
  fi
}

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
    --vcluster-tunnel-path)
      VCLUSTER_TUNNEL_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --kubernetes-version <version> [--target-arch <arch>] [--vcluster-tunnel-path <file>]"
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

# Written once the build source is decided, below; none left from an earlier run.
rm -f ./kubernetes-${KUBERNETES_VERSION}.go-dep-pins

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

# When a Go dependency pin from the overlay (a CVE fix upstream has not
# shipped yet) applies to this version, the Kubernetes binaries are built from
# source with the pins instead of downloaded from dl.k8s.io.
K8S_SRC_DIR="./k8s-src-${TARGETARCH}"
# The pins of this patch release: the overlay's entries from this version or
# earlier ones of its minor version (see pin-deps/pins-for.sh).
unset K8S_GO_DEP_PINS # the sourced overlay set it as an array of all entries
if ! K8S_GO_DEP_PINS=$(./pin-deps/pins-for.sh "${KUBERNETES_VERSION}"); then
  echo "Error: failed to read the Go dependency pins of Kubernetes ${KUBERNETES_VERSION}"
  exit 1
fi
if [ -n "${K8S_GO_DEP_PINS}" ]; then
  # Keep only the pins that raise a dependency of this version, so a version
  # that already ships them keeps the upstream binaries.
  GO_MOD_DIR=$(mktemp -d)
  if ! curl -fsSL -o "${GO_MOD_DIR}/go.mod" "https://raw.githubusercontent.com/kubernetes/kubernetes/${KUBERNETES_VERSION}/go.mod"; then
    echo "Error: failed to read go.mod of Kubernetes ${KUBERNETES_VERSION}"
    exit 1
  fi
  if ! APPLIED_PINS=$(cd "${GO_MOD_DIR}" && PIN_GO_DEPS_DRY_RUN=1 "${OLDPWD}/pin-deps/pin-go-deps.sh" "${K8S_GO_DEP_PINS}"); then
    echo "Error: the Go dependency pins do not fit Kubernetes ${KUBERNETES_VERSION}"
    exit 1
  fi
  rm -rf "${GO_MOD_DIR}"
  # shellcheck disable=SC2086 # joins the one-per-line pins into one line
  K8S_GO_DEP_PINS=$(echo ${APPLIED_PINS})
fi
# The pins this version is built from source with, empty when it uses the
# dl.k8s.io binaries: the release e2e-tests source builds before publishing them.
printf "%s" "${K8S_GO_DEP_PINS}" > ./kubernetes-${KUBERNETES_VERSION}.go-dep-pins
if [ -n "${K8S_GO_DEP_PINS}" ]; then
  echo "Building Kubernetes ${KUBERNETES_VERSION} from source with Go dependency pins: ${K8S_GO_DEP_PINS}..."
  rm -rf "${K8S_SRC_DIR}"
  if ! KUBE_CROSS_VERSION=$(curl -fsSL "https://raw.githubusercontent.com/kubernetes/kubernetes/${KUBERNETES_VERSION}/build/build-image/cross/VERSION"); then
    echo "Error: failed to read the kube-cross version of Kubernetes ${KUBERNETES_VERSION}"
    exit 1
  fi
  # A throwaway builder: removing it drops its build cache (kube-cross, the
  # clone, the Go build cache), so repeated source builds do not fill the disk,
  # and the caller's own build cache is left alone.
  K8S_SRC_BUILDER="k8s-src-${TARGETARCH}-$$"
  if ! docker buildx create --name "${K8S_SRC_BUILDER}" --driver docker-container >/dev/null; then
    echo "Error: failed to create the buildx builder ${K8S_SRC_BUILDER}"
    exit 1
  fi
  # Also remove it when the script is interrupted or cancelled mid-build.
  trap 'docker buildx rm "${K8S_SRC_BUILDER}" >/dev/null 2>&1; exit 130' INT
  trap 'docker buildx rm "${K8S_SRC_BUILDER}" >/dev/null 2>&1; exit 143' TERM
  docker buildx build --builder "${K8S_SRC_BUILDER}" -f ./pin-deps/Dockerfile \
    --platform "linux/${TARGETARCH}" \
    --build-arg KUBE_CROSS_VERSION="${KUBE_CROSS_VERSION}" \
    --build-arg KUBERNETES_VERSION="${KUBERNETES_VERSION}" \
    --build-arg K8S_GO_DEP_PINS="${K8S_GO_DEP_PINS}" \
    --output "type=local,dest=${K8S_SRC_DIR}" ./pin-deps
  K8S_SRC_BUILD_RC=$?
  trap - INT TERM
  docker buildx rm "${K8S_SRC_BUILDER}" >/dev/null || echo "Warning: failed to remove the buildx builder ${K8S_SRC_BUILDER}"
  if [ "${K8S_SRC_BUILD_RC}" -ne 0 ]; then
    echo "Error: failed to build Kubernetes ${KUBERNETES_VERSION} from source for ${TARGETARCH}"
    exit 1
  fi
fi

# k8s_bin <name> puts the Kubernetes binary <name> into ./<name>.
k8s_bin() {
  if [ -n "${K8S_GO_DEP_PINS:-}" ]; then
    cp "${K8S_SRC_DIR}/$1" "./$1" || { echo "Error: $1 is missing from the source build in ${K8S_SRC_DIR}"; return 1; }
  else
    curl -fsS -L -o "$1" "https://dl.k8s.io/release/${KUBERNETES_VERSION}/bin/linux/${TARGETARCH}/$1"
  fi
}

# Create the directory for the binaries, without leftovers from a run that
# failed partway, which would otherwise end up in this version's archives
rm -rf ./release
mkdir -p ./release

# Download kubeadm, kubelet, and kubectl
echo "Downloading kubeadm ${KUBERNETES_VERSION}..."
if ! k8s_bin kubeadm; then
  echo "Error: failed to get kubeadm ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kubeadm
mv kubeadm ./release/kubeadm
echo "Downloading kubelet ${KUBERNETES_VERSION}..."
if ! k8s_bin kubelet; then
  echo "Error: failed to get kubelet ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kubelet
mv kubelet ./release/kubelet
echo "Downloading kubectl ${KUBERNETES_VERSION}..."
if ! k8s_bin kubectl; then
  echo "Error: failed to get kubectl ${KUBERNETES_VERSION} for ${TARGETARCH}"
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

# Obtain vcluster-tunnel (tailscaled from loft-sh/tailscale fork)
if [ -n "$VCLUSTER_TUNNEL_PATH" ]; then
  echo "Using local vcluster-tunnel from ${VCLUSTER_TUNNEL_PATH}..."
  if [ ! -f "$VCLUSTER_TUNNEL_PATH" ]; then
    echo "Error: --vcluster-tunnel-path file not found: ${VCLUSTER_TUNNEL_PATH}"
    exit 1
  fi
  cp "$VCLUSTER_TUNNEL_PATH" ./vcluster-tunnel
else
  echo "Downloading vcluster-tunnel ${TAILSCALED_VERSION}..."
  if ! curl -fsS -L -o vcluster-tunnel "https://github.com/loft-sh/tailscale/releases/download/${TAILSCALED_VERSION}/tailscaled-linux-${TARGETARCH}"; then
    echo "Error: failed to download vcluster-tunnel ${TAILSCALED_VERSION} for ${TARGETARCH}"
    exit 1
  fi
  verify_fork_asset tailscale "${TAILSCALED_VERSION}" "tailscaled-linux-${TARGETARCH}" ./vcluster-tunnel
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
if [ -n "${K8S_GO_DEP_PINS:-}" ]; then
  {
    echo ""
    echo "## Go Dependency Pins"
    echo "The Kubernetes binaries are built from source with these minimum Go dependency versions:"
    for pin in ${K8S_GO_DEP_PINS}; do echo "- \`${pin}\`"; done
  } >> ./kubernetes-${KUBERNETES_VERSION}.txt
fi

# delete the release folder
rm -rf ./release

# Create the directory for the control plane binaries again
mkdir -p ./release

# Download kube-apiserver
echo "Downloading kube-apiserver ${KUBERNETES_VERSION}..."
if ! k8s_bin kube-apiserver; then
  echo "Error: failed to get kube-apiserver ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kube-apiserver
cp kube-apiserver ./kube-apiserver-${TARGETARCH}
mv kube-apiserver ./release/kube-apiserver
echo "Downloading kube-controller-manager ${KUBERNETES_VERSION}..."
if ! k8s_bin kube-controller-manager; then
  echo "Error: failed to get kube-controller-manager ${KUBERNETES_VERSION} for ${TARGETARCH}"
  exit 1
fi
chmod +x kube-controller-manager
cp kube-controller-manager ./kube-controller-manager-${TARGETARCH}
mv kube-controller-manager ./release/kube-controller-manager
echo "Downloading kube-scheduler ${KUBERNETES_VERSION}..."
if ! k8s_bin kube-scheduler; then
  echo "Error: failed to get kube-scheduler ${KUBERNETES_VERSION} for ${TARGETARCH}"
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
chmod +x ./etcd/etcdutl
cp ./etcd/etcd ./etcd-${TARGETARCH}
mv ./etcd/etcd ./release/etcd
cp ./etcd/etcdctl ./etcdctl-${TARGETARCH}
mv ./etcd/etcdctl ./release/etcdctl
cp ./etcd/etcdutl ./etcdutl-${TARGETARCH}
mv ./etcd/etcdutl ./release/etcdutl
rm -R ./etcd

# Install kine
echo "Downloading kine ${KINE_VERSION}..."
if ! curl -fsS -L -o kine "https://github.com/loft-sh/kine/releases/download/${KINE_VERSION}/kine-${TARGETARCH}"; then
  echo "Error: failed to download kine ${KINE_VERSION} for ${TARGETARCH}"
  exit 1
fi
verify_fork_asset kine "${KINE_VERSION}" "kine-${TARGETARCH}" ./kine
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
rm -rf ./release "${K8S_SRC_DIR}"
