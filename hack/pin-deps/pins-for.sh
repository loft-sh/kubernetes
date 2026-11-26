#!/usr/bin/env bash
# Prints, on one line, the Go dependency pins that apply to a Kubernetes patch
# release, from K8S_GO_DEP_PINS in its overlay hack/kubernetes-v1.X:
#
#   K8S_GO_DEP_PINS=(
#     v1.36.6:golang.org/x/net@v0.62.0   # CVE-...
#     v1.36.7:google.golang.org/grpc@v1.83.2
#   )
#
# Each entry, <since>:<module>@<version>, applies to <since> and every later
# patch release of that minor version, not to earlier ones. When a module is
# pinned more than once, the highest version wins. pin-go-deps.sh then skips a
# pin where upstream already ships the same or a newer version.
#
# Usage: pins-for.sh <kubernetes version, e.g. v1.36.7>
set -euo pipefail

version="${1:?usage: $0 <kubernetes version, e.g. v1.36.7>}"
if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: '${version}' is not a Kubernetes release version (vX.Y.Z)" >&2
  exit 1
fi
minor="${version%.*}"
overlay="$(cd "$(dirname "$0")/.." && pwd)/kubernetes-${minor}"
if [ ! -f "$overlay" ]; then
  echo "Error: ${overlay} does not exist" >&2
  exit 1
fi

# A broken overlay must fail rather than silently yield no pins.
# shellcheck disable=SC1090
if ! listed=$(bash -ec 'source "$1"; [ -z "${K8S_GO_DEP_PINS+x}" ] || printf "%s\n" "${K8S_GO_DEP_PINS[@]}"' _ "$overlay"); then
  echo "Error: failed to read ${overlay}" >&2
  exit 1
fi
mapfile -t entries <<< "$listed"
[ -n "$listed" ] || entries=()

# <since> <= <version>, both vX.Y.Z
not_after() {
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

for entry in "${entries[@]}"; do
  since="${entry%%:*}"
  pin="${entry#*:}"
  if [ "$since" = "$entry" ] || ! [[ "$since" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$pin" != *@* ]]; then
    echo "Error: ${overlay}: invalid pin '${entry}', expected <since>:<module>@<version>, e.g. v1.36.7:golang.org/x/net@v0.62.0" >&2
    exit 1
  fi
  if [ "${since%.*}" != "$minor" ]; then
    echo "Error: ${overlay}: pin '${entry}' is for another minor version than ${minor}" >&2
    exit 1
  fi
  if not_after "$since" "$version"; then
    echo "${pin%@*} ${pin#*@}"
  fi
done | sort -k1,1 -k2,2V | awk '{ v[$1] = $2 } END { for (m in v) print m "@" v[m] }' | sort | paste -sd' ' -
