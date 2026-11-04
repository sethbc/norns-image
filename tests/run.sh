#!/bin/bash
# Run the test suites: tests/run.sh unit|image|all
set -euo pipefail

cd "$(dirname "$0")"

case "${1:-all}" in
  unit)  suites=(unit) ;;
  image) suites=(image) ;;
  all)   suites=(unit image) ;;
  *)     echo "usage: $0 unit|image|all" >&2; exit 2 ;;
esac

for suite in "${suites[@]}"; do
  # A suite with no tests yet is not a failure.
  if compgen -G "$suite/*.bats" > /dev/null; then
    bats "$suite"
  else
    echo "tests/$suite: no tests"
  fi
done
