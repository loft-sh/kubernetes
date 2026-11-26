#!/usr/bin/env bash
# Builds, tests and publishes one Kubernetes patch release, for one job of
# .github/workflows/release.yaml:
#   1. download.sh gets the amd64 and arm64 binaries: from dl.k8s.io, or built
#      from source when a Go dependency pin raises a dependency.
#   2. A source build must pass the e2e tests (pin-deps/ci.sh release-e2e)
#      before anything of this version is published.
#   3. The archives go to the GitHub release, the images to ghcr.io.
# Any failure stops here, before publishing.
#
# Usage: release-version.sh <version, e.g. v1.36.7>
# Env: REPO (owner/name of this repository) and GH_TOKEN for the release,
#      ARTIFACTS for the e2e test results.
set -euo pipefail

version="${1:?usage: $0 <kubernetes version, e.g. v1.36.7>}"
repo="${REPO:?REPO is required}"
cd "$(dirname "$0")"

for arch in amd64 arm64; do
  if ! ./download.sh --kubernetes-version "$version" --target-arch "$arch"; then
    echo "::error::Failed to get the ${arch} binaries of Kubernetes ${version}"
    exit 1
  fi
done

if [ -s "./kubernetes-${version}.go-dep-pins" ]; then
  echo "Kubernetes ${version} is built from source with Go dependency pins: $(cat "./kubernetes-${version}.go-dep-pins"), running the e2e tests..."
  if ! ./pin-deps/ci.sh release-e2e "$version"; then
    echo "::error::Kubernetes ${version}, built from source with Go dependency pins, failed the e2e tests; nothing of it is published"
    exit 1
  fi
fi

archives=(
  "./kubernetes-${version}-amd64.tar.gz"
  "./kubernetes-${version}-arm64.tar.gz"
  "./kubernetes-${version}-amd64-full.tar.gz"
  "./kubernetes-${version}-arm64-full.tar.gz"
)
if gh release view "$version" --repo "$repo" &>/dev/null; then
  gh release upload "$version" "${archives[@]}" --repo "$repo" --clobber
  # The notes list the component versions.
  gh release edit "$version" --notes-file "./kubernetes-${version}.txt" --repo "$repo"
  echo "Updated release for Kubernetes ${version}"
else
  gh release create "$version" --title "Kubernetes ${version}" --notes-file "./kubernetes-${version}.txt" --repo "$repo" "${archives[@]}"
  echo "Released Kubernetes ${version}"
fi

# The full image copies every kubernetes-*-<arch>.tar.gz here: the node
# archives, not the -full ones.
rm -f "./kubernetes-${version}-amd64-full.tar.gz" "./kubernetes-${version}-arm64-full.tar.gz"
docker buildx build --platform linux/amd64,linux/arm64 -t "ghcr.io/loft-sh/kubernetes:${version}-full" --push .

# The control plane image has no node archives.
rm -f "./kubernetes-${version}-amd64.tar.gz" "./kubernetes-${version}-arm64.tar.gz"
docker buildx build --platform linux/amd64,linux/arm64 -t "ghcr.io/loft-sh/kubernetes:${version}" --push .
