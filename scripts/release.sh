#!/bin/zsh
# Builds a shareable Fokus: Fokus-<version>.dmg for new installs, plus the signed zip the app updates from.
#   scripts/release.sh 0.2.0              builds into dist/<version>/
#   scripts/release.sh 0.2.0 --publish    also creates the GitHub release that running apps pick up
# The update key lives in the Keychain (scripts/update-key.swift). Without it, installed apps reject the update.
set -euo pipefail
cd "${0:A:h:h}"
version=${1:?Version fehlt, z. B. scripts/release.sh 0.2.0}
publish=${2:-}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}
bundle_id=${FOKUS_RELEASE_ID:-de.jannikhiller.fokus}
repo=${FOKUS_RELEASE_REPO:-Jnooo-cloud/fokus-releases}
out=dist/$version
[[ -e $out ]] && { print "dist/$version gibt es schon. Neue Versionsnummer nehmen."; exit 1; }
mkdir -p "$out"

public_key=$(swift scripts/update-key.swift public)
swift build -c release --product Fokus
swift build -c release --product fokus-mcp

app=$out/Fokus.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Fokus .build/release/fokus-mcp "$app/Contents/MacOS/"
cp Resources/Blocked.html "$app/Contents/Resources/"
cp Resources/Zone.icns "$app/Contents/Resources/Fokus.icns"
# The browser permission prompt shows this text in the Mac's language.
mkdir -p "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/de.lproj"
print '"NSAppleEventsUsageDescription" = "Fokus reads tab addresses, redirects blocked websites and counts time per domain, all on this Mac.";' > "$app/Contents/Resources/en.lproj/InfoPlist.strings"
print '"NSAppleEventsUsageDescription" = "Fokus liest Tab-Adressen, leitet gesperrte Websites um und zählt Zeit pro Domain, alles auf diesem Mac.";' > "$app/Contents/Resources/de.lproj/InfoPlist.strings"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>de</string></array>
  <key>CFBundleExecutable</key><string>Fokus</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleName</key><string>Fokus</string>
  <key>CFBundleDisplayName</key><string>Fokus</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleIconFile</key><string>Fokus</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Based on Zone by Mo Rajabi.</string>
  <key>NSAppleEventsUsageDescription</key><string>Fokus reads tab addresses, redirects blocked websites and counts time per domain, all on this Mac.</string>
  <key>FokusUpdateRepo</key><string>$repo</string>
  <key>FokusUpdateKey</key><string>$public_key</string>${FOKUS_DATA_FOLDER:+
  <key>FokusDataFolder</key><string>$FOKUS_DATA_FOLDER</string>}
</dict></plist>
PLIST
codesign --force --sign - --identifier "$bundle_id.mcp" "$app/Contents/MacOS/fokus-mcp"
codesign --force --sign - --identifier "$bundle_id" --entitlements Resources/Zone-Local.entitlements "$app"

# Update archive for apps that are already installed.
ditto -c -k --keepParent "$app" "$out/Fokus-$version.zip"
swift scripts/update-key.swift sign "$out/Fokus-$version.zip" > "$out/Fokus-$version.zip.sig"

# Disk image for new installs: app, Applications link and a background with the steps.
stage=$out/dmg
mkdir -p "$stage/.background"
ditto "$app" "$stage/Fokus.app"
ln -s /Applications "$stage/Applications"
swift scripts/dmg-background.swift "$stage/.background/background.png"
hdiutil create -quiet -volname Fokus -srcfolder "$stage" -fs HFS+ -format UDRW "$out/rw.dmg"
device=$(hdiutil attach -readwrite -noverify -noautoopen "$out/rw.dmg" | awk '/\/Volumes\/Fokus/ {print $1; exit}')
# The window layout needs Finder automation. Without it the image still works, just unstyled.
osascript <<'APPLESCRIPT' || print "Hinweis: Fenster-Layout übersprungen (Finder-Zugriff fehlt)."
tell application "Finder"
  tell disk "Fokus"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 588}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 96
    set background picture of opts to file ".background:background.png"
    set position of item "Fokus.app" of container window to {190, 170}
    set position of item "Applications" of container window to {450, 170}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$device"
hdiutil convert -quiet "$out/rw.dmg" -format UDZO -o "$out/Fokus-$version.dmg"
rm -f "$out/rw.dmg"
rm -rf "$stage"
print "Fertig: $out/Fokus-$version.dmg"

if [[ $publish == --publish ]]; then
  notes=${FOKUS_NOTES:-"Fokus $version"}
  gh release create "v$version" -R "$repo" --title "Fokus $version" --notes "$notes" \
    "$out/Fokus-$version.dmg" "$out/Fokus-$version.zip" "$out/Fokus-$version.zip.sig"
  print "Veröffentlicht: https://github.com/$repo/releases/tag/v$version"
fi
