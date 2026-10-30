#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/ioslab-snake-visual-checks.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
optimization="-O"
if [[ "${SNAKE_VISUAL_DEBUG:-0}" == "1" ]]; then
  optimization="-Onone"
fi
xcrun swiftc "$optimization" -parse-as-library \
  "$project_root/iOSLab/SnakeEngine.swift" \
  "$project_root/iOSLab/SnakeVisualGeometry.swift" \
  "$project_root/Tests/SnakeVisualChecks.swift" \
  -o "$check_directory/snake-visual-checks"
if [[ "${SNAKE_VISUAL_BENCHMARK:-0}" == "1" ]]; then
  "$check_directory/snake-visual-checks" --benchmark
else
  "$check_directory/snake-visual-checks"
fi
