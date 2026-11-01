#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/snakefocus-design-lab.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT
xcrun swiftc -O -parse-as-library \
  "$project_root/SnakeFocus/SnakeEngine.swift" \
  "$project_root/SnakeFocus/SnakeVisualGeometry.swift" \
  "$project_root/SnakeFocus/LabRenderGeometry.swift" \
  "$project_root/Tests/LabRenderChecks.swift" \
  -o "$check_directory/design-lab-checks"
"$check_directory/design-lab-checks"
