#!/bin/zsh
# Builds Protea.app into macos/build. Usage: ./build-app.sh [--open] [--dmg]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64

APP=build/Protea.app
BIN=$(swift build -c release --arch arm64 --show-bin-path)/Protea

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Protea"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/protea-mark.png "$APP/Contents/Resources/protea-mark.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Protea</string>
  <key>CFBundleDisplayName</key><string>Protea</string>
  <key>CFBundleIdentifier</key><string>dev.protea.app</string>
  <key>CFBundleExecutable</key><string>Protea</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSMicrophoneUsageDescription</key><string>Protea listens while you dictate a prompt to one of your sessions.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Protea turns what you say into the text of your prompt. It runs on this Mac when your language supports it.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will run it locally.
codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $(du -sh "$APP" | cut -f1) → $(pwd)/$APP"

if [[ " $* " == *" --dmg "* ]]; then
  # A drag-to-install disk image: the app next to a shortcut to /Applications.
  rm -rf build/dmg build/Protea.dmg
  mkdir -p build/dmg
  cp -R "$APP" build/dmg/
  ln -s /Applications build/dmg/Applications
  hdiutil create -volname Protea -srcfolder build/dmg -ov -format UDZO build/Protea.dmg >/dev/null
  rm -rf build/dmg
  echo "Packed $(du -sh build/Protea.dmg | cut -f1) → $(pwd)/build/Protea.dmg"
fi

if [[ " $* " == *" --open "* ]]; then open "$APP"; fi
