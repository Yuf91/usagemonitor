#!/bin/bash
# Builds a universal (Apple Silicon + Intel) ad-hoc signed app into dist/ and a zip for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="${BUNDLE_ID:-io.github.yuf91.usagemonitor}"
VERSION="${VERSION:-1.2.2}"
BUILD_NUMBER="${BUILD_NUMBER:-5}"
ARCHS="${ARCHS:-arm64 x86_64}"

# Module caches run to hundreds of MB per architecture, so keep them out of the project and delete them afterwards.
CACHE="$(mktemp -d)"
trap 'rm -rf "$CACHE"' EXIT
export CLANG_MODULE_CACHE_PATH="$CACHE/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE/swiftpm"
mkdir -p .build/release
python3 scripts/compiler-overlay.py
slices=()
for arch in $ARCHS; do
    xcrun swiftc -vfsoverlay "$PWD/.build/compiler-overlay.json" -O -swift-version 5 -target "$arch-apple-macosx13.0" -module-cache-path "$CACHE/swift-$arch" Sources/AIUsageBar/*.swift -o ".build/release/AIUsageBar-$arch"
    slices+=(".build/release/AIUsageBar-$arch")
done
lipo -create "${slices[@]}" -output .build/release/AIUsageBar

APP="$PWD/dist/AI Usage Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AIUsageBar "$APP/Contents/MacOS/AIUsageBar"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AIUsageBar</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>AI Usage Bar</string>
<key>CFBundleDisplayName</key><string>AI Usage Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/AIUsageBar" --self-test

ZIP="$PWD/dist/AIUsageBar-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
printf '\nBuilt: %s\nZip:   %s\n' "$APP" "$ZIP"
