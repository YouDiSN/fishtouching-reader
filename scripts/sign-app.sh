#!/bin/zsh
set -euo pipefail

app="${1:?Usage: sign-app.sh app-bundle}"
identity='Developer ID Application: Tengjiao Ji (DR4WPFLXBN)'
framework="$app/Contents/Frameworks/Sparkle.framework"
keychain_args=()
if [[ -n "${SIGNING_KEYCHAIN:-}" ]]; then keychain_args=(--keychain "$SIGNING_KEYCHAIN"); fi
# Sign nested executables before their containers; never select an arbitrary identity.
for component in "$framework/Versions/B/XPCServices/Downloader.xpc" \
                 "$framework/Versions/B/XPCServices/Installer.xpc" \
                 "$framework/Versions/B/Autoupdate" \
                 "$framework/Versions/B/Updater.app" "$framework" "$app"; do
  /usr/bin/codesign --force --options runtime --timestamp --sign "$identity" "${keychain_args[@]}" "$component"
done
/usr/bin/codesign --verify --deep --strict "$app"
details=$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1)
[[ "$details" == *'Authority=Developer ID Application: Tengjiao Ji (DR4WPFLXBN)'* ]]
[[ "$details" == *'TeamIdentifier=DR4WPFLXBN'* ]]
print 'Verified personal Developer ID signature: DR4WPFLXBN'
