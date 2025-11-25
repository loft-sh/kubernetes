#!/bin/bash
set -e  # Exit on error

# Read from environment variables
KUBERNETES_VERSION="${KUBERNETES_VERSION:-}"
RELEASE_DIR="/kubernetes"
TARGET_ARCH="${TARGET_ARCH:-amd64}"
PAUSE_IMAGE_VERSION="${PAUSE_IMAGE_VERSION:-}"
KUBERNETES_FIPS_IMAGE="${KUBERNETES_FIPS_IMAGE:-}"
ETCD_FIPS_IMAGE="${ETCD_FIPS_IMAGE:-}"
KONNECTIVITY_FIPS_IMAGE="${KONNECTIVITY_FIPS_IMAGE:-}"
HELM_FIPS_IMAGE="${HELM_FIPS_IMAGE:-}"
KINE_FIPS_IMAGE="${KINE_FIPS_IMAGE:-}"

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
  echo "Error: KUBERNETES_VERSION is required"
  exit 1
fi

if [ -z "$TARGET_ARCH" ]; then
  echo "Error: TARGET_ARCH is required"
  exit 1
fi

if [ -z "$KUBERNETES_FIPS_IMAGE" ]; then
  echo "Error: KUBERNETES_FIPS_IMAGE evn var not set"
  exit 1
fi

if [ -z "$KINE_FIPS_IMAGE" ]; then
  echo "Error: KINE_VERSION evn var not set"
  exit 1
fi

if [ -z "$KONNECTIVITY_FIPS_IMAGE" ]; then
  echo "Error: KONNECTIVITY_VERSION evn var not set"
  exit 1
fi

if [ -z "$PAUSE_IMAGE_VERSION" ]; then
  echo "Error: PAUSE_IMAGE_VERSION evn var not set"
  exit 1
fi


# Create the directory for the binaries
mkdir -p "${OUTPUT_DIR}"


# pulling control plane components for $TARGET_ARCH (linux/amd64 or linux/arm64)
echo "Creating temporary kubernetes container for linux/amd64..."
CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "${KUBERNETES_FIPS_IMAGE}")

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
docker save -o "${OUTPUT_DIR}/pause-image.tar" rancher/mirrored-pause:${PAUSE_IMAGE_VERSION}
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
rm $OUTPUT_DIR/containerd $OUTPUT_DIR/containerd-shim-runc-v2 $OUTPUT_DIR/ctr $OUTPUT_DIR/kubeadm $OUTPUT_DIR/kubectl $OUTPUT_DIR/kubelet $OUTPUT_DIR/runc

# copy etcd binaries
ETCD_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "${ETCD_FIPS_IMAGE}" true)
trap 'cleanup $ETCD_CONTAINER_ID' EXIT
if docker cp "$ETCD_CONTAINER_ID:/bin/etcd" "$OUTPUT_DIR/etcd"; then
  echo "copied etcd to $OUTPUT_DIR/etcd"
else
  echo "Error: Failed to copy files from etcd container"
  exit 1
fi

if docker cp "$ETCD_CONTAINER_ID:/bin/etcdctl" "$OUTPUT_DIR/etcdctl"; then
  echo "copied etcdctl to $OUTPUT_DIR/etcdctl"
else
  echo "Error: Failed to copy files from etcdctl container"
  exit 1
fi

# copy helm binary
HELM_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "${HELM_FIPS_IMAGE}" true)
trap 'cleanup $HELM_CONTAINER_ID' EXIT
if docker cp "$HELM_CONTAINER_ID:/usr/local/bin/helm" "$OUTPUT_DIR/helm"; then
  echo "copied helm to $OUTPUT_DIR/helm"
else
  echo "Error: Failed to copy files from helm container"
  exit 1
fi

# copy kine binary
KINE_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "${KINE_FIPS_IMAGE}" true)
trap 'cleanup $KINE_CONTAINER_ID' EXIT
if docker cp "$KINE_CONTAINER_ID:/bin/kine" "$OUTPUT_DIR/kine"; then
  echo "copied kine to $OUTPUT_DIR/kine"
else
  echo "Error: Failed to copy files from kine container"
  exit 1
fi

# copy konnectivity-server binary
KONNECTIVITY_CONTAINER_ID=$(docker create --platform ${TARGET_OS_ARCH} "${KONNECTIVITY_FIPS_IMAGE}" true)
trap 'cleanup $KONNECTIVITY_CONTAINER_ID' EXIT
if docker cp "$KONNECTIVITY_CONTAINER_ID:/bin/konnectivity-server" "$OUTPUT_DIR/konnectivity-server"; then
  echo "copied konnectivity-server to $OUTPUT_DIR/konnectivity-server"
else
  echo "Error: Failed to copy files from konnectivity-server container"
  exit 1
fi

# create archive
echo "creating kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips-full.tar.gz archive..."
tar -zcf "kubernetes-${KUBERNETES_VERSION}-${TARGET_ARCH}-fips-full.tar.gz" "${OUTPUT_DIR}"

docker rm "$KONNECTIVITY_CONTAINER_ID" "$KINE_CONTAINER_ID" "$HELM_CONTAINER_ID" "$ETCD_CONTAINER_ID" "$CONTAINER_ID" || true
rm -r $OUTPUT_DIR