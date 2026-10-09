#!/bin/zsh
set -euo pipefail

app_pid="$1"
old_bundle="$2"
new_name="$3"
reopen="$4"
new_bundle="${old_bundle:h}/$new_name.app"
log_file="$HOME/Library/Logs/LocalLibrary-rename.log"
if [[ -e "$old_bundle" && -e "$new_bundle" ]]; then
  old_identity=$(/usr/bin/stat -f '%d:%i' "$old_bundle")
  new_identity=$(/usr/bin/stat -f '%d:%i' "$new_bundle")
  if [[ "$old_identity" == "$new_identity" ]]; then new_bundle="$old_bundle"; fi
fi

# The old process must release its signed bundle before changing Info.plist.
for attempt in {1..200}; do
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 0.1
done

function reopen_existing {
  if [[ "$reopen" == "1" && -d "$old_bundle" ]]; then /usr/bin/open -n "$old_bundle"; fi
}

if kill -0 "$app_pid" 2>/dev/null; then
  print "Timed out waiting for process $app_pid" >> "$log_file"
  exit 1
fi
if [[ "$old_bundle" != "$new_bundle" && -e "$new_bundle" ]]; then
  print "Target app already exists: $new_bundle" >> "$log_file"
  reopen_existing
  exit 1
fi
if [[ "$old_bundle" != "$new_bundle" ]]; then
  if ! /bin/mv "$old_bundle" "$new_bundle"; then
    print "Could not rename $old_bundle" >> "$log_file"
    reopen_existing
    exit 1
  fi
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$new_bundle" >> "$log_file" 2>&1 || true
/usr/bin/defaults write local.library.reader displayName -string "$new_name"
/usr/bin/defaults delete local.library.reader pendingDisplayName >/dev/null 2>&1 || true
if [[ "$reopen" == "1" ]]; then /usr/bin/open -n "$new_bundle"; fi
