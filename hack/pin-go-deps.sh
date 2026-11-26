#!/usr/bin/env bash
# Raises Go dependencies of a kubernetes/kubernetes checkout to at least the
# given versions, for CVE fixes upstream has not shipped yet. A pin never
# downgrades: once upstream ships the same or a newer version, the pin is
# skipped and can be removed from hack/kubernetes-v1.X.
#
# Usage (from the kubernetes source root):
#   pin-go-deps.sh "golang.org/x/net@v0.47.0 google.golang.org/grpc@v1.72.1"
set -euo pipefail

applied=0
for pin in ${1:-}; do
  mod="${pin%@*}"
  want="${pin#*@}"
  if [ "$mod" = "$pin" ] || [ -z "$mod" ] || [ -z "$want" ]; then
    echo "Error: invalid pin '${pin}', expected <module>@<version>" >&2
    exit 1
  fi

  have=$(awk -v m="$mod" '$1==m{print $2} $1=="require" && $2==m{print $3}' go.mod | head -1)
  if [ -z "$have" ]; then
    echo "pin ${mod}@${want}: not a dependency, skipping"
    continue
  fi
  # ponytail: sort -V orders plain semver only, not pre-releases or pseudo-versions
  if [ "$(printf '%s\n%s\n' "$have" "$want" | sort -V | tail -1)" = "$have" ]; then
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
