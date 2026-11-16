#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_root/build/mac"

xcodebuild \
  -project "$project_root/BrickByBrick.xcodeproj" \
  -scheme BrickByBrick \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$build_dir" \
  build

open "$build_dir/Build/Products/Debug/BrickByBrick.app"
