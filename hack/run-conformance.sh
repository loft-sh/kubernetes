#!/usr/bin/env bash
# Runs the full Kubernetes conformance suite on kind against a Kubernetes
# source tree, with kind's hack/ci/e2e-k8s.sh, the script upstream's
# ci-kubernetes-kind-conformance job runs. It builds the kind node image from
# that tree, so Go dependency pins applied to it are what gets tested.
#
# Usage: run-conformance.sh <kubernetes source dir>
# Env: KIND_VERSION (default v0.33.0), ARTIFACTS (test results), PARALLEL=true
#      to skip [Serial] tests, FOCUS/SKIP to narrow the suite (see e2e-k8s.sh).
set -euo pipefail

k8s_dir="${1:?usage: $0 <kubernetes source dir>}"
kind_version="${KIND_VERSION:-v0.33.0}"
tools_dir=$(mktemp -d)
trap 'rm -rf "$tools_dir"' EXIT

release="https://github.com/kubernetes-sigs/kind/releases/download/${kind_version}"
curl -fsSLo "${tools_dir}/kind" "${release}/kind-linux-amd64"
expected=$(curl -fsSL "${release}/kind-linux-amd64.sha256sum" | cut -d' ' -f1)
echo "${expected}  ${tools_dir}/kind" | sha256sum -c -
chmod +x "${tools_dir}/kind"
curl -fsSLo "${tools_dir}/e2e-k8s.sh" "https://raw.githubusercontent.com/kubernetes-sigs/kind/${kind_version}/hack/ci/e2e-k8s.sh"

export PATH="${tools_dir}:${PATH}"
cd "$k8s_dir"
bash "${tools_dir}/e2e-k8s.sh"
