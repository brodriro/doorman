#!/bin/bash
# Runs the collector against every fixture in tests/fixtures/ and compares the
# output with its expected.json. Usage: tests/run.sh [fixture-name]
set -uo pipefail
cd "$(dirname "$0")/.."
status=0
for dir in tests/fixtures/${1:-*}/; do
  name=$(basename "$dir")
  if diff -u "$dir/expected.json" <(WM_FIXTURE_DIR="$dir" WM_NOW=1700000000 bin/doorman-scan | jq .); then
    echo "ok   $name"
  else
    echo "FAIL $name"
    status=1
  fi
done
exit $status
