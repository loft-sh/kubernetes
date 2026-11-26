#!/usr/bin/env bash
# Prints the GitHub Actions matrix of Kubernetes versions to test for Go
# dependency pins (K8S_GO_DEP_PINS in hack/kubernetes-v1.X), as
#   {"version":["v1.35.11","v1.36.7"]}
# Each minor version is tested on its latest patch release. The jobs read the
# pins from the overlay themselves.
#
# BASE_REF set: the minor versions with pins whose pins differ from BASE_REF
#   (all minor versions with pins when hack/pin-go-deps.sh differs).
# ONLY_MINOR set (e.g. v1.35): only that minor version, with or without pins.
set -euo pipefail
cd "$(dirname "$0")/.."

pins_of() {
  # shellcheck disable=SC1090
  bash -c 'source "$1"; echo "${K8S_GO_DEP_PINS[*]:-}"' _ "$1"
}

all_changed=false
if [ -n "${BASE_REF:-}" ] && ! git diff --quiet "${BASE_REF}" -- hack/pin-go-deps.sh; then
  all_changed=true
fi

old_overlay=$(mktemp)
trap 'rm -f "$old_overlay"' EXIT

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

  version=$(git ls-remote --tags --refs https://github.com/kubernetes/kubernetes.git "${minor}.*" \
    | sed 's#.*refs/tags/##' | grep -E "^${minor//./\\.}\.[0-9]+$" | sort -V | tail -1 || true)
  if [ -z "$version" ]; then
    echo "Kubernetes ${minor} has no release yet, skipping" >&2
    continue
  fi
  echo "$version"
done | jq -Rsc '{version: (split("\n") | map(select(length > 0)))}'
