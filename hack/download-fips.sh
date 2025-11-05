#!/bin/bash
set -e  # Exit on error

# Default versions
KUBERNETES_VERSION=""
# Configuration
IMAGE_NAME="kubernetes-fips:local"
RELEASE_DIR="/kubernetes"

ETCD_VERSION="v3.5.17"
HELM_VERSION="v3.17.3"
KINE_VERSION="v0.13.14"
PAUSE_IMAGE_VERSION="3.9"
KONNECTIVITY_VERSION="v0.32.0"
TARGET_ARCH="amd64"

# Parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --kubernetes-version)
      KUBERNETES_VERSION="$2"
      shift 2
      ;;
    --target-arch)
      TARGET_ARCH="$2"
      shift 2
      ;;
    --etcd-version)
      ETCD_VERSION="$2"
      shift 2
      ;;
    --helm-version)
      HELM_VERSION="$2"
      shift 2
      ;;
    --kine-version)
      KINE_VERSION="$2"
      shift 2
      ;;
    --konnectivity-version)
      KONNECTIVITY_VERSION="$2"
      shift 2
      ;;
    --pause-image-version)
      PAUSE_IMAGE_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 --kubernetes-version <version>"
      exit 1
      ;;
  esac
done

OUTPUT_DIR="./release"
TARGET_OS_ARCH="linux/${TARGET_ARCH}"

# Cleanup function
cleanup() {
    local container_id="$1"
    echo "Cleaning up container... $1"
    docker rm "$container_id" >/dev/null 2>&1 || true
}

# Kubernetes version is required
if [ -z "$KUBERNETES_VERSION" ]; then
  echo "Error: --kubernetes-version is required"
  echo "Usage: $0 --kubernetes-version <version>"
  exit 1
fi

if [ -z "$ETCD_VERSION" ]; then
  echo "Error: --etcd-version is required"
  echo "Usage: $0 --etcd-version <version>"
  exit 1
fi

if [ -z "$HELM_VERSION" ]; then
  echo "Error: --helm-version is required"
  echo "Usage: $0 --helm-version <version>"
  exit 1
fi

if [ -z "$KINE_VERSION" ]; then
  echo "Error: --kine-version is required"
  echo "Usage: $0 --kine-version <version>"
  exit 1
fi

if [ -z "$KONNECTIVITY_VERSION" ]; then
  echo "Error: --konnectivity-version is required"
  echo "Usage: $0 --konnectivity-version <version>"
  exit 1
fi

if [ -z "$TARGET_ARCH" ]; then
  echo "Error: --target-arch is required"
  echo "Usage: $0 --target-arch <version>"
  exit 1
fi

# Trim kubernetes patch version to check if there is a file with that name
KUBERNETES_VERSION_TRIMMED=$(echo ${KUBERNETES_VERSION} | sed -E 's/^(v[0-9]+\.[0-9]+)\.[0-9]+$/\1/')
if [ ! -f "./kubernetes-${KUBERNETES_VERSION_TRIMMED}" ]; then
  echo "Error: kubernetes-${KUBERNETES_VERSION_TRIMMED} file does not exist"
  exit 1
fi


# Create the directory for the binaries
mkdir -p "${OUTPUT_DIR}"


# pulling control plane components for $TARGET_ARCH (linux/amd64 or linux/arm64)
echo "Pulling Docker image: $IMAGE_NAME"
#docker pull --platform=${TARGET_ARCH} "$IMAGE_NAME" TODO: uncomment
docker pull --platform=${TARGET_OS_ARCH} "ghcr.io/loft-sh/etcd-fips:${ETCD_VERSION}"
docker pull --platform=${TARGET_OS_ARCH}  "ghcr.io/loft-sh/helm-fips:${HELM_VERSION}"
docker pull --platform=${TARGET_OS_ARCH}  "ghcr.io/loft-sh/kine-fips:${KINE_VERSION}"
docker pull --platform=${TARGET_OS_ARCH}  "ghcr.io/loft-sh/konnectivity-server-fips:${KONNECTIVITY_VERSION}"

echo "Creating temporary kubernetes container for linux/amd64..."
CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "$IMAGE_NAME")


trap 'cleanup $CONTAINER_ID' EXIT

# First, copy node components to output dir
if docker cp "$CONTAINER_ID:$RELEASE_DIR/" "$OUTPUT_DIR/"; then
  echo "copied k8s binaries to $OUTPUT_DIR"
else
  echo "copying failed"
  exit 1
fi

# delete control plane components
rm "${OUTPUT_DIR}/kubernetes/kube-apiserver"
rm "${OUTPUT_DIR}/kubernetes/kube-controller-manager"
rm "${OUTPUT_DIR}/kubernetes/kube-scheduler"

