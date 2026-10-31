#!/bin/zsh
set -eu
project_root="${0:A:h:h}"
simulation_directory="$(mktemp -d "${TMPDIR:-/tmp}/ioslab-snake-duration.XXXXXX")"
trap 'rm -rf "$simulation_directory"' EXIT
cp "$project_root/iOSLab/SnakeEngine.swift" "$simulation_directory/SnakeEngine.swift"
export SNAKE_ESTIMATE_ENGINE_SHA256="$(shasum -a 256 "$simulation_directory/SnakeEngine.swift" | awk '{print $1}')"
export SNAKE_ESTIMATE_SOURCE_COMMIT="$(git -C "$project_root" rev-parse HEAD)"
export SNAKE_ESTIMATE_BASE_ENGINE_SHA256="$(git -C "$project_root" show HEAD:iOSLab/SnakeEngine.swift | shasum -a 256 | awk '{print $1}')"
export SNAKE_ESTIMATE_COMPILER="$(xcrun swiftc --version)"
xcrun swiftc -O -parse-as-library \
  "$simulation_directory/SnakeEngine.swift" \
  "$project_root/Tests/SnakeDurationSimulation.swift" \
  -o "$simulation_directory/snake-duration"
simulation_arguments=()
write_estimates=0
for argument in "$@"; do
  if [[ "$argument" == "--write" ]]; then
    write_estimates=1
  else
    simulation_arguments+=("$argument")
  fi
done
if [[ "$write_estimates" == "1" ]]; then
  mkdir -p "$simulation_directory/generated/Docs" "$simulation_directory/generated/iOSLab"
  "$simulation_directory/snake-duration" "${simulation_arguments[@]}" --write-root "$simulation_directory/generated"
  current_engine_hash="$(shasum -a 256 "$project_root/iOSLab/SnakeEngine.swift" | awk '{print $1}')"
  if [[ "$current_engine_hash" != "$SNAKE_ESTIMATE_ENGINE_SHA256" ]]; then
    print -u2 "Engine source changed during simulation; production estimates were not replaced."
    exit 2
  fi
  mv "$simulation_directory/generated/Docs/SnakeDurationSimulation.json" "$project_root/Docs/SnakeDurationSimulation.json"
  mv "$simulation_directory/generated/iOSLab/SnakeDurationEstimates.swift" "$project_root/iOSLab/SnakeDurationEstimates.swift"
else
  "$simulation_directory/snake-duration" "${simulation_arguments[@]}"
fi
