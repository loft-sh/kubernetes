#!/usr/bin/env bash
# Prints, on one line, the Go dependency pins that raise a dependency of a
# Kubernetes patch release: its pins (pins-for.sh) minus the ones its go.mod
# already meets. Empty output means the release keeps the dl.k8s.io binaries;
# otherwise it is built from source with these pins and tested before it is
# published. download.sh and the release workflow's matrix (ci.sh
# release-versions) both decide with it, so they cannot disagree.
#
# Usage: effective-pins.sh <kubernetes version, e.g. v1.36.7>
set -euo pipefail

version="${1:?usage: $0 <kubernetes version, e.g. v1.36.7>}"
deps_dir="$(cd "$(dirname "$0")" && pwd)"

pins=$("${deps_dir}/pins-for.sh" "$version")
[ -n "$pins" ] || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if ! curl -fsSL -o "${work}/go.mod" "https://raw.githubusercontent.com/kubernetes/kubernetes/${version}/go.mod"; then
  echo "Error: failed to read go.mod of Kubernetes ${version}" >&2
  exit 1
fi
if ! applied=$(cd "$work" && PIN_GO_DEPS_DRY_RUN=1 "${deps_dir}/pin-go-deps.sh" "$pins"); then
  echo "Error: the Go dependency pins do not fit Kubernetes ${version}" >&2
  exit 1
fi
# shellcheck disable=SC2086 # joins the one-per-line pins into one line
echo $applied
