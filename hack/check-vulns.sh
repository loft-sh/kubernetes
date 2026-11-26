#!/usr/bin/env bash
# Fails when the Kubernetes binaries built from a source tree reach any known
# vulnerability. Run it on a tree with the Go dependency pins applied, with the
# Go version that release builds with on PATH, so the standard library is
# checked at that version too.
#
# govulncheck reports only vulnerabilities whose code the binaries can call.
# The report lists each with the version that fixes it, which is the pin to
# add; stdlib ones are fixed by a Kubernetes release with a newer Go.
#
# Usage: check-vulns.sh <kubernetes source dir>
# Env: GITHUB_STEP_SUMMARY (optional) for the report, GOVULNCHECK_VERSION
#      (default v1.10.0).
set -euo pipefail

k8s_dir="${1:?usage: $0 <kubernetes source dir>}"
govulncheck_version="${GOVULNCHECK_VERSION:-v1.10.0}"
report="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

GOWORK=off GOBIN="${work}/bin" go install "golang.org/x/vuln/cmd/govulncheck@${govulncheck_version}"

echo "Scanning the Kubernetes binaries in ${k8s_dir} with $(go version)..." >&2
(cd "$k8s_dir" && "${work}/bin/govulncheck" -format json \
  ./cmd/kube-apiserver ./cmd/kube-controller-manager ./cmd/kube-scheduler \
  ./cmd/kubelet ./cmd/kubeadm ./cmd/kubectl) > "${work}/scan.json"

# One table row per reachable vulnerability and affected module.
jq -rs '
  (map(select(.osv) | .osv | {key: .id, value: ((.aliases // []) | unique | join(", "))}) | from_entries) as $aliases
  | map(select(.finding and .finding.trace[0].function) | .finding
      | {id: .osv, module: .trace[0].module, version: .trace[0].version, fixed: (.fixed_version // "none")})
  | unique
  | .[]
  | "| [\(.id)](https://pkg.go.dev/vuln/\(.id)) | \($aliases[.id] // "") | \(.module) | \(.version) | \(.fixed) |"' \
  "${work}/scan.json" > "${work}/rows.md"

count=$(cut -d'|' -f2 "${work}/rows.md" | sort -u | grep -c . || true)
{
  if [ "$count" -gt 0 ]; then
    echo "**${count} reachable vulnerabilities.** Pin each module to its fixed version in the overlay; stdlib ones need a Kubernetes release with a newer Go."
    echo
    echo "| ID | Aliases | Module | Version | Fixed in |"
    echo "| --- | --- | --- | --- | --- |"
    cat "${work}/rows.md"
  else
    echo "No reachable vulnerabilities."
  fi
} >> "$report"

[ "$count" -eq 0 ]
