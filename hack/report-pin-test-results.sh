#!/usr/bin/env bash
# Sums up the jobs of .github/workflows/test-go-dep-pins.yaml for its single
# required check: fails when a job failed or was cancelled, with an error
# annotation naming that job and where to find the cause. Skipped jobs pass,
# since nothing is tested when no pins change.
#
# Env: DETECT, VULNCHECK, UNIT, CONFORMANCE: the job results (needs.<job>.result).
set -euo pipefail

failed=0

# check <result> <job name> <where to look>
check() {
  case "$1" in
    success | skipped) ;;
    *)
      echo "::error title=$2 ${1}::$2 ${1}: $3"
      failed=1
      ;;
  esac
}

if [ "${DETECT:-}" != success ]; then
  echo "::error title=detect ${DETECT:-}::detect ${DETECT:-did not run}: see its log, it lists the versions and pins to test"
  failed=1
fi
check "${VULNCHECK:-}" "K8s vulnerability check" "see its annotations for the reachable vulnerabilities and the versions to pin"
check "${UNIT:-}" "K8s unit tests" "see its log for the failing packages"
check "${CONFORMANCE:-}" "K8s conformance tests" "see its log and the conformance-<version> artifact (junit_01.xml) for the failing specs"

if [ "$failed" -eq 0 ]; then
  echo "All Go dependency pin checks passed (or had no pins to test)."
fi
exit "$failed"