find ${OUTPUT_DIR}/kubernetes/ -mindepth 1 -maxdepth 1 -exec mv {} $OUTPUT_DIR \;
rmdir "${OUTPUT_DIR}/kubernetes"

# Download pause image
echo "Downloading pause image ${PAUSE_IMAGE_VERSION}..."
docker pull --platform=${TARGET_OS_ARCH} rancher/mirrored-pause:${PAUSE_IMAGE_VERSION}
docker save -o ./release/pause-image.tar rancher/mirrored-pause:${PAUSE_IMAGE_VERSION}
echo "rancher/mirrored-pause:${PAUSE_IMAGE_VERSION}" > ./release/pause-image.txt

# create tar archive
echo "creating node components tar archive..."
tar -zcf "kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips.tar.gz" "${OUTPUT_DIR}"

# then, delete node components, just keep the tar archive,
rm -r $OUTPUT_DIR

# copy control plane components, then create tar -full archive
if docker cp "$CONTAINER_ID:$RELEASE_DIR/" "$OUTPUT_DIR/"; then
  echo "copied k8s binaries to $OUTPUT_DIR"
else
  echo "copying failed"
  exit 1
fi


# remove node binaries, keep them in tar archive only
cp "kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips.tar.gz" $OUTPUT_DIR
rm -r $OUTPUT_DIR/cni
rm $OUTPUT_DIR/containerd $OUTPUT_DIR/containerd-shim-runc-v2 $OUTPUT_DIR/containerd-stress $OUTPUT_DIR/ctr $OUTPUT_DIR/kubeadm $OUTPUT_DIR/kubectl $OUTPUT_DIR/kubelet $OUTPUT_DIR/runc

# copy etcd binaries
ETCD_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "ghcr.io/loft-sh/etcd-fips:${ETCD_VERSION}" true)
trap 'cleanup $ETCD_CONTAINER_ID' EXIT
if docker cp "$ETCD_CONTAINER_ID:/bin/etcd" "$OUTPUT_DIR/etcd"; then
  echo "copied etcd to $OUTPUT_DIR/etcd"
else
  echo "Error: Failed to copy files from etcd container"
  exit 1
fi

if docker cp "$ETCD_CONTAINER_ID:/bin/etcdctl" "$OUTPUT_DIR/etcdctl"; then
  echo "copied etcdctl to $OUTPUT_DIR/etcdctl"
  docker rm "$ETCD_CONTAINER_ID"
else
  echo "Error: Failed to copy files from etcdctl container"
  exit 1
fi

# copy helm binary
HELM_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "ghcr.io/loft-sh/helm-fips:${HELM_VERSION}" true)
trap 'cleanup $HELM_CONTAINER_ID' EXIT
if docker cp "$HELM_CONTAINER_ID:/usr/local/bin/helm" "$OUTPUT_DIR/helm"; then
  echo "copied helm to $OUTPUT_DIR/helm"
  docker rm "$HELM_CONTAINER_ID"
else
  echo "Error: Failed to copy files from helm container"
  exit 1
fi

# copy kine binary
KINE_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "ghcr.io/loft-sh/kine-fips:${KINE_VERSION}" true)
trap 'cleanup $KINE_CONTAINER_ID' EXIT
if docker cp "$KINE_CONTAINER_ID:/bin/kine" "$OUTPUT_DIR/kine"; then
  echo "copied kine to $OUTPUT_DIR/kine"
  docker rm "$KINE_CONTAINER_ID"
else
  echo "Error: Failed to copy files from kine container"
  exit 1
fi

# copy konnectivity-server binary
KONNECTIVITY_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "ghcr.io/loft-sh/konnectivity-server-fips:${KONNECTIVITY_VERSION}" true)
trap 'cleanup $KONNECTIVITY_CONTAINER_ID' EXIT
if docker cp "$KONNECTIVITY_CONTAINER_ID:/bin/konnectivity-server" "$OUTPUT_DIR/konnectivity-server"; then
  echo "copied konnectivity-server to $OUTPUT_DIR/konnectivity-server"
  docker rm "$KONNECTIVITY_CONTAINER_ID"
else
  echo "Error: Failed to copy files from konnectivity-server container"
  exit 1
fi

# create archive
echo "creating kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips-full.tar.gz archive..."
tar -zcf "kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips-full.tar.gz" "${OUTPUT_DIR}"

docker rm "$KONNECTIVITY_CONTAINER_ID" "$KINE_CONTAINER_ID" "$HELM_CONTAINER_ID" "$ETCD_CONTAINER_ID" "$CONTAINER_ID" || true
rm -r $OUTPUT_DIR
