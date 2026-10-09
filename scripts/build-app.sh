#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
swift build -c release
existing_app=""
for candidate in "$PWD"/dist/*.app(N); do
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$bundle_id" == "local.library.reader" ]]; then existing_app="$candidate"; break; fi
done
display_name="FishTouching Reader"
if [[ -n "$existing_app" ]]; then
  display_name="${existing_app:t:r}"
fi
app_dir="$PWD/dist/$display_name.app"
if [[ -n "$existing_app" && "$existing_app" != "$app_dir" ]]; then mv "$existing_app" "$app_dir"; fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/LocalLibrary "$app_dir/Contents/MacOS/LocalLibrary"
cp Resources/index.html "$app_dir/Contents/Resources/index.html"
cp Resources/settings.html "$app_dir/Contents/Resources/settings.html"
cp scripts/rename-helper.sh "$app_dir/Contents/Resources/rename-helper.sh"
licenses_dir="$app_dir/Contents/Resources/Licenses"
rm -rf "$licenses_dir"
mkdir -p "$licenses_dir"
cp LICENSE "$licenses_dir/FishTouching-Reader-LICENSE"
cp THIRD_PARTY_NOTICES.md "$licenses_dir/THIRD_PARTY_NOTICES.md"
cp -f licenses/libsodium-LICENSE "$licenses_dir/"
icons_dir="$app_dir/Contents/Resources/Icons"
mkdir -p "$icons_dir"
swift scripts/make-icon.swift "$icons_dir/book.png"
swift scripts/make-presets.swift "$icons_dir"
iconset="$PWD/.build/LocalLibrary.iconset"
mkdir -p "$iconset"
cp "$icons_dir/fish.png" "$iconset/icon_512x512@2x.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  if (( double < 1024 )); then
    sips -z "$double" "$double" "$iconset/icon_512x512@2x.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleExecutable</key><string>LocalLibrary</string>
  <key>CFBundleIdentifier</key><string>local.library.reader</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FishTouching Reader</string>
  <key>CFBundleDisplayName</key><string>FishTouching Reader</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>100</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
APP_DISPLAY_NAME="$display_name" python3 - "$app_dir/Contents/Info.plist" <<'PY'
import os, plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as source:
    values = plistlib.load(source)
values['CFBundleName'] = os.environ['APP_DISPLAY_NAME']
values['CFBundleDisplayName'] = os.environ['APP_DISPLAY_NAME']
with open(path, 'wb') as target:
    plistlib.dump(values, target)
PY
codesign --force --sign - "$app_dir" >/dev/null
print "Built: $app_dir"
