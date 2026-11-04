#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'QuickPlan uses SwiftUI and requires macOS 14 or later. On Linux, run swift test --filter BlueprintCoreTests to test the model.' >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  printf '%s\n' 'Swift was not found. Install Xcode 15 or later and select its command-line tools in Xcode Settings > Locations.' >&2
  exit 1
fi

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
swift build -c debug --product QuickPlan
binary_dir="$(swift build -c debug --show-bin-path)"
exec "$binary_dir/QuickPlan"
