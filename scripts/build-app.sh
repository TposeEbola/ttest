#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Building QuickPlan.app requires macOS 14 or later and Xcode 15 or later.' >&2
  exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
  printf '%s\n' 'Swift was not found. Install Xcode 15 or later and select its command-line tools in Xcode Settings > Locations.' >&2
  exit 1
fi

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
swift build -c release --product QuickPlan
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/QuickPlan.app"
mkdir -p "$app_dir/Contents/MacOS"
install -m 755 "$binary_dir/QuickPlan" "$app_dir/Contents/MacOS/QuickPlan"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>QuickPlan</string>
  <key>CFBundleDisplayName</key><string>QuickPlan</string>
  <key>CFBundleExecutable</key><string>QuickPlan</string>
  <key>CFBundleIdentifier</key><string>com.quickplan.editor</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>QuickPlan Document</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.quickplan.document</string></array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.quickplan.document</string>
      <key>UTTypeDescription</key><string>QuickPlan Document</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>quickplan</string></array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$app_dir"
fi
printf 'Built %s\n' "$app_dir"
