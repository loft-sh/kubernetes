#!/usr/bin/env bash
# Raises Go dependencies of a kubernetes/kubernetes checkout to at least the
# given versions, for CVE fixes upstream has not shipped yet. A pin never
# downgrades: once upstream ships the same or a newer version, the pin is
# skipped and can be removed from hack/kubernetes-v1.X.
#
# Pins must be release versions (vX.Y.Z, optionally +incompatible); pre-release
# and pseudo-versions are rejected because they cannot be ordered reliably.
#
# Usage (from the kubernetes source root):
#   pin-go-deps.sh "golang.org/x/net@v0.47.0 google.golang.org/grpc@v1.72.1"
set -euo pipefail

# newer <a> <b>: succeeds when release version a is newer than b.
newer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ]
}

applied=0
for pin in ${1:-}; do
  mod="${pin%@*}"
  want="${pin#*@}"
  if [ "$mod" = "$pin" ] || [ -z "$mod" ] || [ -z "$want" ]; then
    echo "Error: invalid pin '${pin}', expected <module>@<version>" >&2
    exit 1
  fi
  if ! [[ "$want" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(\+incompatible)?$ ]]; then
    echo "Error: pin '${pin}' is not a release version (vX.Y.Z)" >&2
    exit 1
  fi

  have=$(awk -v m="$mod" '$1==m{print $2} $1=="require" && $2==m{print $3}' go.mod | head -1)
  if [ -z "$have" ]; then
    echo "Error: pin '${pin}': ${mod} is not a dependency of this Kubernetes version (misspelled module path?)" >&2
    exit 1
  fi

  # Compare release parts; upstream may be on a pre-release or pseudo-version
  # of the pinned release (v1.2.0-rc.1 < v1.2.0), which the pin then replaces.
  have_release="${have%%[-+]*}"
  want_release="${want%%+*}"
  if [ "$have" = "$want" ] || newer "$have_release" "$want_release" \
    || { [ "$have_release" = "$want_release" ] && [[ "$have" != *-* ]]; }; then
    echo "pin ${mod}@${want}: upstream already has ${have}, skipping (pin can be removed)"
    continue
  fi

  echo "pin ${mod}: ${have} -> ${want}"
  ./hack/pin-dependency.sh "$mod" "$want"
  applied=1
done

if [ "$applied" -eq 1 ]; then
  ./hack/update-vendor.sh
fi
