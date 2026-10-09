#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 'Usage: ./scripts/package-notarized-release.sh "Developer ID Application: Name (TEAMID)" keychain-profile'
  exit 2
fi
identity="$1"
profile="$2"
cd "${0:A:h:h}"

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$identity"; then
  print -u2 'Developer ID Application certificate with private key was not found in the Keychain.'
  exit 1
fi
if ! /usr/bin/xcrun --find notarytool >/dev/null 2>&1; then
  print -u2 'notarytool is unavailable. Install current Xcode Command Line Tools.'
  exit 1
fi

./scripts/build-app.sh
source_app=""
for candidate in "$PWD"/dist/*.app(N); do
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$bundle_id" == 'local.library.reader' ]]; then source_app="$candidate"; break; fi
done
if [[ -z "$source_app" ]]; then print -u2 'Built app not found.'; exit 1; fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$source_app/Contents/Info.plist")
arch=$(/usr/bin/uname -m)
stage=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$stage"' EXIT
release_app="$stage/FishTouching Reader.app"
submission="$stage/notarization.zip"
/usr/bin/ditto "$source_app" "$release_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName FishTouching Reader' "$release_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName FishTouching Reader' "$release_app/Contents/Info.plist"
/usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "$release_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$release_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_app" "$submission"
/usr/bin/xcrun notarytool submit "$submission" --keychain-profile "$profile" --wait --output-format json > "$stage/notary-result.json"
/usr/bin/python3 - "$stage/notary-result.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as source:
    result = json.load(source)
if result.get('status') != 'Accepted':
    raise SystemExit('Apple notarization failed: ' + str(result))
print('Apple notarization accepted:', result.get('id', ''))
PY
/usr/bin/xcrun stapler staple "$release_app"
/usr/bin/xcrun stapler validate "$release_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$release_app"
/bin/mkdir -p release
archive="$PWD/release/fishtouching-reader-macos-$arch-v$version-notarized.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_app" "$archive"
/usr/bin/shasum -a 256 "$archive"
print "Notarized package: $archive"
