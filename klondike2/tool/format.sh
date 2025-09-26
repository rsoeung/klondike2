#!/usr/bin/env bash
set -euo pipefail
# Consistent formatter wrapper. Forces line length to match .editorconfig.
# Usage: ./tool/format.sh [--check]

LINE_LEN=100
if [[ "${1-}" == "--check" ]]; then
  dart format --line-length $LINE_LEN --output=none --set-exit-if-changed .
  echo "Formatting check passed."
else
  dart format --line-length $LINE_LEN .
  echo "Formatting applied with line length $LINE_LEN."
fi
