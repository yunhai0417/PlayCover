#!/bin/zsh
#
# Build PlayTools.xcframework from the local PlayTools repository into Vendor/.
# PlayCover embeds this framework at runtime; it is never linked at compile time.
#
# Usage:
#   scripts/build-playtools.sh                 # builds from ../PlayTools (sibling clone)
#   PLAYTOOLS_DIR=/path/to/PlayTools scripts/build-playtools.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAYTOOLS_DIR="${PLAYTOOLS_DIR:-$ROOT/../PlayTools}"
OUTPUT_DIR="$ROOT/Vendor"
XCODEPROJ="$PLAYTOOLS_DIR/PlayTools.xcodeproj"

if [ ! -d "$XCODEPROJ" ]; then
    echo "error: PlayTools project not found at $XCODEPROJ" >&2
    echo "Clone PlayCover/PlayTools next to this repo, or set PLAYTOOLS_DIR." >&2
    exit 1
fi

DERIVED_DATA="$ROOT/.playtools-build"

echo "Building PlayTools (Release, generic/platform=iOS) from $PLAYTOOLS_DIR"
echo "(SPM packages resolve on first run only; later runs reuse $DERIVED_DATA offline)"
xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "PlayTools" \
    -configuration "Release" \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -skipPackageUpdates \
    CODE_SIGNING_ALLOWED=NO \
    build

BUILT_FRAMEWORK="$DERIVED_DATA/Build/Products/Release-iphoneos/PlayTools.framework"
if [ ! -d "$BUILT_FRAMEWORK" ]; then
    echo "error: built framework not found at $BUILT_FRAMEWORK" >&2
    exit 1
fi

echo "Packing xcframework into $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
XCFRAMEWORK="$OUTPUT_DIR/PlayTools.xcframework"
rm -rf "$XCFRAMEWORK"
mkdir -p "$XCFRAMEWORK/ios-arm64"
cp -R "$BUILT_FRAMEWORK" "$XCFRAMEWORK/ios-arm64/PlayTools.framework"
cat > "$XCFRAMEWORK/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>AvailableLibraries</key>
	<array>
		<dict>
			<key>LibraryIdentifier</key>
			<string>ios-arm64</string>
			<key>LibraryPath</key>
			<string>PlayTools.framework</string>
			<key>SupportedArchitectures</key>
			<array>
				<string>arm64</string>
			</array>
			<key>SupportedPlatform</key>
			<string>ios</string>
			<key>SupportedPlatformVersion</key>
			<string>15.0</string>
		</dict>
	</array>
	<key>CFBundlePackageType</key>
	<string>XFWK</string>
	<key>XCFrameworkFormatVersion</key>
	<string>1.0</string>
</dict>
</plist>
PLIST

git -C "$PLAYTOOLS_DIR" rev-parse HEAD > "$OUTPUT_DIR/PlayTools.commit"

echo "Done. Built from commit $(cat "$OUTPUT_DIR/PlayTools.commit")"
