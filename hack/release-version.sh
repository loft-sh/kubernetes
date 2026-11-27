#!/usr/bin/env bash
# The steps of one Kubernetes patch release, for the jobs of
# .github/workflows/release-version.yaml:
#
#   release-version.sh build <version> <files.tar>
#       download.sh gets the amd64 and arm64 binaries (from dl.k8s.io, or built
#       from source when a Go dependency pin raises a dependency) and packs
#       everything the publish step needs into <files.tar>. A missing file
#       fails here, before anything is published.
#   release-version.sh images <version> [--push]
#       Builds the full and the control plane image from those files, and
#       pushes them with --push.
#   release-version.sh publish <version> <files.tar>
#       Unpacks <files.tar>, uploads the archives to the GitHub release and
#       pushes the images.
#
# Env for publish: REPO (owner/name of this repository) and GH_TOKEN.
set -euo pipefail

cmd="${1:?usage: $0 build|images|publish <version> ...}"
version="${2:?usage: $0 ${cmd} <kubernetes version, e.g. v1.36.7> ...}"
cd "$(dirname "$0")"

archives=(
  "kubernetes-${version}-amd64.tar.gz"
  "kubernetes-${version}-arm64.tar.gz"
  "kubernetes-${version}-amd64-full.tar.gz"
  "kubernetes-${version}-arm64-full.tar.gz"
)
# The binaries the images copy (Dockerfile), per architecture.
image_binaries=(kube-apiserver kube-controller-manager kube-scheduler helm etcd etcdctl etcdutl kine konnectivity-server)

# files: everything the publish step needs, from a build.
files() {
  local arch bin
  printf '%s\n' "${archives[@]}" "kubernetes-${version}.txt"
  for arch in amd64 arm64; do
    for bin in "${image_binaries[@]}"; do
      echo "${bin}-${arch}"
    done
  done
}

images() {
  local push=()
  [ "${1:-}" != --push ] || push=(--push)
  # The full image copies every kubernetes-*-<arch>.tar.gz here: the node
  # archives, not the -full ones.
  rm -f "kubernetes-${version}-amd64-full.tar.gz" "kubernetes-${version}-arm64-full.tar.gz"
  docker buildx build --platform linux/amd64,linux/arm64 -t "ghcr.io/loft-sh/kubernetes:${version}-full" "${push[@]}" .
  # The control plane image has no node archives.
  rm -f "kubernetes-${version}-amd64.tar.gz" "kubernetes-${version}-arm64.tar.gz"
  docker buildx build --platform linux/amd64,linux/arm64 -t "ghcr.io/loft-sh/kubernetes:${version}" "${push[@]}" .
}

case "$cmd" in
  build)
    out="${3:?usage: $0 build <version> <files.tar>}"
    for arch in amd64 arm64; do
      if ! ./download.sh --kubernetes-version "$version" --target-arch "$arch"; then
        echo "::error::Failed to get the ${arch} binaries of Kubernetes ${version}"
        exit 1
      fi
    done
    # tar fails on a missing file: download.sh does not stop on every failed
    # download, e.g. a konnectivity image that is not published.
    if ! files | tar -cf "$out" -T -; then
      echo "::error::The build of Kubernetes ${version} is missing files; nothing of it is published"
      exit 1
    fi
    ;;
  images)
    images "${3:-}"
    ;;
  publish)
    in="${3:?usage: $0 publish <version> <files.tar>}"
    repo="${REPO:?REPO is required}"
    tar -xf "$in"
    if gh release view "$version" --repo "$repo" &>/dev/null; then
      gh release upload "$version" "${archives[@]}" --repo "$repo" --clobber
      # The notes list the component versions.
      gh release edit "$version" --notes-file "kubernetes-${version}.txt" --repo "$repo"
      echo "Updated release for Kubernetes ${version}"
    else
      gh release create "$version" --title "Kubernetes ${version}" --notes-file "kubernetes-${version}.txt" --repo "$repo" "${archives[@]}"
      echo "Released Kubernetes ${version}"
    fi
    images --push
    ;;
  *)
    echo "usage: $0 build <version> <files.tar> | images <version> [--push] | publish <version> <files.tar>" >&2
    exit 2
    ;;
esac
