#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$PROJECT_ROOT/CodeDrop.xcodeproj"
SCHEME="CodeDrop"
CONFIGURATION="Release"
DERIVED_DATA="$PROJECT_ROOT/build/DerivedData"
ARCHIVE_PATH="$PROJECT_ROOT/build/CodeDrop.xcarchive"
EXPORT_PATH="$PROJECT_ROOT/build/export"
EXPORT_PLIST="$PROJECT_ROOT/build/ExportOptions.plist"

# Write export options (copy app, no signing required for local distribution)
cat > "$EXPORT_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>mac-application</string>
</dict>
</plist>
PLIST

echo "==> Archiving ($CONFIGURATION)..."
if command -v xcpretty &>/dev/null; then
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -archivePath "$ARCHIVE_PATH" \
        | xcpretty
else
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "generic/platform=macOS" \
        -derivedDataPath "$DERIVED_DATA" \
        -archivePath "$ARCHIVE_PATH"
fi

echo "==> Exporting..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST"

APP="$EXPORT_PATH/CodeDrop.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown")
BUILD=$(defaults read "$APP/Contents/Info" CFBundleVersion 2>/dev/null || echo "unknown")

echo ""
echo "==> Done: $APP"
echo "    Version: $VERSION ($BUILD)"
