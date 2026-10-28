#!/usr/bin/env bash
# Fails when an overlay pins a kine or tailscaled version that has no sha256 in
# download.sh, so a version bump without its checksums fails on the pull
# request instead of in the release build. Offline: it reads files only.
set -euo pipefail
cd "$(dirname "$0")"

eval "$(sed -n '/^fork_asset_sha256() {/,/^}/p' download.sh)"
default_tailscaled=$(sed -n 's/^TAILSCALED_VERSION="\(.*\)"$/\1/p' download.sh)
if [ -z "$default_tailscaled" ]; then
  echo "Error: no default TAILSCALED_VERSION in download.sh"
  exit 1
fi

fail=0
for overlay in kubernetes-v*; do
  read -r kine tailscaled < <(
    KINE_VERSION=""
    TAILSCALED_VERSION="$default_tailscaled"
    # shellcheck source=/dev/null
    source "./$overlay"
    echo "$KINE_VERSION $TAILSCALED_VERSION"
  )
  for arch in amd64 arm64; do
    for asset in "kine/$kine/kine-$arch" "tailscale/$tailscaled/tailscaled-linux-$arch"; do
      if ! fork_asset_sha256 "$asset" >/dev/null; then
        echo "Error: $overlay needs a sha256 for loft-sh/$asset in fork_asset_sha256 in hack/download.sh"
        fail=1
      fi
    done
  done
done
exit "$fail"
