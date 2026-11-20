#!/bin/zsh
# Builds Fokus with the Command Line Tools, installs it to /Applications and keeps it
# running: launchd restarts it after a crash or force quit, but not after a normal quit.
set -euo pipefail
cd "${0:A:h:h}"
DEVELOPER_DIR=${DEVELOPER_DIR:-$([[ -d /Applications/Xcode.app ]] && print /Applications/Xcode.app/Contents/Developer || print /Library/Developer/CommandLineTools)} swift build -c release --product Fokus
DEVELOPER_DIR=${DEVELOPER_DIR:-$([[ -d /Applications/Xcode.app ]] && print /Applications/Xcode.app/Contents/Developer || print /Library/Developer/CommandLineTools)} swift build -c release --product fokus-mcp
app=/Applications/Fokus.app
# Your own reverse-DNS ID keeps macOS permissions and settings stable. Put it in .fokus-local
# (ignored by git) as FOKUS_BUNDLE_ID=com.yourname.fokus, or pass it as an environment variable.
[[ -f .fokus-local ]] && source ./.fokus-local
label=${FOKUS_BUNDLE_ID:-local.fokus.app}
agent="$HOME/Library/LaunchAgents/$label.plist"
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
rm -rf -- "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Fokus "$app/Contents/MacOS/Fokus"
cp .build/release/fokus-mcp "$app/Contents/MacOS/fokus-mcp"
codesign --force --sign - --identifier "$label.mcp" "$app/Contents/MacOS/fokus-mcp"
cp Resources/Blocked.html "$app/Contents/Resources/"
cp Resources/Zone.icns "$app/Contents/Resources/Fokus.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Fokus</string>
  <key>CFBundleIdentifier</key><string>$label</string>
  <key>CFBundleName</key><string>Fokus</string>
  <key>CFBundleDisplayName</key><string>Fokus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>Fokus</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Based on Zone by Mo Rajabi.</string>
  <key>NSAppleEventsUsageDescription</key><string>Fokus liest Tab-Adressen, leitet gesperrte Websites um und zählt Zeit pro Domain lokal.</string>
</dict></plist>
PLIST
codesign --force --sign - --identifier "$label" --entitlements Resources/Zone-Local.entitlements "$app"
cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$app/Contents/MacOS/Fokus</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$agent"
print "Fokus installiert: $app"
