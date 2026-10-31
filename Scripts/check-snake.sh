#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/snakefocus-snake-checks.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
optimization="-O"
if [[ "${SNAKE_DEBUG_BENCHMARK:-0}" == "1" ]]; then
  optimization="-Onone"
  export SNAKE_BENCHMARK_ONLY=1
fi
xcrun swiftc "$optimization" -parse-as-library \
  "$project_root/SnakeFocus/SnakeEngine.swift" \
  "$project_root/Tests/SnakeEngineChecks.swift" \
  -o "$check_directory/snake-checks"
"$check_directory/snake-checks"
