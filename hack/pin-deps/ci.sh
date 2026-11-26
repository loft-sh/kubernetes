#!/usr/bin/env bash
# CI steps of .github/workflows/test-go-dep-pins.yaml, which tests the Go
# dependency pins (K8S_GO_DEP_PINS in hack/kubernetes-v1.X, see pins-for.sh)
# before they are merged. Each step is a subcommand:
#
#   ci.sh versions            Print the matrix of Kubernetes versions to test.
#   ci.sh apply <version>     Apply that patch release's pins to the checkout
#                             in the current directory.
#   ci.sh vulncheck <dir>     Fail when the binaries reach a known vulnerability.
#   ci.sh e2e <dir>           Run the Kubernetes e2e tests on kind.
#   ci.sh release-e2e <version>
#                             Clone a patch release, apply its pins and run the
#                             e2e tests on kind; the release workflow runs it
#                             before publishing binaries built from source.
#   ci.sh report              Sum up the job results for the required check.
set -euo pipefail

deps_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(cd "${deps_dir}/../.." && pwd)"

# entries_of <overlay file>: its K8S_GO_DEP_PINS entries, one per line.
entries_of() {
  # shellcheck disable=SC1090
  bash -ec 'source "$1"; [ -z "${K8S_GO_DEP_PINS+x}" ] || printf "%s\n" "${K8S_GO_DEP_PINS[@]}"' _ "$1"
}

