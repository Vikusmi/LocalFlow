#!/bin/bash
# Builds LocalFlow.app and installs it to /Applications.
set -euo pipefail
cd "$(dirname "$0")"

# Workaround for stale files in some Command Line Tools installs (they break `import Foundation`).
# Builds against a VFS overlay that hides them; nothing on the system is modified.
CLT=$(xcode-select -p)
T="$PWD/.toolchain"
BUILD_ARGS=()
if [ -f "$CLT/usr/include/swift/module.modulemap" ] && [ -f "$CLT/usr/include/swift/bridging.modulemap" ]; then
    echo "Applying Command Line Tools workaround…"
    rm -rf "$T" && mkdir -p "$T"
    : > "$T/empty.modulemap"
    cp -R "$CLT/usr/lib/swift/pm/ManifestAPI" "$CLT/usr/lib/swift/pm/PluginAPI" "$T/"
    find "$T" -name "*.private.swiftinterface" -delete
    cat > "$T/overlay.json" <<JSON
{"version": 0, "case-sensitive": "false", "roots": [
  {"name": "$CLT/usr/include/swift/module.modulemap", "type": "file", "external-contents": "$T/empty.modulemap"}
]}
JSON
    cat > "$T/swiftc" <<SH
#!/bin/bash
exec "$CLT/usr/bin/swiftc" "\$@" -vfsoverlay "$T/overlay.json" -Xcc -ivfsoverlay -Xcc "$T/overlay.json"
SH
    chmod +x "$T/swiftc"
    export SWIFTPM_CUSTOM_LIBS_DIR="$T" SWIFT_EXEC_MANIFEST="$T/swiftc"
    BUILD_ARGS=(-Xswiftc -vfsoverlay -Xswiftc "$T/overlay.json" -Xcc -ivfsoverlay -Xcc "$T/overlay.json")
fi

swift build -c release ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}

APP="build/LocalFlow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LocalFlow "$APP/Contents/MacOS/LocalFlow"
# SwiftPM resource bundles from dependencies (if any)
find .build/release -maxdepth 1 -name "*.bundle" -exec cp -R {} "$APP/Contents/Resources/" \;

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LocalFlow</string>
    <key>CFBundleDisplayName</key><string>LocalFlow</string>
    <key>CFBundleIdentifier</key><string>local.localflow.app</string>
    <key>CFBundleExecutable</key><string>LocalFlow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>LocalFlow records your voice while you hold the dictation shortcut. Audio never leaves your Mac.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

rm -rf /Applications/LocalFlow.app
cp -R "$APP" /Applications/
echo "Installed /Applications/LocalFlow.app"
