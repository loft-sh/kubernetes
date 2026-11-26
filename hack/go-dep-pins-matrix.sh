#!/usr/bin/env bash
# Prints the GitHub Actions matrix of Kubernetes versions whose Go dependency
# pins (K8S_GO_DEP_PINS in hack/kubernetes-v1.X) need testing, as
#   {"include":[{"version":"v1.35.11","pins":"golang.org/x/net@v0.47.0 ..."}]}
# Each minor version with pins is tested on its latest patch release.
#
# BASE_REF set: only the minor versions whose pins differ from BASE_REF (all
#   minor versions with pins when hack/pin-go-deps.sh differs from BASE_REF).
# ONLY_MINOR set (e.g. v1.35): only that minor version, changed or not.
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
  if [ -n "${ONLY_MINOR:-}" ] && [ "$minor" != "$ONLY_MINOR" ]; then
    continue
  fi

  pins=$(pins_of "$overlay")
  if [ -z "$pins" ]; then
    continue
  fi

  if [ -n "${BASE_REF:-}" ] && [ "$all_changed" = false ]; then
    git show "${BASE_REF}:${overlay}" > "$old_overlay" 2>/dev/null || : > "$old_overlay"
    if [ "$pins" = "$(pins_of "$old_overlay")" ]; then
      continue
    fi
  fi

  version=$(git ls-remote --tags --refs https://github.com/kubernetes/kubernetes.git "${minor}.*" \
    | sed 's#.*refs/tags/##' | grep -E "^${minor//./\\.}\.[0-9]+$" | sort -V | tail -1 || true)
  if [ -z "$version" ]; then
    echo "${overlay} pins Go dependencies but Kubernetes ${minor} has no release yet, skipping" >&2
    continue
  fi

  jq -nc --arg version "$version" --arg pins "$pins" '{version: $version, pins: $pins}'
done | jq -sc '{include: .}'
