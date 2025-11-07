#!/bin/sh

if [ -z "$*" ]; then
  echo "usage: $0 file1 [file2 ... fileN]"
fi

for exe in "${@}"; do
  if [ ! -x "${exe}" ]; then
    echo "$exe: file not found" >&2
    exit 1
  fi

  # Check if the binary uses any crypto packages
  # Use grep without -c, then count lines with wc
  crypto_imports=$(go tool nm "${exe}" | grep "crypto/" | wc -l)

  if [ "$crypto_imports" -eq 0 ]; then
    echo "${exe}: no crypto usage (FIPS not applicable) ✓"
    continue
  fi

  if [ "$(go tool nm "${exe}" | grep -c "crypto/internal/fips140/v1.0.0")" -eq 0 ]; then
    echo "${exe}: missing Go Cryptographic Module version v1.0.0 symbols" >&2
    exit 1
  fi
done
