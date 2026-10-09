#!/bin/zsh
set -euo pipefail

cd "${0:A:h:h}"
./scripts/build-app.sh

app_dir=""
for candidate in "$PWD"/dist/*.app(N); do
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$bundle_id" == "local.library.reader" ]]; then app_dir="$candidate"; break; fi
done
if [[ -z "$app_dir" ]]; then print -u2 "Built app not found"; exit 1; fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")
arch=$(/usr/bin/uname -m)
stage=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$stage"' EXIT
release_app="$stage/摸鱼阅读.app"
/usr/bin/ditto "$app_dir" "$release_app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName 摸鱼阅读' "$release_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName 摸鱼阅读' "$release_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$release_app"
/usr/bin/codesign --verify --strict "$release_app"
/bin/mkdir -p release
archive="$PWD/release/摸鱼阅读-macos-$arch-v$version.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_app" "$archive"
/usr/bin/shasum -a 256 "$archive"
print "Package: $archive"
