#!/usr/bin/env bash
# CI steps of .github/workflows/test-go-dep-pins.yaml, which tests the Go
# dependency pins (K8S_GO_DEP_PINS in hack/kubernetes-v1.X) before they are
# merged. Each step is a subcommand:
#
#   ci.sh versions            Print the matrix of Kubernetes versions to test.
#   ci.sh apply <version>     Apply the overlay's pins to the checkout in the
#                             current directory.
#   ci.sh vulncheck <dir>     Fail when the binaries reach a known vulnerability.
#   ci.sh conformance <dir>   Run the full conformance suite on kind.
#   ci.sh report              Sum up the job results for the required check.
set -euo pipefail

deps_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$deps_dir")"

# pins_of <overlay file>: the overlay's pins on one line, empty when it sets none.
pins_of() {
  # shellcheck disable=SC1090
  bash -c 'source "$1"; echo "${K8S_GO_DEP_PINS[*]:-}"' _ "$1"
}

# Prints {"version":["v1.35.11","v1.36.7"]}: the latest patch release of each
# minor version to test.
#   BASE_REF set: the minor versions with pins whose pins differ from BASE_REF
#     (all minor versions with pins when pin-go-deps.sh differs).
#   ONLY_MINOR set (e.g. v1.35): only that minor version, with or without pins.
cmd_versions() {
  cd "$repo_dir"
  local all_changed=false old_overlay overlay minor pins tags version
  if [ -n "${BASE_REF:-}" ] && ! git diff --quiet "${BASE_REF}" -- kubernetes-deps/pin-go-deps.sh; then
    all_changed=true
  fi
  old_overlay=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$old_overlay'" EXIT

  for overlay in hack/kubernetes-v*; do
    minor="${overlay#hack/kubernetes-}"
    if [ -n "${ONLY_MINOR:-}" ]; then
      [ "$minor" = "$ONLY_MINOR" ] || continue
    else
      pins=$(pins_of "$overlay")
      [ -n "$pins" ] || continue
      if [ -n "${BASE_REF:-}" ] && [ "$all_changed" = false ]; then
        git show "${BASE_REF}:${overlay}" > "$old_overlay" 2>/dev/null || : > "$old_overlay"
        [ "$pins" != "$(pins_of "$old_overlay")" ] || continue
      fi
    fi

    # A failed lookup must fail the job: skipping the minor would let the
    # required check pass without testing anything.
    if ! tags=$(git ls-remote --tags --refs https://github.com/kubernetes/kubernetes.git "${minor}.*"); then
      echo "Error: failed to list the Kubernetes ${minor} releases" >&2
      exit 1
    fi
    version=$(echo "$tags" | sed 's#.*refs/tags/##' | grep -E "^${minor//./\\.}\.[0-9]+$" | sort -V | tail -1 || true)
    if [ -z "$version" ]; then
      echo "Kubernetes ${minor} has no release yet, skipping" >&2
      continue
    fi
    echo "$version"
  done | jq -Rsc '{version: (split("\n") | map(select(length > 0)))}'
}

# Applies the pins of the version's overlay to the Kubernetes checkout in the
# current directory; does nothing when the overlay sets none.
cmd_apply() {
  local version="${1:?usage: $0 apply <kubernetes version, e.g. v1.36.7>}"
  local overlay="${repo_dir}/hack/kubernetes-${version%.*}" pins
  if [ ! -f "$overlay" ]; then
    echo "Error: ${overlay} does not exist" >&2
    exit 1
  fi
  pins=$(pins_of "$overlay")
  echo "Go dependency pins for Kubernetes ${version}: ${pins:-none}"
  "${deps_dir}/pin-go-deps.sh" "$pins"
}

# Fails when the Kubernetes binaries of the source tree reach any known
# vulnerability (govulncheck reports only code the binaries can call). Run it
# with the Go version the release builds with, so the stdlib is checked too.
# The report, with the version that fixes each one (the pin to add; stdlib ones
# need a Kubernetes release with a newer Go), goes to stdout, to
# GITHUB_STEP_SUMMARY when set, and as error annotations under GITHUB_ACTIONS.
# Env: GOVULNCHECK_VERSION (default v1.10.0).
cmd_vulncheck() {
  local k8s_dir="${1:?usage: $0 vulncheck <kubernetes source dir>}"
  local work count id aliases module version fixed
  work=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT

  GOWORK=off GOBIN="${work}/bin" go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION:-v1.10.0}"
  echo "Scanning the Kubernetes binaries in ${k8s_dir} with $(go version)..." >&2
  (cd "$k8s_dir" && "${work}/bin/govulncheck" -format json \
    ./cmd/kube-apiserver ./cmd/kube-controller-manager ./cmd/kube-scheduler \
    ./cmd/kubelet ./cmd/kubeadm ./cmd/kubectl) > "${work}/scan.json"

  # One line per reachable vulnerability and module: id, aliases, module, version, fix.
  jq -rs '
    (map(select(.osv) | .osv | {key: .id, value: ((.aliases // []) | unique | join(", "))}) | from_entries) as $aliases
    | map(select(.finding and .finding.trace[0].function) | .finding
        | {id: .osv, module: .trace[0].module, version: .trace[0].version, fixed: (.fixed_version // "none")})
    | unique
    | .[]
    | [.id, (($aliases[.id] // "") | if . == "" then "-" else . end), .module, .version, .fixed] | @tsv' \
    "${work}/scan.json" > "${work}/findings.tsv"

  count=$(cut -f1 "${work}/findings.tsv" | sort -u | grep -c . || true)
  {
    if [ "$count" -gt 0 ]; then
      echo "**${count} reachable vulnerabilities.** Pin each module to its fixed version in the overlay; stdlib ones need a Kubernetes release with a newer Go."
      echo
      echo "| ID | Aliases | Module | Version | Fixed in |"
      echo "| --- | --- | --- | --- | --- |"
      while IFS=$'\t' read -r id aliases module version fixed; do
        echo "| [${id}](https://pkg.go.dev/vuln/${id}) | ${aliases} | ${module} | ${version} | ${fixed} |"
      done < "${work}/findings.tsv"
    else
      echo "No reachable vulnerabilities."
    fi
  } > "${work}/report.md"

  cat "${work}/report.md"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    cat "${work}/report.md" >> "$GITHUB_STEP_SUMMARY"
  fi
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    while IFS=$'\t' read -r id _ module version fixed; do
      echo "::error title=${id} in ${module}::${module} ${version} reaches ${id} (https://pkg.go.dev/vuln/${id}); fixed in ${fixed}"
    done < "${work}/findings.tsv"
  fi
  [ "$count" -eq 0 ]
}

# Runs the full conformance suite on kind with kind's hack/ci/e2e-k8s.sh (the
# script upstream's ci-kubernetes-kind-conformance job runs), building the node
# image from the source tree, so its pins are what gets tested. The specs run
# in parallel ginkgo processes; ginkgo still runs the [Serial] ones one at a
# time. Env: KIND_VERSION (default v0.33.0), ARTIFACTS (test results),
# GINKGO_PARALLEL=n to run everything sequentially, PARALLEL=true to skip the
# [Serial] specs, FOCUS/SKIP to narrow the suite (see e2e-k8s.sh).
cmd_conformance() {
  local k8s_dir="${1:?usage: $0 conformance <kubernetes source dir>}"
  local kind_version="${KIND_VERSION:-v0.33.0}" tools_dir release expected
  export GINKGO_PARALLEL="${GINKGO_PARALLEL:-y}"
  tools_dir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tools_dir'" EXIT

  release="https://github.com/kubernetes-sigs/kind/releases/download/${kind_version}"
  curl -fsSLo "${tools_dir}/kind" "${release}/kind-linux-amd64"
  expected=$(curl -fsSL "${release}/kind-linux-amd64.sha256sum" | cut -d' ' -f1)
  echo "${expected}  ${tools_dir}/kind" | sha256sum -c -
  chmod +x "${tools_dir}/kind"
  curl -fsSLo "${tools_dir}/e2e-k8s.sh" "https://raw.githubusercontent.com/kubernetes-sigs/kind/${kind_version}/hack/ci/e2e-k8s.sh"

  export PATH="${tools_dir}:${PATH}"
  cd "$k8s_dir"
  bash "${tools_dir}/e2e-k8s.sh"
}

# Fails when a job failed or was cancelled, with an error annotation naming it
# and where to find the cause; skipped jobs pass (no pins to test, or
# vulncheck-only). Env: DETECT, VULNCHECK, UNIT, CONFORMANCE: the job results.
cmd_report() {
  local failed=0
  report_job() { # <result> <job name> <where to look>
    case "$1" in
      success | skipped) ;;
      *)
        echo "::error title=$2 ${1}::$2 ${1}: $3"
        failed=1
        ;;
    esac
  }
  if [ "${DETECT:-}" != success ]; then
    echo "::error title=detect ${DETECT:-}::detect ${DETECT:-did not run}: see its log, it lists the versions to test"
    failed=1
  fi
  report_job "${VULNCHECK:-}" "K8s vulnerability check" "see its annotations for the reachable vulnerabilities and the versions to pin"
  report_job "${UNIT:-}" "K8s unit tests" "see its log for the failing packages"
  report_job "${CONFORMANCE:-}" "K8s conformance tests" "see its log and the conformance-<version> artifact (junit_01.xml) for the failing specs"
  if [ "$failed" -eq 0 ]; then
    echo "All Go dependency pin checks passed (or had nothing to test)."
  fi
  return "$failed"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  versions | apply | vulncheck | conformance | report) "cmd_${cmd}" "$@" ;;
  *)
    echo "usage: $0 versions | apply <version> | vulncheck <dir> | conformance <dir> | report" >&2
    exit 2
    ;;
esac