# released <minor>: its stable patch releases, oldest first.
released() {
  local tags
  # A failed lookup must fail the job: skipping the minor would let the
  # required check pass without testing anything.
  if ! tags=$(git ls-remote --tags --refs https://github.com/kubernetes/kubernetes.git "${1}.*"); then
    echo "Error: failed to list the Kubernetes ${1} releases" >&2
    exit 1
  fi
  echo "$tags" | sed 's#.*refs/tags/##' | grep -E "^${1//./\\.}\.[0-9]+$" | sort -V || true
}

# Prints {"version":["v1.36.6","v1.36.7"]}: the Kubernetes patch releases to test.
#   BASE_REF set (pull requests): for each minor version whose pin entries
#     differ from BASE_REF, the "since" version of each new or changed entry
#     and the latest patch release, which inherits every entry. When
#     pin-go-deps.sh or pins-for.sh differ, the latest patch release of every
#     minor version with pins.
#   ONLY_VERSION set (manual runs): that version, e.g. v1.36.6, or the latest
#     patch release of a minor version, e.g. v1.36, with or without pins.
cmd_versions() {
  cd "$repo_dir"
  local all_changed=false old_overlay overlay minor new_entries old_entries changed releases latest since
  if [ -n "${BASE_REF:-}" ] && ! git diff --quiet "${BASE_REF}" -- hack/pin-deps/pin-go-deps.sh hack/pin-deps/pins-for.sh; then
    all_changed=true
  fi
  old_overlay=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$old_overlay'" EXIT

  if [ -n "${ONLY_VERSION:-}" ]; then
    if [[ "$ONLY_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      released "${ONLY_VERSION%.*}" | grep -qx "$ONLY_VERSION" || { echo "Error: Kubernetes ${ONLY_VERSION} is not released" >&2; exit 1; }
      echo "$ONLY_VERSION"
    elif [[ "$ONLY_VERSION" =~ ^v[0-9]+\.[0-9]+$ ]]; then
      released "$ONLY_VERSION" | tail -1
    else
      echo "Error: '${ONLY_VERSION}' is neither a minor (v1.36) nor a patch (v1.36.7) version" >&2
      exit 1
    fi | jq -Rsc '{version: (split("\n") | map(select(length > 0)))}'
    return
  fi

  for overlay in hack/kubernetes-v*; do
    minor="${overlay#hack/kubernetes-}"
    new_entries=$(entries_of "$overlay")
    old_entries=""
    if [ -n "${BASE_REF:-}" ] && git show "${BASE_REF}:${overlay}" > "$old_overlay" 2>/dev/null; then
      old_entries=$(entries_of "$old_overlay")
    fi
    if [ -n "${BASE_REF:-}" ] && [ "$all_changed" = false ]; then
      [ "$new_entries" != "$old_entries" ] || continue
      # entries that are new or changed in this pull request
      changed=$(comm -23 <(echo "$new_entries" | sed '/^$/d' | sort -u) <(echo "$old_entries" | sed '/^$/d' | sort -u))
    else
      [ -n "$new_entries" ] || continue
      changed=""
    fi

    releases=$(released "$minor")
    latest=$(echo "$releases" | tail -1)
    if [ -z "$latest" ]; then
      echo "Kubernetes ${minor} has no release yet, skipping" >&2
      continue
    fi
    echo "$latest"
    for since in $(echo "$changed" | sed '/^$/d; s/:.*//' | sort -u); do
      if echo "$releases" | grep -qx "$since"; then
        echo "$since"
      else
        echo "Kubernetes ${since} is not released yet; its pins are tested on ${latest}" >&2
      fi
    done
  done | sort -uV | jq -Rsc '{version: (split("\n") | map(select(length > 0)))}'
}

# Applies the pins of that patch release (pins-for.sh) to the Kubernetes
# checkout in the current directory; does nothing when none apply.
cmd_apply() {
  local version="${1:?usage: $0 apply <kubernetes version, e.g. v1.36.7>}" pins
  pins=$("${deps_dir}/pins-for.sh" "$version")
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

# Runs the Kubernetes e2e tests on kind with kind's hack/ci/e2e-k8s.sh (the
# script upstream's kind jobs run), building the node image from the source
# tree, so its pins are what gets tested. By default it runs the specs of
# upstream's pull-kubernetes-e2e-kind presubmit (no feature, slow, serial,
# disruptive or flaky ones) plus the whole conformance suite, serial ones
# included. The specs run in parallel ginkgo processes; ginkgo still runs the
# [Serial] ones one at a time.
# Env: KIND_VERSION (default v0.33.0), ARTIFACTS (test results), LABEL_FILTER
# to pick other specs, GINKGO_PARALLEL=n to run everything sequentially,
# FOCUS/SKIP (see e2e-k8s.sh).
cmd_e2e() {
  local k8s_dir="${1:?usage: $0 e2e <kubernetes source dir>}"
  local kind_version="${KIND_VERSION:-v0.33.0}" tools_dir release expected
  export GINKGO_PARALLEL="${GINKGO_PARALLEL:-y}"
  export LABEL_FILTER="${LABEL_FILTER:-(Feature: isEmpty && !Slow && !Serial && !Disruptive && !Flaky) || Conformance}"
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

# Clones the patch release into a temporary directory, applies its pins with
# the Go version it builds with (GOTOOLCHAIN from .go-version) and runs the e2e
# tests on kind. Env: as for e2e; ARTIFACTS defaults to
# ./e2e-artifacts/<version>.
cmd_release_e2e() {
  local version="${1:?usage: $0 release-e2e <kubernetes version, e.g. v1.36.7>}"
  local artifacts="${ARTIFACTS:-${PWD}/e2e-artifacts/${version}}" work rc=0
  work=$(mktemp -d)
  git -c advice.detachedHead=false clone -b "$version" --depth=1 https://github.com/kubernetes/kubernetes.git "${work}/kubernetes"
  (
    cd "${work}/kubernetes"
    GOTOOLCHAIN="go$(cat .go-version)"
    export GOTOOLCHAIN
    cmd_apply "$version"
    ARTIFACTS="$artifacts" cmd_e2e "${work}/kubernetes"
  ) || rc=$?
  # The Go build cache under _output is read-only.
  chmod -R u+w "$work" 2>/dev/null || true
  rm -rf "$work"
  return "$rc"
}

# Fails when a job failed or was cancelled, with an error annotation naming it
# and where to find the cause; skipped jobs pass (no pins to test, or
# vulncheck-only). Env: DETECT, VULNCHECK, UNIT, E2E: the job results.
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
  report_job "${E2E:-}" "K8s e2e tests" "see its log and the e2e-<version> artifact (junit_01.xml) for the failing specs"
  if [ "$failed" -eq 0 ]; then
    echo "All Go dependency pin checks passed (or had nothing to test)."
  fi
  return "$failed"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  versions | apply | vulncheck | e2e | report) "cmd_${cmd}" "$@" ;;
  release-e2e) cmd_release_e2e "$@" ;;
  *)
    echo "usage: $0 versions | apply <version> | vulncheck <dir> | e2e <dir> | release-e2e <version> | report" >&2
    exit 2
    ;;
esac
