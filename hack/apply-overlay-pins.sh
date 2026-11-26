#!/usr/bin/env bash
# Applies the Go dependency pins of a Kubernetes version's overlay
# (K8S_GO_DEP_PINS in hack/kubernetes-v1.X) to the Kubernetes checkout in the
# current directory. Does nothing when the overlay sets no pins.
#
# Usage (from the kubernetes source root): apply-overlay-pins.sh v1.36.7
set -euo pipefail

version="${1:?usage: $0 <kubernetes version, e.g. v1.36.7>}"
hack_dir="$(cd "$(dirname "$0")" && pwd)"
overlay="${hack_dir}/kubernetes-${version%.*}"
if [ ! -f "$overlay" ]; then
  echo "Error: ${overlay} does not exist" >&2
  exit 1
fi

# shellcheck disable=SC1090
pins=$(bash -c 'source "$1"; echo "${K8S_GO_DEP_PINS[*]:-}"' _ "$overlay")
echo "Go dependency pins for Kubernetes ${version}: ${pins:-none}"
"${hack_dir}/pin-go-deps.sh" "$pins"
