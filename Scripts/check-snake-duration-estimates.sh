#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/snakefocus-snake-duration-checks.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
# Compile the actual Foundation-only speed enum, without linking UIKit. A
# refactor that moves or removes these enum boundaries fails the check loudly.
awk 'BEGIN { print "import Foundation" } /^enum SnakeSpeed:/ { copying=1 } /^enum SnakeSessionStage:/ { copying=0 } copying { print }' \
  "$project_root/SnakeFocus/SnakeSession.swift" > "$check_directory/SnakeSpeed.swift"
# Only map definitions are needed here, not the full simulator. The runtime
# check still hashes the entire engine source before trusting any estimate.
awk '/^enum SnakePhase:/ { done=1 } !done { print }' \
  "$project_root/SnakeFocus/SnakeEngine.swift" > "$check_directory/SnakeMaps.swift"
xcrun swiftc -whole-module-optimization -parse-as-library \
  "$check_directory/SnakeMaps.swift" \
  "$project_root/SnakeFocus/SnakeDurationEstimates.swift" \
  "$check_directory/SnakeSpeed.swift" \
  "$project_root/Tests/SnakeDurationEstimateChecks.swift" \
  -o "$check_directory/snake-duration-checks"
"$check_directory/snake-duration-checks" "$project_root"
