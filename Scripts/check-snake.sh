#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/ioslab-snake-checks.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
xcrun swiftc -O -parse-as-library \
  "$project_root/iOSLab/SnakeEngine.swift" \
  "$project_root/Tests/SnakeEngineChecks.swift" \
  -o "$check_directory/snake-checks"
"$check_directory/snake-checks"
