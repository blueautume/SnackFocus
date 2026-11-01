#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
check_directory="$(mktemp -d "${TMPDIR:-/tmp}/snakefocus-localization-checks.XXXXXX")"
trap 'rm -rf "$check_directory"' EXIT

# Exercise Bundle lookup against the same .lproj files shipped by the app.
bundle="$check_directory/SnakeLocalizationChecks.bundle"
mkdir -p "$bundle/Contents/Resources"
cp -R "$project_root/SnakeFocus/en.lproj" "$project_root/SnakeFocus/zh-Hans.lproj" "$bundle/Contents/Resources/"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.lihao.snakefocus.localization-checks</string>
<key>CFBundleName</key><string>SnakeLocalizationChecks</string>
<key>CFBundlePackageType</key><string>BNDL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST

# Compile the actual Foundation-only enum without importing UIKit or running a
# session. A moved/renamed enum boundary fails compilation rather than silently
# leaving a stale list of speed choices in this check.
awk 'BEGIN { print "import Foundation" } /^enum SnakeSpeed:/ { copying=1 } /^enum SnakeSessionStage:/ { copying=0 } copying { print }' \
  "$project_root/SnakeFocus/SnakeSession.swift" > "$check_directory/SnakeSpeed.swift"
xcrun swiftc -whole-module-optimization -parse-as-library \
  "$project_root/SnakeFocus/SnakeEngine.swift" \
  "$project_root/SnakeFocus/SnakeVisualGeometry.swift" \
  "$project_root/SnakeFocus/SnakeDurationEstimates.swift" \
  "$project_root/SnakeFocus/SnakeLocalization.swift" \
  "$check_directory/SnakeSpeed.swift" \
  "$project_root/Tests/SnakeLocalizationChecks.swift" \
  -o "$check_directory/localization-checks"
"$check_directory/localization-checks" "$project_root" "$bundle"
